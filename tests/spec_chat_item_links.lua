T.register("chat item links: settings are opt-in and hover tooltips follow the setting", function()
	local e = Mocks.NewEnv()
	local links = e.ns.chatItemLinks
	assert_false(e.ns.db.chatItemTooltipOnHover)
	assert_false(e.ns.db.chatItemPreviewToggle)
	local calls = {}
	GameTooltip = {
		SetOwner = function(_, frame, anchor) calls.owner, calls.anchor = frame, anchor end,
		SetHyperlink = function(_, link) calls.link = link end,
		Show = function() calls.shown = true end,
		Hide = function() calls.hidden = true end,
	}
	local frame = { HookScript = function(self, name, fn) self[name] = fn end }
	assert_true(links.HookFrame(frame))
	assert_false(links.HookFrame(frame), "same chat frame is hooked once")
	links.OnHyperlinkEnter(frame, "item:123")
	assert_nil(calls.link, "hover is disabled by default")
	e.ns.db.chatItemTooltipOnHover = true
	links.OnHyperlinkEnter(frame, "item:123")
	assert_eq(calls.owner, frame)
	assert_eq(calls.anchor, "ANCHOR_CURSOR")
	assert_eq(calls.link, "item:123")
	assert_true(calls.shown)
	links.OnHyperlinkLeave(frame)
	assert_true(calls.hidden)
end)

T.register("chat item links: repeat item click toggles the native preview closed", function()
	local e = Mocks.NewEnv()
	local links = e.ns.chatItemLinks
	local preview = { shown = false, IsShown = function(self) return self.shown end,
		Hide = function(self) self.shown = false; self.hideCount = (self.hideCount or 0) + 1 end }
	ItemRefTooltip = preview
	e.ns.db.chatItemPreviewToggle = true
	links.OnHyperlinkClick({}, "item:123") -- First click opens via Blizzard's normal handler.
	preview.shown = true
	links.OnHyperlinkClick({}, "item:123")
	assert_false(preview.shown)
	assert_eq(preview.hideCount, 1)
	preview.shown = true
	links.OnHyperlinkClick({}, "item:456")
	assert_true(preview.shown, "a different item click does not close the preview")
	links.OnHyperlinkClick({}, "spell:1")
	assert_eq(links.HookFrame(nil), false)
end)

T.register("chat item links: options are available in DoHelper without EllesmereUI hooks", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("chat")
	assert_eq(f.selectedTab, "chat")
	assert_not_nil(f.controls.chatItemTooltipOnHover)
	assert_not_nil(f.controls.chatItemPreviewToggle)
	assert_true(f.chatPage:IsShown())
	f.controls.chatItemTooltipOnHover:SetChecked(true)
	f.controls.chatItemTooltipOnHover:GetScript("OnClick")(f.controls.chatItemTooltipOnHover)
	assert_true(e.ns.db.chatItemTooltipOnHover)
end)
