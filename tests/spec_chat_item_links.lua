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
	e.ns.db.chatItemHoverLingerMs = 1000
	e.ns.db.chatItemTooltipLimit = 3
	Mocks.SetNow(10)
	links.OnHyperlinkEnter(frame, "item:123")
	assert_eq(links.OpenTooltipCount(), 1)
	assert_eq(created[2].owner, frame)
	assert_eq(created[2].anchor, "ANCHOR_CURSOR")
	assert_eq(created[2].link, "item:123")
	assert_true(created[2].shown)
	assert_false(nativeTooltip.shown, "the one-off Blizzard hover tooltip is replaced by the managed tooltip")
	links.OnHyperlinkLeave(frame, "item:123")
	links.UpdateTimers(10.999)
	assert_eq(links.OpenTooltipCount(), 1, "linger timer keeps it open until its deadline")
	links.UpdateTimers(11)
	assert_eq(links.OpenTooltipCount(), 0, "linger timer closes at its deadline")
end)

T.register("chat item links: click previews time out, toggle, deduplicate by item and obey the limit", function()
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
	e.ns.db.chatItemPreviewToggle = true
	e.ns.db.chatItemClickDurationMs = 1000
	e.ns.db.chatItemTooltipLimit = 2
	Mocks.SetNow(20)
	local chat = {}
	links.OnHyperlinkClick(chat, "item:123:1")
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
	links.UpdateTimers(20.999)
	assert_eq(links.OpenTooltipCount(), 2)
	links.UpdateTimers(21)
	assert_eq(links.OpenTooltipCount(), 0, "click preview duration closes previews automatically")
	assert_false(links.eventFrame:GetScript("OnUpdate") ~= nil, "timer driver stops when there are no pending timers")
	e.ns.db.chatItemClickDurationMs = 0
	links.OnHyperlinkClick(chat, "item:1000")
	links.UpdateTimers(100)
	assert_eq(links.OpenTooltipCount(), 1, "zero disables clicked-preview auto-close")
	links.OnHyperlinkClick(chat, "item:1000")
	assert_eq(links.OpenTooltipCount(), 0, "repeat click still closes an untimed preview")
	links.OnHyperlinkClick(chat, "item:1001")
	links.OnHyperlinkClick(chat, "item:1002")
	e.ns.db.chatItemTooltipLimit = 1
	links.EnforceLimit()
	assert_eq(links.OpenTooltipCount(), 1, "lowering the limit immediately dismisses oldest excess previews")
end)

T.register("chat item links: options are available in DoHelper without EllesmereUI hooks", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("chat")
	assert_eq(f.selectedTab, "chat")
	assert_not_nil(f.controls.chatItemTooltipOnHover)
	assert_not_nil(f.controls.chatItemPreviewToggle)
	assert_not_nil(f.controls.chatItemHoverLingerMs)
	assert_not_nil(f.controls.chatItemClickDurationMs)
	assert_not_nil(f.controls.chatItemTooltipLimit)
	assert_true(f.chatPage:IsShown())
	f.controls.chatItemTooltipOnHover:SetChecked(true)
	f.controls.chatItemTooltipOnHover:GetScript("OnClick")(f.controls.chatItemTooltipOnHover)
	assert_true(e.ns.db.chatItemTooltipOnHover)
	f.controls.chatItemHoverLingerMs:SetValue(2500)
	assert_eq(e.ns.db.chatItemHoverLingerMs, 2500)
	f.controls.chatItemClickDurationMs:SetValue(5000)
	assert_eq(e.ns.db.chatItemClickDurationMs, 5000)
	f.controls.chatItemTooltipLimit:SetValue(5)
	assert_eq(e.ns.db.chatItemTooltipLimit, 5)
end)
