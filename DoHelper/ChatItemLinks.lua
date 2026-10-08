-- DoHelper-owned item-link affordances for Blizzard chat frames.
-- These are independent of EllesmereUI and are opt-in in the DoHelper settings.
local _, ns = ...
local links = {}
ns.chatItemLinks = links

local lastClickedLink
local hoverTooltipOwner
local hookedFrames = setmetatable({}, { __mode = "k" })

local function isItemLink(link)
	if type(link) ~= "string" then return false end
	if _G.issecretvalue and _G.issecretvalue(link) then return false end
	return link:match("^item:") ~= nil
end

function links.OnHyperlinkEnter(frame, link)
	if not isItemLink(link) or not ns.db or not ns.db.chatItemTooltipOnHover then return end
	local tooltip = _G.GameTooltip
	if not tooltip or type(tooltip.SetOwner) ~= "function" or type(tooltip.SetHyperlink) ~= "function" then return end
	tooltip:SetOwner(frame, "ANCHOR_CURSOR")
	tooltip:SetHyperlink(link)
	if tooltip.Show then tooltip:Show() end
	hoverTooltipOwner = frame
end

function links.OnHyperlinkLeave(frame)
	if hoverTooltipOwner ~= frame then return end
	hoverTooltipOwner = nil
	local tooltip = _G.GameTooltip
	if tooltip and tooltip.Hide then tooltip:Hide() end
end

function links.OnHyperlinkClick(_, link)
	if not ns.db or not ns.db.chatItemPreviewToggle then return end
	if not isItemLink(link) then
		lastClickedLink = nil
		return
	end
	local preview = _G.ItemRefTooltip
	if lastClickedLink == link and preview and preview.IsShown and preview:IsShown() then
		preview:Hide()
		lastClickedLink = nil
	else
		lastClickedLink = link
	end
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

local function initialize()
	links.HookFrames()
	-- Additional chat windows are created lazily by the stock chat UI.
	if type(_G.hooksecurefunc) == "function" then
		pcall(_G.hooksecurefunc, "FCF_OpenNewWindow", function() links.HookFrames() end)
	end
end

if type(_G.CreateFrame) == "function" then
	local eventFrame = CreateFrame("Frame")
	links.eventFrame = eventFrame
	eventFrame:RegisterEvent("PLAYER_LOGIN")
	eventFrame:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_LOGIN")
		initialize()
	end)
end
