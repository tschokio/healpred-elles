-- DoHelper-owned item-link affordances for Blizzard chat frames.
-- All settings are opt-in and independent of EllesmereUI.
local _, ns = ...
local links = {}
ns.chatItemLinks = links

local hookedFrames = setmetatable({}, { __mode = "k" })
local active, pool = {}, {}
local tooltipSerial = 0
local eventFrame

local function isItemLink(link)
	if type(link) ~= "string" then return false end
	if _G.issecretvalue and _G.issecretvalue(link) then return false end
	return link:match("^item:") ~= nil
end

local function itemKey(link)
	if not isItemLink(link) then return nil end
	-- Treat bonus/unique suffix variants of the same base item as one item.
	return link:match("^item:(%-?%d+)") or link
end

local function setting(key, fallback)
	local value = ns.db and ns.db[key]
	if ns.isSecret and ns.isSecret(value) then return fallback end
	value = tonumber(value)
	return value or fallback
end

local function lookup(key)
	for i, record in ipairs(active) do
		if record.key == key then return record, i end
	end
end

local function releaseFrame(frame)
	if not frame then return end
	frame._doHelperChatRecord = nil
	if frame.EnableMouse then frame:EnableMouse(false) end
	if frame.Hide then frame:Hide() end
	if frame.ClearLines then frame:ClearLines() end
	pool[#pool + 1] = frame
end

local function removeAt(index)
	local record = table.remove(active, index)
	if record then releaseFrame(record.frame) end
	return record
end

local function makeRoom()
	local limit = links.TooltipLimit()
	while #active >= limit do
		-- Keep the newest previews; making room always dismisses the oldest.
		removeAt(1)
	end
end

function links.TooltipLimit()
	local limit = math.floor(setting("chatItemTooltipLimit", 3) + 0.5)
	return math.max(1, math.min(10, limit))
end

function links.EnforceLimit()
	local limit = links.TooltipLimit()
	while #active > limit do removeAt(1) end
end

local function acquireFrame()
	local frame = table.remove(pool)
	if frame then return frame end
	if type(_G.CreateFrame) ~= "function" or not _G.UIParent then return nil end
	tooltipSerial = tooltipSerial + 1
	local ok, created = pcall(_G.CreateFrame, "GameTooltip", "DoHelperChatItemTooltip" .. tooltipSerial, _G.UIParent, "GameTooltipTemplate")
	if not ok or not created then return nil end
	if created.SetClampedToScreen then created:SetClampedToScreen(true) end
	if created.EnableMouse then created:EnableMouse(false) end
	return created
end

local function ratio(value, fallback)
	if ns.isSecret and ns.isSecret(value) then return fallback end
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
	return math.max(0, math.min(1, number))
end

local function savedPosition()
	local parent = _G.UIParent
	local width = parent and parent.GetWidth and ns.toNumber(parent:GetWidth())
	local height = parent and parent.GetHeight and ns.toNumber(parent:GetHeight())
	if not width or not height or width <= 0 or height <= 0 then return 24, 24 end
	local saved = ns.db and ns.db.chatItemPreviewPosition
	if ns.isSecret and ns.isSecret(saved) then saved = nil end
	local x = ratio(type(saved) == "table" and saved.x, 0.5)
	local y = ratio(type(saved) == "table" and saved.y, 0.5)
	return x * width, y * height
end

local function rememberPosition(frame)
	local parent = _G.UIParent
	if not parent or not frame.GetLeft or not frame.GetBottom or not frame.ClearAllPoints or not frame.SetPoint
		or not parent.GetWidth or not parent.GetHeight then return end
	local left, bottom = ns.toNumber(frame:GetLeft()), ns.toNumber(frame:GetBottom())
	local width, height = ns.toNumber(parent:GetWidth()), ns.toNumber(parent:GetHeight())
	if not left or not bottom or not width or not height or width <= 0 or height <= 0 then return end
	local x, y = ratio(left / width, 0.5), ratio(bottom / height, 0.5)
	ns.db.chatItemPreviewPosition = { x = x, y = y }
	local record = frame._doHelperChatRecord
	if record then record.x, record.y = x * width, y * height end
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x * width, y * height)
end

local function configureDragging(frame)
	if frame._doHelperDragConfigured then return end
	frame._doHelperDragConfigured = true
	if type(frame.SetMovable) ~= "function" or type(frame.RegisterForDrag) ~= "function"
		or type(frame.SetScript) ~= "function" or type(frame.StartMoving) ~= "function"
		or type(frame.StopMovingOrSizing) ~= "function" then return end
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if type(_G.IsShiftKeyDown) == "function" then
			local ok, down = pcall(_G.IsShiftKeyDown)
			if not ok or not down then return end
		end
		self._doHelperDragging = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		if not self._doHelperDragging then return end
		self._doHelperDragging = nil
		self:StopMovingOrSizing()
		rememberPosition(self)
	end)
end

local function getOrCreate(frame, link)
	local key = itemKey(link)
	if not key then return nil end
	local record = lookup(key)
	if record then return record end
	makeRoom()
	local tooltip = acquireFrame()
	if not tooltip or type(tooltip.SetOwner) ~= "function" or type(tooltip.SetHyperlink) ~= "function" then
		if tooltip then releaseFrame(tooltip) end
		return nil
	end
	local x, y = savedPosition()
	record = { key = key, link = link, frame = tooltip, owner = frame, x = x, y = y }
	active[#active + 1] = record
	return record
end

local function showRecord(record, frame, link, clicked)
	if not record then return false end
	local tooltip = record.frame
	local _, index = lookup(record.key)
	record.owner, record.link = frame, link
	local pinned = clicked or record.clicked
	tooltip._doHelperChatRecord = record
	if pinned then configureDragging(tooltip) end
	if tooltip.EnableMouse then tooltip:EnableMouse(pinned and true or false) end
	if index == 1 and not pinned then
		tooltip:SetOwner(frame or _G.UIParent, "ANCHOR_CURSOR")
	else
		tooltip:SetOwner(_G.UIParent, "ANCHOR_NONE")
		if tooltip.ClearAllPoints and tooltip.SetPoint then
			tooltip:ClearAllPoints()
			local previous = index and index > 1 and active[index - 1]
			if previous and previous.frame then
				tooltip:SetPoint("TOPLEFT", previous.frame, "BOTTOMLEFT", 0, -8)
			else
				tooltip:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", record.x, record.y)
			end
		end
	end
	if tooltip.ClearLines then tooltip:ClearLines() end
	local ok = pcall(tooltip.SetHyperlink, tooltip, link)
	if not ok then
		local _, badIndex = lookup(record.key)
		if badIndex then removeAt(badIndex) end
		return false
	end
	-- On modern clients TooltipDataProcessor normally decorates synchronously;
	-- this explicit pass also covers legacy clients and our custom preview frames.
	if ns.Camping and ns.Camping.Decorate then pcall(ns.Camping.Decorate, tooltip) end
	if pinned and tooltip.AddLine then
		pcall(tooltip.AddLine, tooltip, "Shift-drag to move; position is saved.", 0.7, 0.82, 1)
	end
	if tooltip.Show then tooltip:Show() end
	if _G.GameTooltip and _G.GameTooltip ~= tooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
	return true
end

function links.OnHyperlinkEnter(frame, link)
	if not isItemLink(link) or not ns.db or not ns.db.chatItemTooltipOnHover then return end
	local record = getOrCreate(frame, link)
	if not record then return end
	record.hovered = true
	showRecord(record, frame, link)
end

function links.OnHyperlinkLeave(frame, link)
	local key = itemKey(link)
	local record = key and lookup(key)
	if not record or record.owner ~= frame or not record.hovered then
		-- EllesmereUI and some WoW client builds fire OnHyperlinkLeave with only
		-- the chat frame (unlike OnHyperlinkEnter, which includes the link).
		-- Resolve the active hover by frame when the client omits the link.
		record = nil
		for i = #active, 1, -1 do
			local candidate = active[i]
			if candidate.owner == frame and candidate.hovered then
				record = candidate
				break
			end
		end
	end
	if not record then return end
	record.hovered = false
	if record.clicked then return end
	local _, index = lookup(record.key)
	if index then removeAt(index) end
end

function links.OnHyperlinkClick(frame, link)
	if not ns.db or not ns.db.chatItemPreviewToggle then return end
	local key = itemKey(link)
	if not key then return end
	local record = lookup(key)
	if record and record.clicked then
		local _, index = lookup(key)
		removeAt(index)
		if _G.ItemRefTooltip and _G.ItemRefTooltip.Hide then _G.ItemRefTooltip:Hide() end
		return
	end
	if not record then record = getOrCreate(frame, link) end
	-- Pin the clicked preview at the saved position instead of letting an
	-- ANCHOR_CURSOR tooltip follow the pointer around the screen.
	record.x, record.y = savedPosition()
	if not showRecord(record, frame, link, true) then return end
	record.clicked = true
	if _G.ItemRefTooltip and _G.ItemRefTooltip.Hide then _G.ItemRefTooltip:Hide() end
end

function links.HookFrame(frame)
	if not frame or hookedFrames[frame] or type(frame.HookScript) ~= "function" then return false end
	hookedFrames[frame] = true
	frame:HookScript("OnHyperlinkEnter", links.OnHyperlinkEnter)
	frame:HookScript("OnHyperlinkLeave", links.OnHyperlinkLeave)
	frame:HookScript("OnHyperlinkClick", links.OnHyperlinkClick)
	return true
end

function links.HookFrames()
	local count = tonumber(_G.NUM_CHAT_WINDOWS) or 10
	for i = 1, count do links.HookFrame(_G["ChatFrame" .. i]) end
end

function links.OpenTooltipCount()
	return #active
end

local function initialize()
	links.HookFrames()
	-- Additional chat windows are created lazily by the stock chat UI.
	if type(_G.hooksecurefunc) == "function" then
		pcall(_G.hooksecurefunc, "FCF_OpenNewWindow", function() links.HookFrames() end)
	end
end

if type(_G.CreateFrame) == "function" then
	eventFrame = CreateFrame("Frame")
	links.eventFrame = eventFrame
	eventFrame:RegisterEvent("PLAYER_LOGIN")
	eventFrame:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_LOGIN")
		initialize()
	end)
end
