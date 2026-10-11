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

local function now()
	return type(_G.GetTime) == "function" and _G.GetTime() or 0
end

local function lookup(key)
	for i, record in ipairs(active) do
		if record.key == key then return record, i end
	end
end

local function updateDriver()
	if not eventFrame then return end
	local needsUpdate = false
	for _, record in ipairs(active) do
		if record.leaveAt or record.clickExpiresAt then needsUpdate = true; break end
	end
	if needsUpdate then
		eventFrame:SetScript("OnUpdate", function() links.UpdateTimers() end)
	else
		eventFrame:SetScript("OnUpdate", nil)
	end
end

local function releaseFrame(frame)
	if not frame then return end
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
	updateDriver()
end

local function acquireFrame()
	local frame = table.remove(pool)
	if frame then return frame end
	if type(_G.CreateFrame) ~= "function" or not _G.UIParent then return nil end
	tooltipSerial = tooltipSerial + 1
	local ok, created = pcall(_G.CreateFrame, "GameTooltip", "DoHelperChatItemTooltip" .. tooltipSerial, _G.UIParent, "GameTooltipTemplate")
	if not ok or not created then return nil end
	if created.SetClampedToScreen then created:SetClampedToScreen(true) end
	return created
end

local function cursorPoint()
	local x, y = 24, 24
	if type(_G.GetCursorPosition) == "function" then
		local ok, cx, cy = pcall(_G.GetCursorPosition)
		if ok and type(cx) == "number" and type(cy) == "number" then
			local scale = _G.UIParent and _G.UIParent.GetEffectiveScale and _G.UIParent:GetEffectiveScale() or 1
			if type(scale) ~= "number" or scale <= 0 then scale = 1 end
			x, y = cx / scale, cy / scale
		end
	end
	return x, y
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
	local x, y = cursorPoint()
	record = { key = key, link = link, frame = tooltip, owner = frame, openedAt = now(), x = x, y = y }
	active[#active + 1] = record
	return record
end

local function showRecord(record, frame, link)
	if not record then return false end
	local tooltip = record.frame
	local _, index = lookup(record.key)
	record.owner, record.link = frame, link
	if index == 1 then
		tooltip:SetOwner(frame or _G.UIParent, "ANCHOR_CURSOR")
	else
		tooltip:SetOwner(_G.UIParent, "ANCHOR_NONE")
		if tooltip.ClearAllPoints and tooltip.SetPoint then
			tooltip:ClearAllPoints()
			local previous = active[(index or #active) - 1]
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
		updateDriver()
		return false
	end
	if tooltip.Show then tooltip:Show() end
	if _G.GameTooltip and _G.GameTooltip ~= tooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
	return true
end

function links.UpdateTimers(at)
	at = tonumber(at) or now()
	for i = #active, 1, -1 do
		local record = active[i]
		local clickedExpired = record.clickExpiresAt and at >= record.clickExpiresAt
		local lingerExpired = record.leaveAt and at >= record.leaveAt
		if clickedExpired then record.clickExpiresAt = nil end
		if (clickedExpired or lingerExpired) and not record.hovered then removeAt(i) end
	end
	updateDriver()
end

function links.OnHyperlinkEnter(frame, link)
	if not isItemLink(link) or not ns.db or not ns.db.chatItemTooltipOnHover then return end
	local record = getOrCreate(frame, link)
	if not record then return end
	record.hovered = true
	record.leaveAt = nil
	if showRecord(record, frame, link) then updateDriver() end
end

function links.OnHyperlinkLeave(frame, link)
	local key = itemKey(link)
	local record = key and lookup(key)
	if not record or record.owner ~= frame then return end
	record.hovered = false
	local linger = math.max(0, math.min(5000, setting("chatItemHoverLingerMs", 1000)))
	record.leaveAt = now() + linger / 1000
	links.UpdateTimers()
end

function links.OnHyperlinkClick(frame, link)
	if not ns.db or not ns.db.chatItemPreviewToggle then return end
	local key = itemKey(link)
	if not key then return end
	local record = lookup(key)
	if record and record.clicked then
		local _, index = lookup(key)
		removeAt(index)
		updateDriver()
		if _G.ItemRefTooltip and _G.ItemRefTooltip.Hide then _G.ItemRefTooltip:Hide() end
		return
	end
	if not record then record = getOrCreate(frame, link) end
	if not showRecord(record, frame, link) then return end
	record.clicked = true
	record.openedAt = now()
	local timeout = math.max(0, math.min(5000, setting("chatItemClickDurationMs", 0)))
	-- Zero means keep clicked previews open until explicitly toggled/evicted.
	record.clickExpiresAt = timeout > 0 and (record.openedAt + timeout / 1000) or nil
	if _G.ItemRefTooltip and _G.ItemRefTooltip.Hide then _G.ItemRefTooltip:Hide() end
	updateDriver()
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
