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
	"GET_ITEM_INFO_RECEIVED",
	"ITEM_DATA_LOAD_RESULT",
}
local DEFAULTS = {
	duration = 5, maxRows = 6, fontSize = 15, iconSize = 40, width = 420,
	opacity = 1, backgroundAlpha = 0.24, qualityColors = true, skin = "glass",
	borderGlow = true, animate = true,
}
local PRESETS = {
	glass = { label = "Glass", background = { 0.012, 0.018, 0.026 }, border = { 0.58, 0.72, 0.86 }, borderAlpha = 0.24, edgeSize = 1, rowAlpha = 0.08, gap = 3 },
	classic = { label = "WoW Classic", background = { 0.13, 0.09, 0.045 }, border = { 0.58, 0.40, 0.16 }, borderAlpha = 0.95, edgeSize = 12, rowAlpha = 0.15, gap = 3, edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border" },
	ellesmere = { label = "EllesmereUI", background = { 0.018, 0.05, 0.065 }, border = { 0.12, 0.55, 0.63 }, borderAlpha = 0.9, edgeSize = 2, rowAlpha = 0.18, gap = 3 },
	minimal = { label = "Minimal", background = { 0, 0, 0 }, border = { 0.75, 0.82, 0.9 }, borderAlpha = 0.12, edgeSize = 1, rowAlpha = 0, gap = 1 },
	charcoal = { label = "Charcoal", background = { 0.025, 0.03, 0.038 }, border = { 0.35, 0.40, 0.48 }, borderAlpha = 0.62, edgeSize = 1, rowAlpha = 0.15, gap = 2 },
	arcane = { label = "Arcane", background = { 0.035, 0.018, 0.07 }, border = { 0.62, 0.35, 0.95 }, borderAlpha = 0.75, edgeSize = 2, rowAlpha = 0.16, gap = 3 },
}
loot.presets = PRESETS
local entries = {}
local eventFrame
local previewBackup, previewUntil

local function clamp(value, low, high, fallback)
	local n = ns.toNumber(value)
	if n == nil then n = fallback end
	return math.max(low, math.min(high, n))
end

local function data()
	if not ns.db then return nil end
	if ns.isSecret(ns.db.lootWindow) or type(ns.db.lootWindow) ~= "table" then ns.db.lootWindow = {} end
	local d = ns.db.lootWindow
	if d.skin == nil then d.skin = DEFAULTS.skin end
	return d
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
		fontSize = math.floor(clamp(d.fontSize, 8, 28, DEFAULTS.fontSize) + 0.5),
		iconSize = math.floor(clamp(d.iconSize, 20, 96, DEFAULTS.iconSize) + 0.5),
		width = math.floor(clamp(d.width, 280, 900, DEFAULTS.width) + 0.5),
		opacity = clamp(d.opacity, 0, 1, DEFAULTS.opacity),
		backgroundAlpha = clamp(d.backgroundAlpha, 0, 1, DEFAULTS.backgroundAlpha),
		qualityColors = flag("qualityColors", DEFAULTS.qualityColors),
		borderGlow = flag("borderGlow", DEFAULTS.borderGlow),
		animate = flag("animate", DEFAULTS.animate),
		items = flag("items", true), money = flag("money", true),
		currency = flag("currency", true), reputation = flag("reputation", true),
		skin = not ns.isSecret(d.skin) and type(d.skin) == "string" and PRESETS[d.skin] and d.skin or DEFAULTS.skin,
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

local function playerSender(sender, senderGUID)
	if not ns.isSecret(senderGUID) and type(senderGUID) == "string" and senderGUID ~= ""
		and type(_G.UnitGUID) == "function" then
		local ok, playerGUID = pcall(_G.UnitGUID, "player")
		if ok and not ns.isSecret(playerGUID) and type(playerGUID) == "string" and playerGUID ~= "" then
			return senderGUID == playerGUID
		end
	end
	if ns.isSecret(sender) then return false end
	if type(sender) ~= "string" or sender == "" then return true end
	if sender:lower() == "you" then return true end
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

local function marketUnitPrice(itemID, itemString)
	local api = _G.TSM_API
	if api and type(api.GetCustomPriceValue) == "function" then
		for _, args in ipairs({
			{ itemString, "DBMarket" },
			{ "DBMarket", itemString },
		}) do
			local ok, result = pcall(api.GetCustomPriceValue, args[1], args[2])
			local value = ok and ns.toNumber(result) or nil
			if value and value > 0 then return value end
		end
	end
	if api and type(api.GetCustomPrice) == "function" then
		local ok, result = pcall(api.GetCustomPrice, "dbmarket", itemID)
		local value = ok and ns.toNumber(result) or nil
		if value and value > 0 then return value end
	end
	local auctionator = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
	if auctionator and type(auctionator.GetAuctionPriceByItemID) == "function" then
		local ok, value = pcall(auctionator.GetAuctionPriceByItemID, "DoHelper", itemID)
		value = ok and ns.toNumber(value) or nil
		if value and value > 0 then return value end
	end
	return nil
end

local function itemValues(itemID, itemString, quantity)
	local market = marketUnitPrice(itemID, itemString)
	local getter = _G.GetItemInfo
	local vendor
	if type(getter) == "function" then
		local ok, values = pcall(function()
			local info = ns.pack(getter(itemString))
			return info[11]
		end)
		local sellPrice = ok and values or nil
		sellPrice = ok and ns.toNumber(sellPrice) or nil
		if sellPrice and sellPrice > 0 then vendor = sellPrice * quantity end
	end
	local chosen = market and market * quantity or vendor
	return chosen, market and "AH" or vendor and "Vendor" or nil
end

local function formatMoney(copper)
	copper = math.max(0, math.floor(ns.toNumber(copper) or 0))
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local remainder = copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. "g" end
	if silver > 0 then parts[#parts + 1] = silver .. "s" end
	if remainder > 0 or #parts == 0 then parts[#parts + 1] = remainder .. "c" end
	return table.concat(parts, " ")
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

local function moneyIcon(message)
	local embedded = message:match("|T([^:|]+)")
	if embedded then return embedded end
	local lower = message:lower()
	if lower:match("%d+%s+gold") or lower:find("gold", 1, true) then return "Interface\\Icons\\INV_Misc_Coin_03" end
	if lower:match("%d+%s+silver") or lower:find("silver", 1, true) then return "Interface\\Icons\\INV_Misc_Coin_02" end
	return "Interface\\Icons\\INV_Misc_Coin_01"
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
	handle:SetSize(DEFAULTS.width, 7)
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
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.glow = row:CreateTexture(nil, "OVERLAY")
	row.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	if type(row.glow.SetBlendMode) == "function" then row.glow:SetBlendMode("ADD") end
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetJustifyH("RIGHT")
	row.value:SetWordWrap(false)
	row.quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.quantity:SetJustifyH("RIGHT")
	row.quantity:SetJustifyV("BOTTOM")
	row.quantity:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -1)
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
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function(self)
		if type(_G.IsShiftKeyDown) ~= "function" or not _G.IsShiftKeyDown() then return end
		local parent = self:GetParent()
		if parent and parent.StartMoving then parent:StartMoving() end
	end)
	row:SetScript("OnDragStop", function(self)
		local parent = self:GetParent()
		if parent and parent.StopMovingOrSizing then parent:StopMovingOrSizing(); rememberPosition(parent) end
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
	local skin = PRESETS[style.skin] or PRESETS.glass
	local gap = skin.gap or 3
	local rowHeight = math.max(style.iconSize + 4, style.fontSize * 2 + 8)
	local height = 10 + count * rowHeight + (count - 1) * gap + 8
	frame:SetSize(style.width, height)
	if frame.dragHandle then frame.dragHandle:SetWidth(style.width) end
	for i = 1, count do
		local row = makeRow(frame, i)
		local entry = entries[i]
		local y = -9 - (i - 1) * (rowHeight + gap)
		local current = now()
		local age = math.max(0, current - (entry.created or current))
		local slide = style.animate and math.max(0, 1 - age / 0.18) or 0
		local fade = entry.expires and math.min(1, math.max(0, (entry.expires - current) / 0.4)) or 1
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y + (slide * 10))
		row:SetSize(style.width - 16, rowHeight)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
		row.icon:SetSize(style.iconSize, style.iconSize)
		row.icon:SetTexture(entry.icon)
		row.glow:ClearAllPoints()
		row.glow:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
		row.glow:SetSize(style.iconSize + 22, style.iconSize + 22)
		row.bg:SetVertexColor(skin.border[1], skin.border[2], skin.border[3], skin.rowAlpha or 0)
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 6)
		row.name:SetPoint("RIGHT", row, "RIGHT", -92, 6)
		row.name:SetText(entry.text)
		setTextStyle(row.name, style.fontSize)
		row.value:ClearAllPoints()
		row.value:SetPoint("RIGHT", row, "RIGHT", -2, 5)
		row.value:SetWidth(88)
		row.value:SetText(entry.value and ((entry.valueLabel and (entry.valueLabel .. " ") or "") .. formatMoney(entry.value)) or "")
		setTextStyle(row.value, math.max(10, style.fontSize - 2))
		row.value:SetTextColor(1, 0.82, 0.28, 1)
		row.quantity:SetFont((ns.ui and ns.ui.FONT) or "Fonts\\ARIALN.TTF", math.max(10, style.fontSize - 2), "OUTLINE")
		row.quantity:SetText(entry.quantity and entry.quantity > 1 and tostring(entry.quantity) or "")
		if entry.color and style.qualityColors then
			row.name:SetTextColor(entry.color[1], entry.color[2], entry.color[3], 1)
		elseif ns.ui and ns.ui.colors and ns.ui.colors.text then
			row.name:SetTextColor(ns.ui.colors.text[1], ns.ui.colors.text[2], ns.ui.colors.text[3], 1)
		else
			row.name:SetTextColor(1, 1, 1, 1)
		end
		local glowColor = (style.qualityColors and entry.color) or skin.border
		row.glow:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], style.borderGlow and (entry.color and style.qualityColors and 0.72 or 0.30) or 0)
		row.itemLink = entry.link
		row:SetAlpha((style.animate and math.min(1, age / 0.12) or 1) * fade)
		row:Show()
	end
	for i = count + 1, #frame.rows do frame.rows[i]:Hide(); frame.rows[i].itemLink = nil end
	loot.ApplyStyle()
	frame:Show()
	local updating = false
	for _, entry in ipairs(entries) do
		if entry.expires or (style.animate and now() - (entry.created or 0) < 0.18) then updating = true; break end
	end
	frame:SetScript("OnUpdate", updating and loot.OnUpdate or nil)
end

function loot.ApplyStyle()
	local frame = loot.window
	if not frame then return end
	local style = loot.Style()
	local skin = PRESETS[style.skin] or PRESETS.glass
	local edge = skin.edgeFile or "Interface\\Buttons\\WHITE8X8"
	if frame.SetBackdrop then frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = edge,
		edgeSize = skin.edgeSize,
		insets = { left = skin.edgeSize > 2 and 8 or 1, right = skin.edgeSize > 2 and 8 or 1,
			top = skin.edgeSize > 2 and 8 or 1, bottom = skin.edgeSize > 2 and 8 or 1 },
	}) end
	if frame.SetBackdropColor then frame:SetBackdropColor(skin.background[1], skin.background[2], skin.background[3], style.backgroundAlpha) end
	if frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(skin.border[1], skin.border[2], skin.border[3], skin.borderAlpha or 1)
	end
	if frame.SetAlpha then frame:SetAlpha(style.opacity) end
	if #entries > 0 then
		for i = 1, math.min(#entries, style.maxRows) do
			local row = frame.rows[i]
			if row and row:IsShown() then
				setTextStyle(row.name, style.fontSize)
				local entry = entries[i]
				if entry.color and style.qualityColors then row.name:SetTextColor(entry.color[1], entry.color[2], entry.color[3], 1)
				elseif ns.ui and ns.ui.colors and ns.ui.colors.text then
					local c = ns.ui.colors.text; row.name:SetTextColor(c[1], c[2], c[3], 1)
				end
				row.bg:SetVertexColor(skin.border[1], skin.border[2], skin.border[3], skin.rowAlpha or 0)
				local glowColor = (style.qualityColors and entry.color) or skin.border
				row.glow:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], style.borderGlow and (entry.color and style.qualityColors and 0.72 or 0.30) or 0)
			end
		end
	end
end

function loot.SavePosition()
	rememberPosition(loot.window)
end

local function addEntry(kind, text, icon, link, color, details)
	local style = loot.Style()
	local current = now()
	if previewBackup and not buildingPreview then
		entries = previewBackup
		previewBackup, previewUntil = nil, nil
	end
	for index = #entries, 1, -1 do
		local expires = entries[index].expires
		if expires and current >= expires then table.remove(entries, index) end
	end
	if #entries >= 12 then table.remove(entries, #entries) end
	local entry = { kind = kind, text = text, icon = icon, link = link, color = color, created = current }
	for key, value in pairs(details or {}) do entry[key] = value end
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
	local quantity = tonumber(message:match("|h|r%s*[xX×]%s*(%d+)")
		or message:match("|h%s*[xX×]%s*(%d+)"))
	if not quantity then
		local linkStart = message:find("|Hitem:", 1, true)
		local prefix = linkStart and message:sub(1, linkStart - 1) or ""
		quantity = tonumber(prefix:match("(%d+)%s*[xX×]%s*$"))
	end
	quantity = quantity or 1
	quantity = math.max(1, math.floor(quantity))
	local r, g, b
	if loot.Style().qualityColors then r, g, b = itemColor(message) end
	local color = r and { r, g, b } or nil
	local value, valueLabel = itemValues(itemID, itemString, quantity)
	local added = addEntry("item", name, itemIcon(itemID, message), itemString, color, {
		itemID = itemID, itemString = itemString, quantity = quantity,
		value = value, valueLabel = valueLabel,
	})
	if not value and _G.C_Item and type(_G.C_Item.RequestLoadItemDataByID) == "function" then
		pcall(_G.C_Item.RequestLoadItemDataByID, itemID)
	end
	return added
end

local function addMessage(kind, message)
	local text = plainMessage(message)
	if not text then return false end
	local icon = message:match("|T([^:|]+)")
	if not icon and kind == "currency" then icon = currencyIcon(message) end
	if not icon and kind == "money" then icon = moneyIcon(message) end
	if not icon then
		icon = kind == "reputation" and "Interface\\Icons\\Achievement_Reputation_01"
			or "Interface\\Icons\\INV_Misc_Coin_02"
	end
	return addEntry(kind, text, icon)
end

local function refreshItemInfo(itemID)
	for _, entry in ipairs(entries) do
		if entry.kind == "item" and entry.itemID == itemID then
			entry.icon = itemIcon(itemID, entry.link or "")
			entry.value, entry.valueLabel = itemValues(itemID, entry.itemString, entry.quantity or 1)
		end
	end
	loot.Refresh()
end

function loot.Clear()
	entries = {}
	previewBackup = nil
	local frame = loot.window
	if frame then frame:SetScript("OnUpdate", nil); frame:Hide() end
end

function loot.OnUpdate()
	local current = now()
	if previewBackup and previewUntil and current >= previewUntil then
		entries = previewBackup
		previewBackup, previewUntil = nil, nil
		for index = #entries, 1, -1 do
			if entries[index].expires and current >= entries[index].expires then table.remove(entries, index) end
		end
		render()
		return
	end
	local before = #entries
	for index = #entries, 1, -1 do
		local expires = entries[index].expires
		if expires and current >= expires then table.remove(entries, index) end
	end
	local style = loot.Style()
	local timed, animating, fading = false, false, false
	for _, entry in ipairs(entries) do
		if entry.expires then
			timed = true
			if entry.expires - current < 0.4 then fading = true end
		end
		if style.animate and current - (entry.created or current) < 0.18 then animating = true end
	end
	if #entries ~= before or animating or fading then render() end
	if not timed and not animating and loot.window then loot.window:SetScript("OnUpdate", nil) end
	if #entries == 0 and loot.window then loot.window:Hide() end
end

function loot.HandleEvent(event, message, sender, senderGUID)
	if not loot.Enabled() then return false end
	if event == "CHAT_MSG_LOOT" then
		local style = loot.Style()
		if not style.items or not playerSender(sender, senderGUID) then return false end
		return parseItem(message)
	elseif event == "CHAT_MSG_MONEY" then
		if loot.Style().money and playerSender(sender, senderGUID) then return addMessage("money", message) end
	elseif event == "CHAT_MSG_CURRENCY" then
		if loot.Style().currency and playerSender(sender, senderGUID) then return addMessage("currency", message) end
	elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
		if loot.Style().reputation and playerSender(sender, senderGUID) then return addMessage("reputation", message) end
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
		local itemID = ns.toNumber(message)
		if itemID then refreshItemInfo(itemID); return true end
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
			duration = { 0, 30 }, maxRows = { 1, 12 }, fontSize = { 8, 28 },
			iconSize = { 20, 96 }, width = { 280, 900 }, opacity = { 0, 1 }, backgroundAlpha = { 0, 1 },
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
	if style.qualityColors ~= nil and not ns.isSecret(style.qualityColors) then d.qualityColors = style.qualityColors and true or false end
	if style.borderGlow ~= nil and not ns.isSecret(style.borderGlow) then d.borderGlow = style.borderGlow and true or false end
	if style.animate ~= nil and not ns.isSecret(style.animate) then d.animate = style.animate and true or false end
	loot.Refresh()
	return true
end

function loot.SetSkin(key)
	if ns.isSecret(key) or type(key) ~= "string" or not PRESETS[key] then return false end
	local d = data()
	if not d then return false end
	d.skin = key
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
	if not previewBackup then previewBackup = entries end
	local current = now()
	entries = {
		{
			kind = "item", text = "STYLE PREVIEW · Example drop", icon = "Interface\\Icons\\INV_Misc_QuestionMark",
			quantity = 3, value = 12345, valueLabel = "Preview", created = current,
			expires = current + 2.5, isPreview = true,
		},
	}
	previewUntil = current + 2.5
	render()
	return true
end

function loot.Toggle()
	local frame = ensureWindow()
	if not frame then return nil end
	if frame:IsShown() then frame:Hide()
	else
		loot.OnUpdate()
		if #entries > 0 then render() else frame:Hide() end
	end
	return frame
end

function loot.Setup()
	if eventFrame or type(_G.CreateFrame) ~= "function" then return end
	eventFrame = _G.CreateFrame("Frame")
	loot.eventFrame = eventFrame
	eventFrame:SetScript("OnEvent", function(_, event, ...)
		local message, sender = ...
		local senderGUID = select(12, ...)
		loot.HandleEvent(event, message, sender, senderGUID)
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
