local function click(widget, ...)
	widget:GetScript("OnClick")(widget, ...)
end
local function toggle(widget, value)
	widget:SetChecked(value)
	click(widget)
end

-- True when `f` is `root` or a descendant of it.
local function within(root, f)
	local p = f
	while p do
		if p == root then return true end
		p = p:GetParent()
	end
	return false
end

T.register("options: window is lazy reused escape registered and refreshes saved settings", function()
	local e = Mocks.NewEnv()
	assert_nil(e.ns.optionsWindow)
	e.ns.HandleCommand("options")
	local f = e.ns.optionsWindow
	assert_true(f:IsShown())
	assert_eq(f.controls.alpha:GetText(), "0.6")
	assert_true(f.controls.enabled:GetChecked())
	assert_false(f.controls.approximate:GetChecked())
	click(f.controls.close)
	assert_false(f:IsShown())
	e.ns.HandleCommand("alpha 0.25")
	e.ns.HandleCommand("menu")
	assert_eq(e.ns.optionsWindow, f)
	assert_eq(f.controls.alpha:GetText(), "0.25")
	local found = 0
	for _, name in ipairs(UISpecialFrames) do if name == f:GetName() then found = found + 1 end end
	assert_eq(found, 1)
	assert_nil(f:GetScript("OnUpdate"))
end)

T.register("options: checkboxes use existing runtime and prediction commands", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	toggle(f.controls.approximate, true)
	assert_true(e.ns.db.approximatePrediction)
	toggle(f.controls.exclude, true)
	assert_true(e.ns.db.assumeApiExcludesHoTs)
	toggle(f.controls.enabled, false)
	assert_false(e.ns.db.enabled)
	assert_nil(e.ns.overlay.state.ticker)
	toggle(f.controls.enabled, true)
	assert_true(e.ns.db.enabled)
	toggle(f.controls.debug, true)
	assert_true(e.ns.db.debug)
	assert_true(e.ns.debugEnabled)
end)

T.register("options: appearance apply validates all fields atomically and preserves native style", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	f.controls.alpha:SetText("0.3")
	f.controls.red:SetText("bad")
	click(f.controls.apply)
	assert_eq(e.ns.db.alpha, 0.6)
	f.controls.red:SetText("0.2")
	click(f.controls.apply)
	assert_eq(e.ns.db.alpha, 0.3)
	assert_true(e.ns.db.shareNativeStyle)
	toggle(f.controls.native, false)
	f.controls.red:SetText("0.2")
	f.controls.green:SetText("0.4")
	f.controls.blue:SetText("0.8")
	click(f.controls.apply)
	assert_false(e.ns.db.shareNativeStyle)
	assert_eq(e.ns.db.overlayColor[1], 0.2)
	assert_eq(e.ns.db.overlayColor[3], 0.8)
	f.controls.alpha:SetText("-1")
	click(f.controls.apply)
	assert_eq(e.ns.db.alpha, 0.3)
	toggle(f.controls.native, true)
	assert_true(e.ns.db.shareNativeStyle)
	f.controls.alpha:SetFocus()
	click(f.controls.close)
	assert_false(f.controls.alpha:HasFocus())
end)

T.register("options: preview is explicit session only diagnostics opens copy window", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	assert_nil(e.ns.session.fake)
	click(f.controls.preview)
	assert_eq(e.ns.session.fake.value, 1000)
	assert_nil(e.ns.db.showFake)
	click(f.controls.stop)
	assert_nil(e.ns.session.fake)
	click(f.controls.diagnostics)
	assert_true(e.ns.debugWindow:IsShown())
end)

T.register("options: minimap visibility position clicks and drag have no idle updater", function()
	local e = Mocks.NewEnv()
	-- Simulate a minimap becoming available at login; init is also called at startup.
	Minimap = CreateFrame("Frame", nil, UIParent)
	Minimap:SetSize(140, 140)
	GetCursorPosition = function() return 200, 100 end
	e.ns.InitOptions()
	local b = e.ns.minimapButton
	assert_true(b:IsShown())
	assert_nil(b:GetScript("OnUpdate"))
	click(b, "LeftButton")
	assert_true(e.ns.optionsWindow:IsShown())
	click(b, "RightButton")
	assert_true(e.ns.debugWindow:IsShown())
	b:GetScript("OnDragStart")(b)
	assert_true(type(b:GetScript("OnUpdate")) == "function")
	b:GetScript("OnUpdate")()
	assert_near(e.ns.db.minimapAngle, 0, 1e-8)
	b:GetScript("OnDragStop")(b)
	assert_nil(b:GetScript("OnUpdate"))
	e.ns.HandleCommand("minimap off")
	assert_false(b:IsShown())
	assert_true(e.ns.db.minimapHidden)
	e.ns.HandleCommand("enable off")
	e.ns.HandleCommand("minimap on")
	assert_true(b:IsShown(), "settings access must survive disabling prediction")
	assert_eq(e.ns.InitOptions(), nil)
	assert_eq(e.ns.minimapButton, b)
	Minimap, GetCursorPosition = nil, nil
end)

T.register("options: modern Blizzard AddOns category registers once without building settings window", function()
	local e = Mocks.NewEnv()
	local registrations = 0
	Settings = {
		RegisterCanvasLayoutCategory = function(panel, name)
			assert_eq(name, "DoHelper")
			return { panel = panel }
		end,
		RegisterAddOnCategory = function() registrations = registrations + 1 end,
	}
	e.ns.InitOptions()
	e.ns.InitOptions()
	assert_eq(registrations, 1)
	assert_nil(e.ns.optionsWindow)
	assert_true(e.ns.optionsCategoryPanel ~= nil)
	Settings = nil
end)

T.register("options: missing frame API reports gracefully and preview persists only until disabled", function()
	local e = Mocks.NewEnv()
	local create = CreateFrame
	CreateFrame = nil
	assert_nil(e.ns.OpenOptions())
	CreateFrame = create
	local f = e.ns.OpenOptions()
	click(f.controls.preview)
	click(f.controls.close)
	assert_eq(e.ns.session.fake.value, 1000, "closing a menu must not silently change predictions")
	e.ns.OpenOptions()
	toggle(f.controls.enabled, false)
	assert_nil(e.ns.session.fake)
end)

T.register("options: descriptive labels render above the page background", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	local page = f.settingsPage
	local checked = 0
	for _, l in ipairs(page._fontStrings) do
		if l:GetText() ~= "" then
			checked = checked + 1
			assert_true(Mocks.IsRegionVisible(l), "hidden settings label: " .. l:GetText())
		end
	end
	assert_true(checked >= 8, "expected the settings descriptions to exist")
	-- The decoration is a BACKGROUND draw-layer texture on the page itself, not
	-- an opaque child frame sitting at page frame level + 1.
	assert_not_nil(Mocks.FindTexture(page, "BACKGROUND"), "page background must be a texture")
	assert_true(Mocks.LayerRank("BACKGROUND") < Mocks.LayerRank("OVERLAY"),
		"backgrounds must draw below OVERLAY text")
	for _, child in ipairs(Mocks.OpaqueChildFrames(page)) do
		assert_eq(child._type, "EditBox", "only real input fields have child backdrops; decoration stays on the page")
	end
	-- Controls are child frames one level above the page and stay clickable.
	assert_not_nil(f.controls.enabled)
	local ctrlLevel = f.controls.enabled:GetFrameLevel()
	assert_true(ctrlLevel > page:GetFrameLevel(), "controls must sit above the page background")
end)

T.register("options: window heading and preview labels are never occluded", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	local heading = Mocks.FindFontString(f, "EllesmereUI helper")
	assert_not_nil(heading, "window heading must exist")
	assert_true(Mocks.IsRegionVisible(heading), "window heading must stay visible")
	local preview = f.preview
	assert_not_nil(preview, "preview panel must exist")
	local previewLabel = Mocks.FindFontString(preview, "ACTION BUTTON PREVIEW")
	assert_not_nil(previewLabel)
	assert_true(Mocks.IsRegionVisible(previewLabel), "preview labels must stay visible over their own panel")
end)

T.register("queue appearance: field labels render above the decorative background", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenQueueAppearance()
	assert_not_nil(Mocks.FindTexture(f, "BACKGROUND"), "appearance background must be a texture")
	assert_true(Mocks.LayerRank("BACKGROUND") < Mocks.LayerRank("OVERLAY"))
	local checked = 0
	for _, l in ipairs(f._fontStrings) do
		if l:GetText() ~= "" then
			checked = checked + 1
			assert_true(Mocks.IsRegionVisible(l), "hidden appearance label: " .. l:GetText())
		end
	end
	assert_true(checked >= 6, "expected the appearance descriptions to exist")
	assert_true(f.controls.thickness:GetFrameLevel() > f:GetFrameLevel(),
		"edit boxes must sit above the appearance background")
end)

T.register("layering mock: opaque higher-level frame occludes a parent label", function()
	Mocks.NewEnv()
	local parent = CreateFrame("Frame", nil, UIParent)
	parent:SetSize(300, 200)
	parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	parent:SetFrameStrata("DIALOG")
	local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
	l:SetWidth(100)
	l:SetText("hello")
	assert_true(Mocks.IsRegionVisible(l))
	local cover = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	cover:SetSize(200, 100)
	cover:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	cover:SetBackdrop({ bgFile = "x" })
	assert_eq(cover:GetFrameLevel(), parent:GetFrameLevel() + 1, "child frames inherit parent level + 1")
	assert_eq(cover:GetFrameStrata(), "DIALOG", "child frames inherit parent strata")
	assert_false(Mocks.IsRegionVisible(l), "opaque child panel must hide the parent's label")
	-- A BACKGROUND texture on the parent must not hide its own OVERLAY text.
	cover:Hide()
	local t = parent:CreateTexture(nil, "BACKGROUND")
	t:SetSize(200, 100)
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	assert_true(Mocks.IsRegionVisible(l), "same-frame background textures render below labels")
	parent:Hide()
	assert_false(Mocks.IsRegionVisible(l), "hidden pages are not visible")
end)

local function openBoth(e)
	local main = e.ns.OpenOptions()
	local app = e.ns.OpenQueueAppearance()
	assert_true(main:IsShown() and app:IsShown(), "both windows must be shown")
	return main, app
end

T.register("appearance: editor outranks the main window and all its deepest descendants", function()
	local e = Mocks.NewEnv()
	local main, app = openBoth(e)
	local appRank = Mocks.StrataRank(app:GetFrameStrata())
	local mainRank = Mocks.StrataRank(main:GetFrameStrata())
	assert_true(appRank > mainRank, "editor strata must outrank the main settings window")
	assert_true(appRank < Mocks.StrataRank("TOOLTIP"), "editor must stay below tooltips")
	-- The old bug: both roots were DIALOG, so the main window's deeper
	-- descendants (its +10 preview border) sorted above the editor's own frames.
	assert_true(main.preview.border:GetFrameLevel() > app:GetFrameLevel(),
		"main window has a frame deeper than the editor root")
	local appFrames, mainFrames = 0, 0
	for _, f in ipairs(Mocks.frames) do
		if within(app, f) then
			appFrames = appFrames + 1
			assert_eq(f:GetFrameStrata(), app:GetFrameStrata(), "editor descendant lost the editor strata")
		elseif within(main, f) then
			mainFrames = mainFrames + 1
			assert_true(Mocks.StrataRank(f:GetFrameStrata()) < appRank,
				"a main-window frame reaches the editor's strata")
		end
	end
	assert_true(appFrames >= 6, "expected the editor hierarchy to exist")
	assert_true(mainFrames >= 6, "expected the main hierarchy to exist")
	assert_not_nil(app.preview.border, "editor preview border must exist")
	assert_eq(app.preview.border:GetFrameStrata(), app:GetFrameStrata(), "preview border must inherit the editor strata")
end)

T.register("appearance: labels stay visible while the main window is shown", function()
	local e = Mocks.NewEnv()
	openBoth(e)
	local app = e.ns.queueAppearanceWindow
	local checked = 0
	for _, l in ipairs(app._fontStrings) do
		if l:GetText() ~= "" then
			checked = checked + 1
			assert_true(Mocks.IsRegionVisible(l), "editor label occluded: " .. l:GetText())
		end
	end
	assert_true(checked >= 6, "expected the editor labels to exist")
	for _, l in ipairs(app.preview._fontStrings) do
		if l:GetText() ~= "" then
			assert_true(Mocks.IsRegionVisible(l), "editor preview label occluded: " .. l:GetText())
		end
	end
	assert_not_nil(Mocks.FindFontString(app, "Next-swing appearance"), "editor heading must exist")
end)

T.register("appearance: hide and reopen keeps stacking, Esc registry and focus cleanup", function()
	local e = Mocks.NewEnv()
	local main, app = openBoth(e)
	local box = app.controls.thickness
	box:SetFocus()
	assert_true(box:HasFocus())
	click(app.controls.close)
	assert_false(app:IsShown())
	assert_false(box:HasFocus(), "closing the editor must clear focus")
	local again = e.ns.OpenQueueAppearance()
	assert_eq(again, app, "the editor is reused lazily")
	assert_true(app:IsShown())
	assert_true(Mocks.StrataRank(app:GetFrameStrata()) > Mocks.StrataRank(main:GetFrameStrata()),
		"reopened editor must still outrank the main window")
	local found = 0
	for _, name in ipairs(UISpecialFrames) do if name == app:GetName() then found = found + 1 end end
	assert_eq(found, 1, "editor registered for Escape exactly once")
end)

T.register("appearance: re-showing the main window never interleaves into the editor", function()
	local e = Mocks.NewEnv()
	local main, app = openBoth(e)
	main:Hide()
	main:Show()
	assert_true(main:IsShown() and app:IsShown())
	assert_true(Mocks.StrataRank(app:GetFrameStrata()) > Mocks.StrataRank(main:GetFrameStrata()))
	local heading = Mocks.FindFontString(app, "Next-swing appearance")
	assert_not_nil(heading)
	assert_true(Mocks.IsRegionVisible(heading), "editor heading must survive re-showing the main window")
end)

T.register("appearance: editor created before main settings still stays on top", function()
	local e = Mocks.NewEnv()
	local app = e.ns.OpenQueueAppearance()
	assert_nil(e.ns.optionsWindow)
	local main = e.ns.OpenOptions()
	assert_true(main:IsShown() and app:IsShown())
	assert_true(Mocks.StrataRank(app:GetFrameStrata()) > Mocks.StrataRank(main.preview.border:GetFrameStrata()))
	for _, l in ipairs(app._fontStrings) do
		if l:GetText() ~= "" then assert_true(Mocks.IsRegionVisible(l), "later-created main obscures editor label") end
	end
end)

T.register("appearance: controls stay actionable while stacked over the main window", function()
	local e = Mocks.NewEnv()
	e.ns.OpenOptions()
	local app = e.ns.OpenQueueAppearance()
	local appRank = Mocks.StrataRank(app:GetFrameStrata())
	for _, key in ipairs({ "thickness", "padding", "alpha", "apply", "defaults", "close" }) do
		local c = app.controls[key]
		assert_not_nil(c, "missing editor control: " .. key)
		assert_eq(Mocks.StrataRank(c:GetFrameStrata()), appRank, "control must inherit the editor strata")
	end
	app.controls.thickness:SetText("7")
	app.controls.padding:SetText("5")
	assert_true(app.preview.Update(7, 5, 0.5, 0.1, 0.2, 0.3), "valid preview update is accepted")
	click(app.preview.button)
	assert_false(app.preview.border:IsShown(), "preview toggle must stay clickable")
	click(app.controls.apply)
	assert_eq(e.ns.db.queuedSwingThickness, 7)
	assert_eq(e.ns.db.queuedSwingPadding, 5)
end)
T.register("options: spell editor saves action IDs and calibrated owned HoTs separately", function()
	local e = Mocks.NewEnv()
	local root = e.ns.OpenOptions()
	root.controls.manageTab:GetScript("OnClick")()
	local f = e.ns.spellEditorWindow
	assert_eq(f:GetFrameStrata(), "FULLSCREEN_DIALOG")
	local c = f.controls
	c.id:SetText("987654"); c.name:SetText("Custom Action")
	c.add:GetScript("OnClick")()
	assert_eq(e.ns.db.extraQueueSpells[987654], "Custom Action")
	assert_nil(e.ns.spells.Meta(987654))
	c.remove:GetScript("OnClick")(); assert_nil(e.ns.queuedSwing.spells[987654])
	c.reset:GetScript("OnClick")(); assert_nil(e.ns.db.removedQueueSpells[987654])
	c.hot:GetScript("OnClick")()
	c.id:SetText("987655"); c.name:SetText("Custom Healing Aura")
	c.interval:SetText("invalid"); c.amount:SetText("25")
	c.add:GetScript("OnClick")(); assert_nil(e.ns.spells.Meta(987655))
	c.interval:SetText("2"); c.add:GetScript("OnClick")()
	assert_eq(e.ns.spells.Meta(987655).name, "Custom Healing Aura")
	assert_eq(e.ns.db.intervalOverrides[987655], 2)
	assert_eq(e.ns.spells.AmountOverride(987655, 1), 25)
	assert_nil(e.ns.queuedSwing.spells[987655])
	c.remove:GetScript("OnClick")(); assert_nil(e.ns.spells.Meta(987655))
	c.reset:GetScript("OnClick")()
	assert_nil(e.ns.db.extraSpells[987655]); assert_nil(e.ns.db.intervalOverrides[987655]); assert_nil(e.ns.db.amountOverrides[987655])
	assert_nil(e.ns.session.fake)
end)
