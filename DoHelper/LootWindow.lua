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
	labelXOffset = 0, labelYOffset = 0, amountXOffset = 0, amountYOffset = 0,
	fontFace = "default", fontOutline = "none", frameStrata = "DIALOG",
	opacity = 1, backgroundAlpha = 0.24, qualityColors = true, skin = "glass",
	borderGlow = true, animate = true,
}
local FRAME_STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
local validStrata = {}
for _, strata in ipairs(FRAME_STRATA) do validStrata[strata] = true end
loot.strataLevels = FRAME_STRATA
local FONT_FACES = {
	default = false,
	friz = "Fonts\\FRIZQT__.TTF",
	arial = "Fonts\\ARIALN.TTF",
	morpheus = "Fonts\\MORPHEUS.TTF",
	skurri = "Fonts\\SKURRI.TTF",
}
local FONT_OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
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
local previewBackup

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
		labelXOffset = math.floor(clamp(d.labelXOffset, -120, 120, DEFAULTS.labelXOffset) + 0.5),
		labelYOffset = math.floor(clamp(d.labelYOffset, -60, 60, DEFAULTS.labelYOffset) + 0.5),
		amountXOffset = math.floor(clamp(d.amountXOffset, -120, 120, DEFAULTS.amountXOffset) + 0.5),
		amountYOffset = math.floor(clamp(d.amountYOffset, -60, 60, DEFAULTS.amountYOffset) + 0.5),
		fontFace = not ns.isSecret(d.fontFace) and type(d.fontFace) == "string" and FONT_FACES[d.fontFace] ~= nil and d.fontFace or DEFAULTS.fontFace,
		fontOutline = not ns.isSecret(d.fontOutline) and type(d.fontOutline) == "string" and FONT_OUTLINES[d.fontOutline] ~= nil and d.fontOutline or DEFAULTS.fontOutline,
		frameStrata = not ns.isSecret(d.frameStrata) and type(d.frameStrata) == "string" and validStrata[d.frameStrata] and d.frameStrata or DEFAULTS.frameStrata,
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

local function numericPart(value)
	if type(value) ~= "string" then return nil end
	local digits = value:gsub("[^%d]", "")
	return tonumber(digits)
end

local function linkQuantity(message, linkType)
	local quantity = tonumber(message:match("|h|r%s*[xX×]%s*(%d+)")
		or message:match("|h%s*[xX×]%s*(%d+)")
		or message:match("[xX×]%s*(%d+)%s*[%.!]*%s*$"))
	if quantity then return math.max(1, math.floor(quantity)) end
	local startAt = message:find("|H" .. linkType .. ":", 1, true)
	local prefix = startAt and message:sub(1, startAt - 1) or ""
	quantity = numericPart(prefix:match("([%d,]+)%s*[xX×]?%s*$"))
	return quantity and math.max(1, math.floor(quantity)) or nil
end

local function currencyName(message)
	return message:match("|Hcurrency:[^|]+|h%[(.-)%]|h")
		or (plainMessage(message) or ""):gsub("^.-:%s*", ""):gsub("%s*[xX×]%s*[%d,]+%s*[%.!]*%s*$", "")
end

local function moneyAmount(message)
	local copper, found = 0, false
	for amount, texture in message:gmatch("([%d,]+).-|T([^:|]+)") do
		local value, path = numericPart(amount), texture:lower()
		if value then
			if path:find("goldicon", 1, true) then copper = copper + value * 10000; found = true
			elseif path:find("silvericon", 1, true) then copper = copper + value * 100; found = true
			elseif path:find("coppericon", 1, true) then copper = copper + value; found = true end
		end
	end
	if found then return copper end
	local text = plainMessage(message) or ""
	local function addPattern(pattern, multiplier)
		local value = numericPart(text:match(pattern))
		if value then copper = copper + value * multiplier; found = true end
	end
	addPattern("([%d,]+)%s*[Gg]old", 10000)
	addPattern("([%d,]+)%s*[Ss]ilver", 100)
	addPattern("([%d,]+)%s*[Cc]opper", 1)
	addPattern("([%d,]+)%s*[Gg]%f[%W]", 10000)
	addPattern("([%d,]+)%s*[Ss]%f[%W]", 100)
	addPattern("([%d,]+)%s*[Cc]%f[%W]", 1)
	return found and copper or nil
end

local function reputationGain(message)
	local amount = numericPart(message:match("[Ii]ncreased by%s+([%d,]+)")
		or message:match("[Gg]ained%s+([%d,]+)")
		or message:match("%+%s*([%d,]+)%s*[Rr]ep"))
	local faction = (plainMessage(message) or "")
		:gsub("^[Yy]our reputation with%s+", "")
		:gsub("^[Rr]eputation with%s+", "")
		:gsub("%s+[Hh]as increased.*$", "")
		:gsub("%s+increased.*$", "")
		:gsub("%s+by%s+[%d,]+.*$", "")
		:gsub("%s+gained.*$", "")
	if faction == "" then faction = "Reputation" end
	return faction, amount
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

local QUALITY_NAMES = {
	[0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
	[5] = "Legendary", [6] = "Artifact", [7] = "Heirloom", [8] = "WoW Token", [9] = "Quest",
}
local QUALITY_BY_HEX = {
	["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
	["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}
local QUALITY_COLORS = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
	[3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
	[6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 }, [8] = { 0, 0.8, 1 },
}

local function itemQualityFromLink(message)
	local hex = message:match("|c(%x%x%x%x%x%x%x%x)|Hitem:")
	return hex and QUALITY_BY_HEX[hex:sub(3):lower()] or nil
end

local function qualityName(quality)
	quality = ns.toNumber(quality)
	if quality == nil then return nil end
	quality = math.floor(quality + 0.5)
	local name = _G["ITEM_QUALITY" .. quality .. "_DESC"] or QUALITY_NAMES[quality]
	return type(name) == "string" and name or nil
end

local function qualityColor(quality)
	quality = ns.toNumber(quality)
	if quality == nil then return nil end
	quality = math.floor(quality + 0.5)
	if type(_G.GetItemQualityColor) == "function" then
		local ok, r, g, b = pcall(_G.GetItemQualityColor, quality)
		r, g, b = ok and ns.toNumber(r), ok and ns.toNumber(g), ok and ns.toNumber(b)
		if r and g and b then return { r, g, b } end
	end
	return QUALITY_COLORS[quality]
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
	local vendor, quality
	if type(getter) == "function" then
		local ok, sellPrice, itemQuality = pcall(function()
			local info = ns.pack(getter(itemString))
			local qualityValue = not ns.isSecret(info[3]) and tonumber(info[3]) or nil
			return info[11], qualityValue
		end)
		sellPrice = ok and sellPrice or nil
		sellPrice = ok and ns.toNumber(sellPrice) or nil
		quality = ok and ns.toNumber(itemQuality) or nil
		if sellPrice and sellPrice > 0 then vendor = sellPrice * quantity end
	end
	local chosen = market and market * quantity or vendor
	return chosen, market and "AH" or vendor and "Vendor" or nil, quality, vendor
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

local function normalizedText(value)
	if type(value) ~= "string" then return "" end
	return value:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function canMergeEntries(existing, incoming)
	if existing.kind ~= incoming.kind or existing.isPreview or incoming.isPreview then return false end
	if existing.kind == "item" then
		return existing.itemID ~= nil and existing.itemID == incoming.itemID
			and existing.itemString ~= nil and existing.itemString == incoming.itemString
	end
	if existing.amountValue == nil or incoming.amountValue == nil then return false end
	if existing.kind == "money" then return true end
	if existing.kind == "currency" then
		if existing.currencyID and incoming.currencyID then return existing.currencyID == incoming.currencyID end
		return normalizedText(existing.text) == normalizedText(incoming.text)
	end
	if existing.kind == "reputation" then
		return normalizedText(existing.text) == normalizedText(incoming.text)
	end
	return false
end

local function updateAggregatedAmount(entry)
	if entry.kind == "money" then
		entry.amountText = "+" .. formatMoney(entry.amountValue)
	elseif entry.kind == "currency" then
		entry.amountText = "+" .. tostring(entry.amountValue)
	elseif entry.kind == "reputation" then
		entry.amountText = "+" .. tostring(entry.amountValue) .. " rep"
	end
end

local function setTextStyle(region, size, style)
	if not region then return end
	style = style or loot.Style()
	local font = FONT_FACES[style.fontFace]
	if font == false or font == nil then font = (ns.ui and ns.ui.FONT) or "Fonts\\FRIZQT__.TTF" end
	local outline = FONT_OUTLINES[style.fontOutline] or ""
	if type(region.SetFont) == "function" then region:SetFont(font, size, outline) end
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
	frame:SetFrameStrata(saved.frameStrata)
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
	row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.amount:SetJustifyH("RIGHT")
	row.amount:SetWordWrap(false)
	row.quality = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.quality:SetJustifyH("LEFT")
	row.quality:SetWordWrap(false)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetJustifyH("RIGHT")
	row.value:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		if not self.itemLink or not _G.GameTooltip then return end
		local link = self.itemLink
		if ns.isSecret(link) then return end
		local itemString = link:match("|H(item:[^|]+)|h") or link:match("^(item:[^|]+)$")
		if itemString then
			_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			_G.GameTooltip:SetHyperlink(itemString)
			if self.marketValue and type(_G.GameTooltip.AddLine) == "function" then
				pcall(_G.GameTooltip.AddLine, _G.GameTooltip, "Auction estimate: " .. formatMoney(self.marketValue), 0.55, 0.82, 1)
			end
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
	local count = previewBackup and #entries or math.min(#entries, style.maxRows)
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
		local isItem = entry.kind == "item"
		local labelY = (isItem and 7 or 0) + style.labelYOffset
		row.name:SetPoint("LEFT", row.icon, "RIGHT", 10 + style.labelXOffset, labelY)
		row.name:SetPoint("RIGHT", row, "RIGHT", -104 + style.labelXOffset, labelY)
		row.name:SetText(entry.text)
		setTextStyle(row.name, style.fontSize, style)
		local itemQuality = isItem and (qualityName(entry.quality) or "Unknown") or nil
		row.quality:ClearAllPoints()
		row.quality:SetPoint("LEFT", row.icon, "RIGHT", 10 + style.labelXOffset, (isItem and -8 or 0) + style.labelYOffset)
		local valueWidth = math.min(124, math.max(84, row:GetWidth() * 0.30))
		local qualityWidth = math.min(120, math.max(48, row:GetWidth() - style.iconSize - valueWidth - 36))
		row.quality:SetWidth(qualityWidth)
		row.quality:SetText(itemQuality and itemQuality:upper() or "")
		setTextStyle(row.quality, math.max(9, style.fontSize - 4), style)
		local qualityTint = style.qualityColors and (entry.color or qualityColor(entry.quality)) or nil
		if qualityTint then row.quality:SetTextColor(qualityTint[1], qualityTint[2], qualityTint[3], 1)
		else row.quality:SetTextColor(0.82, 0.84, 0.88, 1) end
		row.amount:ClearAllPoints()
		row.amount:SetPoint("RIGHT", row, "RIGHT", -2 + style.amountXOffset, (isItem and 7 or 0) + style.amountYOffset)
		row.amount:SetWidth(98)
		row.amount:SetText(entry.amountText or (isItem and entry.quantity and ("+" .. entry.quantity) or ""))
		setTextStyle(row.amount, math.max(10, style.fontSize - 1), style)
		local amountColor = entry.amountColor or (style.qualityColors and (entry.color or qualityColor(entry.quality))) or { 1, 0.82, 0.28 }
		row.amount:SetTextColor(amountColor[1], amountColor[2], amountColor[3], 1)
		row.value:ClearAllPoints()
		row.value:SetPoint("RIGHT", row, "RIGHT", -2, -8)
		row.value:SetWidth(valueWidth)
		local displayValue = isItem and (entry.vendorValue or entry.value) or nil
		local displayLabel = entry.vendorValue ~= nil and "Vendor:" or entry.valueLabel and (entry.valueLabel .. ":") or nil
		row.value:SetText(displayValue and ((displayLabel and (displayLabel .. " ") or "") .. formatMoney(displayValue)) or "")
		setTextStyle(row.value, math.max(10, style.fontSize - 2), style)
		row.value:SetTextColor(1, 0.82, 0.28, 1)
		local nameTint = style.qualityColors and (entry.color or qualityColor(entry.quality)) or nil
		if nameTint then
			row.name:SetTextColor(nameTint[1], nameTint[2], nameTint[3], 1)
		elseif ns.ui and ns.ui.colors and ns.ui.colors.text then
			row.name:SetTextColor(ns.ui.colors.text[1], ns.ui.colors.text[2], ns.ui.colors.text[3], 1)
		else
			row.name:SetTextColor(1, 1, 1, 1)
		end
		local glowColor = (style.qualityColors and (entry.color or qualityColor(entry.quality))) or skin.border
		row.glow:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], style.borderGlow and (entry.color and style.qualityColors and 0.72 or 0.30) or 0)
		row.itemLink = entry.link
		row.marketValue = entry.vendorValue ~= nil and entry.valueLabel == "AH" and entry.value or nil
		row:SetAlpha((style.animate and math.min(1, age / 0.12) or 1) * fade)
		row:Show()
	end
	for i = count + 1, #frame.rows do
		frame.rows[i]:Hide()
		frame.rows[i].itemLink = nil
		frame.rows[i].marketValue = nil
	end
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
	if frame.SetFrameStrata then frame:SetFrameStrata(style.frameStrata) end
	if #entries > 0 then
		local visible = previewBackup and #entries or math.min(#entries, style.maxRows)
		for i = 1, visible do
			local row = frame.rows[i]
			if row and row:IsShown() then
				setTextStyle(row.name, style.fontSize, style)
				setTextStyle(row.amount, math.max(10, style.fontSize - 1), style)
				setTextStyle(row.value, math.max(10, style.fontSize - 2), style)
				setTextStyle(row.quality, math.max(9, style.fontSize - 4), style)
				local entry = entries[i]
				local itemTint = style.qualityColors and (entry.color or qualityColor(entry.quality)) or nil
				if itemTint then row.name:SetTextColor(itemTint[1], itemTint[2], itemTint[3], 1)
				elseif ns.ui and ns.ui.colors and ns.ui.colors.text then
					local c = ns.ui.colors.text; row.name:SetTextColor(c[1], c[2], c[3], 1)
				end
				if itemTint then row.quality:SetTextColor(itemTint[1], itemTint[2], itemTint[3], 1)
				else row.quality:SetTextColor(0.82, 0.84, 0.88, 1) end
				row.bg:SetVertexColor(skin.border[1], skin.border[2], skin.border[3], skin.rowAlpha or 0)
				local glowColor = itemTint or skin.border
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
	if previewBackup then
		entries = previewBackup
		previewBackup = nil
	end
	for index = #entries, 1, -1 do
		local expires = entries[index].expires
		if expires and current >= expires then table.remove(entries, index) end
	end
	local entry = { kind = kind, text = text, icon = icon, link = link, color = color, created = current }
	for key, value in pairs(details or {}) do entry[key] = value end
	if style.duration > 0 then entry.expires = current + style.duration end
	for index, existing in ipairs(entries) do
		if canMergeEntries(existing, entry) then
			table.remove(entries, index)
			if kind == "item" then
				local previousQuantity = existing.quantity or 0
				existing.quantity = previousQuantity + (entry.quantity or 0)
				existing.created, existing.expires = current, entry.expires
				existing.icon, existing.text, existing.link = entry.icon, entry.text, entry.link
				existing.color = entry.color or existing.color
				local value, valueLabel, quality, vendorValue = itemValues(existing.itemID, existing.itemString, existing.quantity)
				if value ~= nil then
					existing.value, existing.valueLabel = value, valueLabel
				elseif existing.value ~= nil and entry.value ~= nil then
					existing.value = existing.value + entry.value
				elseif existing.value ~= nil and previousQuantity > 0 then
					existing.value = existing.value / previousQuantity * existing.quantity
				end
				if vendorValue ~= nil then
					existing.vendorValue = vendorValue
				elseif existing.vendorValue ~= nil and entry.vendorValue ~= nil then
					existing.vendorValue = existing.vendorValue + entry.vendorValue
				elseif existing.vendorValue ~= nil and previousQuantity > 0 then
					existing.vendorValue = existing.vendorValue / previousQuantity * existing.quantity
				end
				if quality ~= nil then existing.quality = quality end
			else
				existing.amountValue = existing.amountValue + entry.amountValue
				existing.created, existing.expires = current, entry.expires
				existing.icon = entry.icon or existing.icon
				existing.amountColor = entry.amountColor or existing.amountColor
				updateAggregatedAmount(existing)
			end
			table.insert(entries, 1, existing)
			while #entries > style.maxRows do table.remove(entries) end
			render()
			return true
		end
	end
	if #entries >= 12 then table.remove(entries, #entries) end
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
	local quantity = linkQuantity(message, "item") or 1
	quantity = math.max(1, math.floor(quantity))
	local r, g, b
	if loot.Style().qualityColors then r, g, b = itemColor(message) end
	local color = r and { r, g, b } or nil
	local value, valueLabel, quality, vendorValue = itemValues(itemID, itemString, quantity)
	quality = quality or itemQualityFromLink(message)
	local added = addEntry("item", name, itemIcon(itemID, message), itemString, color, {
		itemID = itemID, itemString = itemString, quantity = quantity,
		value = value, valueLabel = valueLabel, vendorValue = vendorValue, quality = quality,
	})
	if not value and _G.C_Item and type(_G.C_Item.RequestLoadItemDataByID) == "function" then
		pcall(_G.C_Item.RequestLoadItemDataByID, itemID)
	end
	return added
end

local function addMessage(kind, message)
	local plain = plainMessage(message)
	if not plain then return false end
	local icon = message:match("|T([^:|]+)")
	if not icon and kind == "currency" then icon = currencyIcon(message) end
	if not icon and kind == "money" then icon = moneyIcon(message) end
	if not icon then
		icon = kind == "reputation" and "Interface\\Icons\\Achievement_Reputation_01"
			or "Interface\\Icons\\INV_Misc_Coin_02"
	end
	local text, amountText, amountColor
	local amountValue
	if kind == "money" then
		text = "Money"
		amountValue = moneyAmount(message)
		amountText = amountValue and ("+" .. formatMoney(amountValue)) or plain
		amountColor = { 1, 0.82, 0.28 }
	elseif kind == "currency" then
		text = currencyName(message)
		amountValue = linkQuantity(message, "currency")
		amountText = amountValue and ("+" .. amountValue) or nil
		amountColor = { 0.55, 0.82, 1 }
	else
		text, amountValue = reputationGain(message)
		amountText = amountValue and ("+" .. amountValue .. " rep") or nil
		amountColor = { 0.42, 0.94, 0.58 }
	end
	return addEntry(kind, text, icon, nil, nil, {
		amountText = amountText, amountColor = amountColor, amountValue = amountValue,
		currencyID = kind == "currency" and tonumber(message:match("|Hcurrency:(%d+)")) or nil,
	})
end

local function refreshItemInfo(itemID)
	local function refreshList(list)
		for _, entry in ipairs(list or {}) do
			if entry.kind == "item" and entry.itemID == itemID then
				entry.icon = itemIcon(itemID, entry.link or "")
				local value, valueLabel, quality, vendorValue = itemValues(itemID, entry.itemString, entry.quantity or 1)
				entry.value, entry.valueLabel = value, valueLabel
				if vendorValue ~= nil then entry.vendorValue = vendorValue end
				if quality ~= nil then entry.quality = quality end
			end
		end
	end
	refreshList(entries)
	if previewBackup then refreshList(previewBackup) end
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
	local offsetLimits = {
		labelXOffset = { -120, 120 }, labelYOffset = { -60, 60 },
		amountXOffset = { -120, 120 }, amountYOffset = { -60, 60 },
	}
	for key, range in pairs(offsetLimits) do
		if style[key] ~= nil then
			local value = ns.toNumber(style[key])
			if value == nil or value < range[1] or value > range[2] then
				return false, "Loot text position is outside its allowed range; nothing changed."
			end
			values[key] = math.floor(value + 0.5)
		end
	end
	if style.fontFace ~= nil and not ns.isSecret(style.fontFace) then
		if type(style.fontFace) ~= "string" or FONT_FACES[style.fontFace] == nil then
			return false, "Unknown loot font; nothing changed."
		end
		values.fontFace = style.fontFace
	end
	if style.fontOutline ~= nil and not ns.isSecret(style.fontOutline) then
		if type(style.fontOutline) ~= "string" or FONT_OUTLINES[style.fontOutline] == nil then
			return false, "Unknown loot font outline; nothing changed."
		end
		values.fontOutline = style.fontOutline
	end
	if style.frameStrata ~= nil and not ns.isSecret(style.frameStrata) then
		if type(style.frameStrata) ~= "string" or not validStrata[style.frameStrata] then
			return false, "Unknown loot window strata; nothing changed."
		end
		values.frameStrata = style.frameStrata
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
		if not previewBackup then
			while #entries > style.maxRows do table.remove(entries) end
		end
		render()
	else
		loot.ApplyStyle()
	end
end

function loot.Preview()
	if previewBackup then
		entries = previewBackup
		previewBackup = nil
		local current = now()
		for index = #entries, 1, -1 do
			if entries[index].expires and current >= entries[index].expires then table.remove(entries, index) end
		end
		render()
		return false
	end
	previewBackup = entries
	local current = now()
	local examples = {
		{ 0, "Battered Knife", "Interface\\Icons\\INV_Misc_QuestionMark", 1, 125 },
		{ 1, "Linen Cloth", "Interface\\Icons\\INV_Fabric_Linen_01", 4, 360 },
		{ 2, "Wild Herb", "Interface\\Icons\\INV_Misc_Herb_01", 2, 840 },
		{ 3, "Sapphire", "Interface\\Icons\\INV_Misc_Gem_Sapphire_02", 1, 24500 },
		{ 4, "Arcane Robes", "Interface\\Icons\\INV_Chest_Cloth_17", 1, 125000 },
		{ 5, "Dragonfang Blade", "Interface\\Icons\\INV_Sword_39", 1, 2500000 },
	}
	entries = {}
	for _, example in ipairs(examples) do
		local quality = example[1]
		entries[#entries + 1] = {
			kind = "item", text = example[2], icon = example[3], quantity = example[4],
			value = example[5], valueLabel = "Vendor", quality = quality,
			color = QUALITY_COLORS[quality], created = current, isPreview = true,
		}
	end
	entries[#entries + 1] = {
		kind = "currency", text = "Honor", icon = "Interface\\Icons\\Achievement_Arena_2p_5",
		amountText = "+12", amountColor = { 0.55, 0.82, 1 }, created = current, isPreview = true,
	}
	entries[#entries + 1] = {
		kind = "money", text = "Money", icon = "Interface\\Icons\\INV_Misc_Coin_03",
		amountText = "+1g 25s 30c", amountColor = { 1, 0.82, 0.28 }, created = current, isPreview = true,
	}
	entries[#entries + 1] = {
		kind = "reputation", text = "Example Faction", icon = "Interface\\Icons\\Achievement_Reputation_01",
		amountText = "+25 rep", amountColor = { 0.42, 0.94, 0.58 }, created = current, isPreview = true,
	}
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
