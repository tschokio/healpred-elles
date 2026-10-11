T.register("chat item links: settings are opt-in and hover tooltips follow the setting", function()
	local e = Mocks.NewEnv()
	local links = e.ns.chatItemLinks
	assert_false(e.ns.db.chatItemTooltipOnHover)
	assert_false(e.ns.db.chatItemPreviewToggle)
	local created = {}
	local function tooltip()
		local tip = { shown = false }
		function tip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
		function tip:SetHyperlink(link) self.link = link end
		function tip:Show() self.shown = true end
		function tip:Hide() self.shown = false; self.hideCount = (self.hideCount or 0) + 1 end
		function tip:ClearLines() self.link = nil end
		function tip:ClearAllPoints() self.point = nil end
		function tip:SetPoint(...) self.point = { ... } end
		function tip:SetClampedToScreen(value) self.clamped = value end
		created[#created + 1] = tip
		return tip
	end
	local nativeTooltip = tooltip()
	GameTooltip = nativeTooltip
	local originalCreateFrame = CreateFrame
	CreateFrame = function(kind, name, parent, template)
		if kind == "GameTooltip" then return tooltip() end
		return originalCreateFrame(kind, name, parent, template)
	end
	local frame = { HookScript = function(self, name, fn) self[name] = fn end }
	assert_true(links.HookFrame(frame))
	assert_false(links.HookFrame(frame), "same chat frame is hooked once")
	links.OnHyperlinkEnter(frame, "item:123")
	assert_eq(links.OpenTooltipCount(), 0, "hover is disabled by default")
	e.ns.db.chatItemTooltipOnHover = true
	e.ns.db.chatItemTooltipLimit = 3
	links.OnHyperlinkEnter(frame, "item:123")
	assert_eq(links.OpenTooltipCount(), 1)
	assert_eq(created[2].owner, frame)
	assert_eq(created[2].anchor, "ANCHOR_CURSOR")
	assert_eq(created[2].link, "item:123")
	assert_true(created[2].shown)
	assert_false(nativeTooltip.shown, "the one-off Blizzard hover tooltip is replaced by the managed tooltip")
	links.OnHyperlinkLeave(frame) -- EllesmereUI's leave hook does not pass the link.
	assert_eq(links.OpenTooltipCount(), 0, "hover tooltip closes immediately on leave")
	assert_nil(links.eventFrame:GetScript("OnUpdate"), "chat previews do not need a timer driver")
end)

T.register("chat item links: clicked previews stay pinned until toggled and obey the limit", function()
	local e = Mocks.NewEnv()
	local links = e.ns.chatItemLinks
	local created = {}
	local originalCreateFrame = CreateFrame
	CreateFrame = function(kind, name, parent, template)
		if kind == "GameTooltip" then
			local tip = { shown = false }
			function tip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
			function tip:SetHyperlink(link) self.link = link end
			function tip:Show() self.shown = true end
			function tip:Hide() self.shown = false end
			function tip:ClearLines() self.link = nil end
			function tip:ClearAllPoints() self.point = nil end
			function tip:SetPoint(...) self.point = { ... } end
			function tip:SetClampedToScreen() end
			created[#created + 1] = tip
			return tip
		end
		return originalCreateFrame(kind, name, parent, template)
	end
	local native = { Hide = function(self) self.hidden = true end }
	ItemRefTooltip = native
	e.ns.db.chatItemTooltipOnHover = true
	e.ns.db.chatItemPreviewToggle = true
	e.ns.db.chatItemTooltipLimit = 2
	local chat = {}
	links.OnHyperlinkEnter(chat, "item:123:1")
	links.OnHyperlinkClick(chat, "item:123:1")
	assert_eq(created[1].owner, UIParent, "clicked previews use their own tooltip frame")
	assert_eq(created[1].anchor, "ANCHOR_NONE", "clicked previews must not track the cursor")
	assert_eq(created[1].point[1], "BOTTOMLEFT")
	assert_eq(created[1].point[2], UIParent)
	assert_eq(created[1].point[4], 960, "first clicked preview opens at the saved screen-relative x position")
	assert_eq(created[1].point[5], 540, "first clicked preview opens at the saved screen-relative y position")
	links.OnHyperlinkLeave(chat) -- A pending hover leave must not close a clicked preview.
	assert_eq(links.OpenTooltipCount(), 1)
	links.OnHyperlinkClick(chat, "item:456")
	assert_eq(links.OpenTooltipCount(), 2)
	assert_true(native.hidden, "managed previews replace the single Blizzard item tooltip")
	links.OnHyperlinkClick(chat, "item:789")
	assert_eq(links.OpenTooltipCount(), 2, "new items respect the configured simultaneous-tooltip cap")
	assert_eq(created[2].link, "item:456", "oldest preview is evicted to make room")
	assert_eq(created[1].link, "item:789")
	links.OnHyperlinkClick(chat, "item:456:bonus")
	assert_eq(links.OpenTooltipCount(), 1, "item variants share one preview and a repeat click closes it")
	links.OnHyperlinkClick(chat, "item:999")
	assert_eq(links.OpenTooltipCount(), 2)
	assert_nil(links.eventFrame:GetScript("OnUpdate"), "clicked previews have no auto-close timer")
	links.OnHyperlinkClick(chat, "item:999")
	assert_eq(links.OpenTooltipCount(), 1, "repeat click closes a clicked preview")
	links.OnHyperlinkClick(chat, "item:1001")
	links.OnHyperlinkClick(chat, "item:1002")
	e.ns.db.chatItemTooltipLimit = 1
	links.EnforceLimit()
	assert_eq(links.OpenTooltipCount(), 1, "lowering the limit immediately dismisses oldest excess previews")
end)

T.register("chat item links: clicked previews can be shift-dragged and remember their position", function()
	local e = Mocks.NewEnv()
	local links = e.ns.chatItemLinks
	local created = {}
	local originalCreateFrame = CreateFrame
	CreateFrame = function(kind, name, parent, template)
		if kind == "GameTooltip" then
			local tip = { shown = false, scripts = {} }
			function tip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
			function tip:SetHyperlink(link) self.link = link end
			function tip:AddLine(line) self.extraLine = line end
			function tip:Show() self.shown = true end
			function tip:Hide() self.shown = false end
			function tip:ClearLines() self.link = nil end
			function tip:ClearAllPoints() self.point = nil end
			function tip:SetPoint(...)
				self.point = { ... }
				if self.point[2] == UIParent then self.left, self.bottom = self.point[4], self.point[5] end
			end
			function tip:SetClampedToScreen(value) self.clamped = value end
			function tip:SetMovable(value) self.movable = value end
			function tip:RegisterForDrag(button) self.dragButton = button end
			function tip:EnableMouse(value) self.mouseEnabled = value end
			function tip:SetScript(name, fn) self.scripts[name] = fn end
			function tip:GetScript(name) return self.scripts[name] end
			function tip:StartMoving() self.moving = true end
			function tip:StopMovingOrSizing() self.moving = false end
			function tip:GetLeft() return self.left end
			function tip:GetBottom() return self.bottom end
			created[#created + 1] = tip
			return tip
		end
		return originalCreateFrame(kind, name, parent, template)
	end
	e.ns.db.chatItemPreviewToggle = true
	local oldShiftCheck = IsShiftKeyDown
	IsShiftKeyDown = function() return false end
	local chat = {}
	links.OnHyperlinkClick(chat, "item:321")
	local tip = created[1]
	assert_true(tip.movable)
	assert_eq(tip.mouseEnabled, true)
	assert_eq(tip.dragButton, "LeftButton")
	assert_eq(tip.extraLine, "Shift-drag to move; position is saved.")
	tip:GetScript("OnDragStart")(tip)
	assert_false(tip.moving, "ordinary drags do not move the tooltip")
	IsShiftKeyDown = function() return true end
	tip:GetScript("OnDragStart")(tip)
	assert_true(tip.moving)
	tip.left, tip.bottom = 450, 270
	tip:GetScript("OnDragStop")(tip)
	assert_false(tip.moving)
	assert_eq(e.ns.db.chatItemPreviewPosition.x, 450 / 1920)
	assert_eq(e.ns.db.chatItemPreviewPosition.y, 270 / 1080)
	assert_eq(tip.point[4], 450)
	assert_eq(tip.point[5], 270)
	links.OnHyperlinkClick(chat, "item:321")
	assert_false(tip.mouseEnabled, "releasing the pooled tooltip disables mouse capture")
	UIParent:SetSize(1280, 720)
	links.OnHyperlinkClick(chat, "item:654")
	assert_eq(created[1], tip, "the tooltip frame is reused")
	assert_eq(tip.point[4], 300, "future previews use the saved relative x position after a resolution change")
	assert_eq(tip.point[5], 180, "future previews use the saved relative y position after a resolution change")
	assert_eq(links.OpenTooltipCount(), 1)
	Mocks.now = 10
	tip:GetScript("OnMouseUp")(tip, "LeftButton")
	assert_eq(links.OpenTooltipCount(), 1, "one click on an opened preview keeps it open")
	Mocks.now = 10.2
	tip:GetScript("OnMouseUp")(tip, "LeftButton")
	assert_eq(links.OpenTooltipCount(), 0, "double-clicking the opened tooltip closes it")
	assert_false(tip.shown)
	IsShiftKeyDown = oldShiftCheck
end)

T.register("chat item links: options are available in DoHelper without EllesmereUI hooks", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("chat")
	assert_eq(f.selectedTab, "chat")
	assert_not_nil(f.controls.chatItemTooltipOnHover)
	assert_not_nil(f.controls.chatItemPreviewToggle)
	assert_nil(f.controls.chatItemHoverLingerMs)
	assert_nil(f.controls.chatItemClickDurationMs)
	assert_not_nil(f.controls.chatItemTooltipLimit)
	assert_true(f.chatPage:IsShown())
	f.controls.chatItemTooltipOnHover:SetChecked(true)
	f.controls.chatItemTooltipOnHover:GetScript("OnClick")(f.controls.chatItemTooltipOnHover)
	assert_true(e.ns.db.chatItemTooltipOnHover)
	f.controls.chatItemTooltipLimit:SetValue(5)
	assert_eq(e.ns.db.chatItemTooltipLimit, 5)
end)
