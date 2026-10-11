-- DoHelper / LootWindow.lua
-- Optional, player-only loot feed. It listens to the normal client loot chat
-- events, keeps a short bounded list, and owns a separate movable display.
local _, ns = ...
local loot = {}
ns.lootWindow = loot

local EVENT_NAMES = {
	"CHAT_MSG_LOOT",
	"CHAT_MSG_MONEY",
	"CHAT_MSG_CURRENCY",
	"CHAT_MSG_COMBAT_FACTION_CHANGE",
}
local DEFAULTS = {
	duration = 6, maxRows = 6, fontSize = 13, iconSize = 24, width = 320,
	opacity = 1, backgroundAlpha = 0.78, qualityColors = true,
}
local entries = {}
local eventFrame

local function clamp(value, low, high, fallback)
	local n = ns.toNumber(value)
	if n == nil then n = fallback end
	return math.max(low, math.min(high, n))
end

local function data()
	if not ns.db then return nil end
	if ns.isSecret(ns.db.lootWindow) or type(ns.db.lootWindow) ~= "table" then ns.db.lootWindow = {} end
	return ns.db.lootWindow
end

function loot.Enabled()
	local d = data()
	return d and not ns.isSecret(d.enabled) and d.enabled == true or false
end

function loot.Style()
	local d = data() or {}
	local function flag(key, fallback)
		local value = d[key]
		if ns.isSecret(value) then return fallback end
		return value ~= false
	end
	return {
		duration = clamp(d.duration, 0, 30, DEFAULTS.duration),
		maxRows = math.floor(clamp(d.maxRows, 1, 12, DEFAULTS.maxRows) + 0.5),
		fontSize = math.floor(clamp(d.fontSize, 8, 24, DEFAULTS.fontSize) + 0.5),
		iconSize = math.floor(clamp(d.iconSize, 16, 40, DEFAULTS.iconSize) + 0.5),
		width = math.floor(clamp(d.width, 220, 520, DEFAULTS.width) + 0.5),
		opacity = clamp(d.opacity, 0, 1, DEFAULTS.opacity),
		backgroundAlpha = clamp(d.backgroundAlpha, 0, 1, DEFAULTS.backgroundAlpha),
		qualityColors = flag("qualityColors", DEFAULTS.qualityColors),
		items = flag("items", true), money = flag("money", true),
		currency = flag("currency", true), reputation = flag("reputation", true),
		x = clamp(d.x, -4000, 4000, 0),
		y = clamp(d.y, -4000, 4000, -180),
	}
end

local function now()
	if type(_G.GetTime) == "function" then
		local ok, value = pcall(_G.GetTime)
		if ok and not ns.isSecret(value) then return ns.toNumber(value) or 0 end
	end
	return 0
end

local function playerSender(sender)
	if ns.isSecret(sender) then return false end
	if type(sender) ~= "string" or sender == "" then return true end
	if type(_G.UnitName) ~= "function" then return false end
	local ok, name, realm = pcall(_G.UnitName, "player")
	if not ok or ns.isSecret(name) or type(name) ~= "string" or name == "" then return false end
	local senderLower = sender:lower()
	local nameLower = name:lower()
	if senderLower == nameLower then return true end
	if senderLower:match("^([^%-]+)") == nameLower then return true end
	if type(realm) == "string" and realm ~= "" then
		local qualified = (name .. "-" .. realm):lower()
		if senderLower == qualified then return true end
	end
	if type(_G.UnitFullName) == "function" then
		local fullOK, fullName, fullRealm = pcall(_G.UnitFullName, "player")
		if fullOK and type(fullName) == "string" and fullName ~= "" then
			local qualified = fullName .. (type(fullRealm) == "string" and fullRealm ~= "" and ("-" .. fullRealm) or "")
			if senderLower == qualified:lower() then return true end
		end
	end
	return false
end

local function plainMessage(message)
	if ns.isSecret(message) or type(message) ~= "string" then return nil end
	local text = message
		:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|r", "")
		:gsub("|H[^|]+|h(.-)|h", "%1")
		:gsub("|T[^|]+|t", "")
		:gsub("|A[^|]+|a", "")
		:gsub("%s+", " ")
		:gsub("^%s+", "")
		:gsub("%s+$", "")
	if text == "" then return nil end
	return text
end

local function itemLinkFrom(message)
	return message:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r)")
		or message:match("(|Hitem:[^|]+|h.-|h)")
end

local function itemColor(message)
	local hex = message:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
	if not hex then return nil end
	return tonumber(hex:sub(3, 4), 16) / 255,
		tonumber(hex:sub(5, 6), 16) / 255,
		tonumber(hex:sub(7, 8), 16) / 255
end

local function itemIcon(itemID, message)
	local path = message:match("|T([^:|]+)")
	if path then return path end
	if _G.C_Item and type(_G.C_Item.GetItemIconByID) == "function" then
		local ok, value = pcall(_G.C_Item.GetItemIconByID, itemID)
		if ok and not ns.isSecret(value) and (type(value) == "number" or type(value) == "string") then return value end
	end
	if type(_G.GetItemInfoInstant) == "function" then
		local ok, _, _, _, _, value = pcall(_G.GetItemInfoInstant, itemID)
		if ok and not ns.isSecret(value) and (type(value) == "number" or type(value) == "string") then return value end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function currencyIcon(message)
	local id = tonumber(message:match("|Hcurrency:(%d+)"))
	if not id then return nil end
	if _G.C_CurrencyInfo and type(_G.C_CurrencyInfo.GetCurrencyInfo) == "function" then
		local ok, info = pcall(_G.C_CurrencyInfo.GetCurrencyInfo, id)
		if ok and not ns.isSecret(info) and type(info) == "table" then
			local icon = not ns.isSecret(info.iconFileID) and info.iconFileID or nil
			if not icon and not ns.isSecret(info.icon) then icon = info.icon end
			if type(icon) == "string" or type(icon) == "number" then return icon end
		end
	end
	if type(_G.GetCurrencyInfo) == "function" then
		local ok, _, _, icon = pcall(_G.GetCurrencyInfo, id)
		if ok and not ns.isSecret(icon) and (type(icon) == "string" or type(icon) == "number") then return icon end
	end
	return nil
end

local function playerCenter()
	local parent = _G.UIParent
	if parent and type(parent.GetCenter) == "function" then
		local ok, x, y = pcall(parent.GetCenter, parent)
		if ok then return ns.toNumber(x) or 0, ns.toNumber(y) or 0 end
	end
	return 0, 0
end

local function rememberPosition(frame)
	if not frame or type(frame.GetCenter) ~= "function" then return end
	local ok, x, y = pcall(frame.GetCenter, frame)
	if not ok then return end
	x, y = ns.toNumber(x), ns.toNumber(y)
	if x == nil or y == nil then return end
	local centerX, centerY = playerCenter()
	local d = data()
	if d then d.x, d.y = clamp(x - centerX, -4000, 4000, 0), clamp(y - centerY, -4000, 4000, -180) end
end

local function setTextStyle(region, size)
	if not region then return end
	local font = (ns.ui and ns.ui.FONT) or "Fonts\\FRIZQT__.TTF"
	if type(region.SetFont) == "function" then region:SetFont(font, size, "") end
	if type(region.SetShadowOffset) == "function" then region:SetShadowOffset(1, -1) end
end

local function ensureWindow()
	if loot.window then return loot.window end
	if type(_G.CreateFrame) ~= "function" then return nil end
	local frame = _G.CreateFrame("Frame", "DoHelperLootWindow", _G.UIParent, "BackdropTemplate")
	loot.window = frame
	frame:SetSize(DEFAULTS.width, 50)
	local saved = loot.Style()
	frame:SetPoint("CENTER", _G.UIParent, "CENTER", saved.x, saved.y)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	if type(frame.SetToplevel) == "function" then frame:SetToplevel(true) end

	local handle = _G.CreateFrame("Frame", nil, frame)
	handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	handle:SetSize(DEFAULTS.width, 30)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function(self)
		local parent = self:GetParent()
		if parent and parent.StartMoving then parent:StartMoving() end
	end)
	handle:SetScript("OnDragStop", function(self)
		local parent = self:GetParent()
		if parent and parent.StopMovingOrSizing then parent:StopMovingOrSizing(); rememberPosition(parent) end
	end)
	frame.dragHandle = handle

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
	frame.title:SetText("Loot")
	if ns.ui and ns.ui.Text then ns.ui.Text(frame.title, "section") else setTextStyle(frame.title, 13) end

	local close = _G.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame.closeButton = close
	frame.rows = {}

	frame:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	loot.ApplyStyle()
	return frame
end

local function makeRow(frame, index)
	local row = frame.rows[index]
	if row then return row end
	row = _G.CreateFrame("Frame", nil, frame)
	row:EnableMouse(true)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		if not self.itemLink or not _G.GameTooltip then return end
		local link = self.itemLink
		if ns.isSecret(link) then return end
		local itemString = link:match("|H(item:[^|]+)|h")
		if itemString then
			_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			_G.GameTooltip:SetHyperlink(itemString)
			_G.GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		if _G.GameTooltip then _G.GameTooltip:Hide() end
	end)
	frame.rows[index] = row
	return row
end

local function render()
	local frame = ensureWindow()
	if not frame then return end
	local style = loot.Style()
	local count = math.min(#entries, style.maxRows)
	if count == 0 then frame:Hide(); frame:SetScript("OnUpdate", nil); return end
	local rowHeight = math.max(style.iconSize, style.fontSize + 4) + 5
	local height = 32 + count * rowHeight + 6
	frame:SetSize(style.width, height)
	if frame.dragHandle then frame.dragHandle:SetWidth(style.width) end
	frame.title:SetText("Loot")
	frame.title:SetFont((ns.ui and ns.ui.FONT) or "Fonts\\FRIZQT__.TTF", math.max(10, style.fontSize), "")
	if ns.ui and ns.ui.colors and ns.ui.colors.accent then
		frame.title:SetTextColor(ns.ui.colors.accent[1], ns.ui.colors.accent[2], ns.ui.colors.accent[3], 1)
	end
	for i = 1, count do
		local row = makeRow(frame, i)
		local entry = entries[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30 - (i - 1) * rowHeight)
		row:SetSize(style.width - 20, rowHeight)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.icon:SetSize(style.iconSize, style.iconSize)
		row.icon:SetTexture(entry.icon)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.text:SetWidth(math.max(20, style.width - style.iconSize - 42))
		row.text:SetText(entry.text)
		setTextStyle(row.text, style.fontSize)
		if entry.color and style.qualityColors then
			row.text:SetTextColor(entry.color[1], entry.color[2], entry.color[3], 1)
		elseif ns.ui and ns.ui.colors and ns.ui.colors.text then
			row.text:SetTextColor(ns.ui.colors.text[1], ns.ui.colors.text[2], ns.ui.colors.text[3], 1)
		else
			row.text:SetTextColor(1, 1, 1, 1)
		end
		row.itemLink = entry.link
		row:Show()
	end
	for i = count + 1, #frame.rows do frame.rows[i]:Hide(); frame.rows[i].itemLink = nil end
	loot.ApplyStyle()
	frame:Show()
	local timed = false
	for _, entry in ipairs(entries) do if entry.expires then timed = true; break end end
	frame:SetScript("OnUpdate", timed and loot.OnUpdate or nil)
end

function loot.ApplyStyle()
	local frame = loot.window
	if not frame then return end
	local style = loot.Style()
	if ns.ui and ns.ui.Surface then ns.ui.Surface(frame, ns.ui.colors.window) end
	local windowColor = ns.ui and ns.ui.colors and ns.ui.colors.window or { 0.04, 0.05, 0.07, 1 }
	if frame.SetBackdropColor then frame:SetBackdropColor(windowColor[1], windowColor[2], windowColor[3], style.backgroundAlpha) end
	if frame.SetBackdropBorderColor and ns.ui and ns.ui.colors and ns.ui.colors.border then
		local c = ns.ui.colors.border
		frame:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
	end
	if frame.SetAlpha then frame:SetAlpha(style.opacity) end
	if frame.title then
		setTextStyle(frame.title, math.max(10, style.fontSize))
		if ns.ui and ns.ui.colors and ns.ui.colors.accent then
			local c = ns.ui.colors.accent
			frame.title:SetTextColor(c[1], c[2], c[3], 1)
		end
	end
	if #entries > 0 then
		-- Re-layout existing rows when skin or appearance settings change.
		for i = 1, math.min(#entries, style.maxRows) do
			local row = frame.rows[i]
			if row and row:IsShown() then
				setTextStyle(row.text, style.fontSize)
				local entry = entries[i]
				if entry.color and style.qualityColors then row.text:SetTextColor(entry.color[1], entry.color[2], entry.color[3], 1)
				elseif ns.ui and ns.ui.colors and ns.ui.colors.text then
					local c = ns.ui.colors.text; row.text:SetTextColor(c[1], c[2], c[3], 1)
				end
			end
		end
	end
end

function loot.SavePosition()
	rememberPosition(loot.window)
end

local function addEntry(kind, text, icon, link, color)
	local style = loot.Style()
	local current = now()
	for index = #entries, 1, -1 do
		local expires = entries[index].expires
		if expires and current >= expires then table.remove(entries, index) end
	end
	if #entries >= 12 then table.remove(entries, #entries) end
	local entry = { kind = kind, text = text, icon = icon, link = link, color = color }
	if style.duration > 0 then entry.expires = current + style.duration end
	table.insert(entries, 1, entry)
	while #entries > style.maxRows do table.remove(entries) end
	render()
	return true
end

local function parseItem(message)
	local link = itemLinkFrom(message)
	if not link then return false end
	local itemString = link:match("|H(item:[^|]+)|h")
	local itemID = itemString and tonumber(itemString:match("^item:(%d+)"))
	if not itemID then return false end
	local name = link:match("|h%[(.-)%]|h") or plainMessage(link) or ("Item " .. itemID)
	local quantity = tonumber(message:match("|h|r%s*[xX](%d+)") or message:match("|h%s*[xX](%d+)")) or 1
	quantity = math.max(1, math.floor(quantity))
	if quantity > 1 then name = name .. " × " .. quantity end
	local r, g, b
	if loot.Style().qualityColors then r, g, b = itemColor(message) end
	local color = r and { r, g, b } or nil
	return addEntry("item", name, itemIcon(itemID, message), itemString, color)
end

local function addMessage(kind, message)
	local text = plainMessage(message)
	if not text then return false end
	local icon = message:match("|T([^:|]+)")
	if not icon and kind == "currency" then icon = currencyIcon(message) end
	if not icon then
		icon = kind == "money" and "Interface\\Icons\\INV_Misc_Coin_01"
			or kind == "reputation" and "Interface\\Icons\\Achievement_Reputation_01"
			or "Interface\\Icons\\INV_Misc_Coin_02"
	end
	return addEntry(kind, text, icon)
end

function loot.Clear()
	entries = {}
	local frame = loot.window
	if frame then frame:SetScript("OnUpdate", nil); frame:Hide() end
end

function loot.OnUpdate()
	local current = now()
	local before = #entries
	for index = #entries, 1, -1 do
		local expires = entries[index].expires
		if expires and current >= expires then table.remove(entries, index) end
	end
	if #entries ~= before then render() end
	local timed = false
	for _, entry in ipairs(entries) do if entry.expires then timed = true; break end end
	if not timed and loot.window then loot.window:SetScript("OnUpdate", nil) end
	if #entries == 0 and loot.window then loot.window:Hide() end
end

function loot.HandleEvent(event, message, sender)
	if not loot.Enabled() then return false end
	if event == "CHAT_MSG_LOOT" then
		local style = loot.Style()
		if not style.items or not playerSender(sender) then return false end
		return parseItem(message)
	elseif event == "CHAT_MSG_MONEY" then
		if loot.Style().money and playerSender(sender) then return addMessage("money", message) end
	elseif event == "CHAT_MSG_CURRENCY" then
		if loot.Style().currency and playerSender(sender) then return addMessage("currency", message) end
	elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
		if loot.Style().reputation and playerSender(sender) then return addMessage("reputation", message) end
	end
	return false
end

function loot.SetEnabled(enabled)
	if ns.isSecret(enabled) then return false, "Enable setting is unreadable." end
	local d = data()
	if not d then return false, "Settings unavailable." end
	d.enabled = enabled and true or false
	if eventFrame then
		for _, event in ipairs(EVENT_NAMES) do
			if d.enabled then pcall(eventFrame.RegisterEvent, eventFrame, event)
			else pcall(eventFrame.UnregisterEvent, eventFrame, event) end
		end
	end
	if not d.enabled then loot.Clear() end
	return true
end

function loot.SetStyle(style)
	if type(style) ~= "table" then return false, "No loot appearance settings supplied." end
	local values = {}
	for _, key in ipairs({ "duration", "maxRows", "fontSize", "iconSize", "width", "opacity", "backgroundAlpha" }) do
		local value = ns.toNumber(style[key])
		local limits = {
			duration = { 0, 30 }, maxRows = { 1, 12 }, fontSize = { 8, 24 },
			iconSize = { 16, 40 }, width = { 220, 520 }, opacity = { 0, 1 }, backgroundAlpha = { 0, 1 },
		}
		local range = limits[key]
		if not ns.isFinite(value) or value < range[1] or value > range[2] then
			return false, "Loot settings are outside their allowed ranges; nothing changed."
		end
		values[key] = (key == "opacity" or key == "backgroundAlpha") and value or math.floor(value + 0.5)
	end
	local d = data()
	if not d then return false, "Settings unavailable." end
	for key, value in pairs(values) do d[key] = value end
	d.qualityColors = not ns.isSecret(style.qualityColors) and style.qualityColors and true or false
	loot.Refresh()
	return true
end

function loot.SetCategory(key, value)
	if ns.isSecret(key) or type(key) ~= "string" or ns.isSecret(value) then return false end
	if key ~= "items" and key ~= "money" and key ~= "currency" and key ~= "reputation" then return false end
	local d = data()
	if not d then return false end
	d[key] = value and true or false
	return true
end

function loot.Refresh()
	if #entries > 0 then
		local style = loot.Style()
		while #entries > style.maxRows do table.remove(entries) end
		render()
	else
		loot.ApplyStyle()
	end
end

function loot.Preview()
	entries = {}
	local ok = addEntry("item", "Example item × 2", "Interface\\Icons\\INV_Misc_QuestionMark")
	addEntry("money", "You loot 2 gold, 34 silver.", "Interface\\Icons\\INV_Misc_Coin_01")
	addEntry("reputation", "Your reputation with Example faction increased.", "Interface\\Icons\\Achievement_Reputation_01")
	return ok
end

function loot.Toggle()
	local frame = ensureWindow()
	if not frame then return nil end
	loot.OnUpdate()
	if frame:IsShown() then frame:Hide()
	elseif #entries > 0 then render()
	else loot.Preview() end
	return frame
end

function loot.Setup()
	if eventFrame or type(_G.CreateFrame) ~= "function" then return end
	eventFrame = _G.CreateFrame("Frame")
	loot.eventFrame = eventFrame
	eventFrame:SetScript("OnEvent", function(_, event, ...)
		loot.HandleEvent(event, ...)
	end)
	if loot.Enabled() then
		for _, event in ipairs(EVENT_NAMES) do pcall(eventFrame.RegisterEvent, eventFrame, event) end
	end
end

function loot.Entries()
	local result = {}
	for i, entry in ipairs(entries) do result[i] = entry end
	return result
end
