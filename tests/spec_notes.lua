-- tests/spec_notes.lua
-- Notes with several named topics plus an optional floating window. The window
-- collapses to a compact "Do ^" pill, can be moved, closed and styled, and is
-- read-only during combat. The options tab mirrors the same topics.
local function click(widget, ...)
	widget:GetScript("OnClick")(widget, ...)
end

local function contains(text, fragment)
	return type(text) == "string" and text:find(fragment, 1, true) ~= nil
end

T.register("notes: tab switches cleanly and edits persist and mirror between editors", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	assert_false(f.notesPage:IsShown())
	click(f.controls.notesTab)
	assert_eq(f.selectedTab, "notes")
	assert_true(f.notesPage:IsShown())
	assert_false(f.settingsPage:IsShown())
	assert_false(f.spellsPage:IsShown())
	assert_true(contains(f.controls.notesTab:GetText(), "Notes"))
	f.notesEditor:SetText("flask timer\npull at 3")
	assert_eq(e.ns.db.notes.sites[1].text, "flask timer\npull at 3")
	local win = e.ns.notes.Open()
	assert_true(win:IsShown())
	assert_eq(win.edit:GetText(), "flask timer\npull at 3")
	win.edit:SetText("updated")
	assert_eq(e.ns.db.notes.sites[1].text, "updated")
	assert_eq(f.notesEditor:GetText(), "updated")
	assert_nil(win:GetScript("OnUpdate"), "notes window has no idle updater")
	-- Selecting another tab hides notes but keeps the persisted text.
	click(f.controls.spellsTab)
	assert_false(f.notesPage:IsShown())
	assert_eq(e.ns.db.notes.sites[1].text, "updated")
end)

T.register("notes: topics keep separate text and selection survives switching", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.notesTab)
	assert_eq(#e.ns.notes.Sites(), 1, "a fresh install starts with one topic")
	assert_eq(e.ns.notes.ActiveSite().title, "General")
	f.notesEditor:SetText("first")
	click(f.controls.notesNew)
	assert_eq(#e.ns.notes.Sites(), 2)
	assert_eq(e.ns.notes.ActiveSite().title, "Note 2")
	f.notesEditor:SetText("second")
	assert_eq(e.ns.notes.SiteText(e.ns.notes.ActiveId()), "second")
	assert_eq(f.controls.notesTitle:GetText(), "Note 2")
	-- Switch back to the first topic; its text is intact and shown in the editor.
	click(f.controls.notesPrev)
	assert_eq(e.ns.notes.SiteText(e.ns.notes.ActiveId()), "first")
	assert_eq(f.notesEditor:GetText(), "first")
	-- Rename the active topic.
	f.controls.notesTitle:SetText("Raiding")
	f.controls.notesTitle:GetScript("OnEnterPressed")(f.controls.notesTitle)
	assert_eq(e.ns.notes.ActiveSite().title, "Raiding")
	assert_eq(f.controls.notesTitle:GetText(), "Raiding")
	-- Delete it; one topic must always remain.
	assert_eq(#e.ns.notes.Sites(), 2)
	click(f.controls.notesDelete)
	assert_eq(#e.ns.notes.Sites(), 1)
	click(f.controls.notesDelete)
	assert_eq(#e.ns.notes.Sites(), 1, "the last topic is never removed")
	assert_eq(f.notesEditor:GetText(), "second")
end)

T.register("notes: floating window adds, renames, cycles and deletes topics", function()
	local e = Mocks.NewEnv()
	local f = e.ns.notes.Open()
	f.edit:SetText("alpha")
	assert_eq(e.ns.notes.SiteText(e.ns.notes.ActiveId()), "alpha")
	click(f.siteAdd)
	assert_eq(#e.ns.notes.Sites(), 2)
	assert_eq(f.edit:GetText(), "", "a new topic starts empty")
	f.edit:SetText("beta")
	click(f.sitePrev)
	assert_eq(f.edit:GetText(), "alpha")
	assert_eq(f.siteTitle:GetText(), e.ns.notes.ActiveSite().title)
	f.siteTitle:SetText("Gear")
	f.siteTitle:GetScript("OnEnterPressed")(f.siteTitle)
	assert_eq(e.ns.notes.ActiveSite().title, "Gear")
	click(f.siteNext)
	assert_eq(f.edit:GetText(), "beta")
	assert_eq(f.siteTitle:GetText(), "Note 2")
	click(f.siteDel)
	assert_eq(#e.ns.notes.Sites(), 1)
end)

T.register("notes: legacy single text migrates into a first topic without loss", function()
	local e = Mocks.NewEnv()
	-- Simulate the pre-topics SavedVariables schema.
	e.ns.db.notes.sites = nil
	e.ns.db.notes.text = "old note body"
	local sites = e.ns.notes.Sites()
	assert_eq(#sites, 1)
	assert_eq(sites[1].title, "General")
	assert_eq(sites[1].text, "old note body")
	assert_nil(e.ns.db.notes.text, "the legacy field is migrated away, not kept in parallel")
	-- A second call never duplicates or clears the migrated topic.
	assert_eq(#e.ns.notes.Sites(), 1)
	assert_eq(e.ns.notes.SiteText(e.ns.notes.ActiveId()), "old note body")
end)

T.register("notes: editing locks in combat and unlocks afterwards", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.notesTab)
	local win = e.ns.notes.Open()
	local ev = e.ns.notes.eventFrame
	assert_not_nil(ev, "notes owns a small event frame")
	win.edit:SetFocus()
	e.ns.notes.RefreshEditable()
	assert_true(win.edit:IsEnabled())
	Mocks.inCombat = true
	e.ns.notes.eventFrame:GetScript("OnEvent")(ev, "PLAYER_REGEN_DISABLED")
	assert_false(e.ns.notes.IsEditable())
	assert_false(win.edit:IsEnabled(), "floating editor is read-only in combat")
	assert_false(f.notesEditor:IsEnabled(), "tab editor is read-only in combat")
	assert_false(win.edit:HasFocus(), "locking clears focus so keybinds are not swallowed")
	assert_false(win.siteTitle:IsEnabled(), "topic title is read-only in combat")
	assert_false(win.siteAdd:IsEnabled(), "adding a topic is blocked in combat")
	assert_false(win.siteDel:IsEnabled(), "deleting a topic is blocked in combat")
	assert_false(f.controls.notesTitle:IsEnabled(), "tab topic title is read-only in combat")
	assert_false(f.controls.notesNew:IsEnabled(), "tab add is blocked in combat")
	assert_true(win.sitePrev:IsEnabled(), "cycling topics is safe in combat")
	assert_true(contains(win.hint:GetText(), "read-only"))
	Mocks.inCombat = false
	e.ns.notes.eventFrame:GetScript("OnEvent")(ev, "PLAYER_REGEN_ENABLED")
	assert_true(e.ns.notes.IsEditable())
	assert_true(win.edit:IsEnabled())
	assert_true(win.siteAdd:IsEnabled())
	assert_true(f.controls.notesNew:IsEnabled())
	assert_eq(win.hint:GetText(), "")
end)

T.register("notes: collapsed pill is compact, shows Do and arrow, and reopens", function()
	local e = Mocks.NewEnv()
	local f = e.ns.notes.Open()
	assert_true(f:IsShown())
	assert_true(e.ns.db.notes.shown)
	assert_eq(f.title:GetText(), "Do")
	assert_eq(f.collapse:GetText(), "v")
	-- Collapsed: just "Do" and the arrow, much smaller than the editor window.
	click(f.collapse)
	assert_true(e.ns.db.notes.collapsed)
	assert_false(f.edit:IsShown())
	assert_eq(f:GetHeight(), e.ns.notes.COLLAPSED_HEIGHT)
	assert_eq(f:GetWidth(), e.ns.notes.COLLAPSED_WIDTH)
	assert_eq(f.collapse:GetText(), "^")
	assert_false(f.close:IsShown(), "the collapsed pill keeps only the expand arrow")
	assert_false(f.siteTitle:IsShown())
	-- The arrow opens it again.
	click(f.collapse)
	assert_false(e.ns.db.notes.collapsed)
	assert_true(f.edit:IsShown())
	assert_true(f.close:IsShown())
	assert_eq(f.collapse:GetText(), "v")
	f:GetScript("OnDragStart")(f)
	assert_true(f._moving)
	f:GetScript("OnDragStop")(f)
	assert_false(f._moving)
	assert_eq(e.ns.db.notes.x, 0)
	assert_eq(e.ns.db.notes.y, 0)
	click(f.close)
	assert_false(f:IsShown())
	assert_false(e.ns.db.notes.shown)
	e.ns.db.notes.shown = true
	e.ns.notes.HandleEvent("PLAYER_LOGIN")
	assert_true(f:IsShown(), "a shown note is restored after a reload")
	e.ns.HandleCommand("notes hide")
	assert_false(f:IsShown())
	e.ns.HandleCommand("notes expand")
	e.ns.HandleCommand("notes")
	assert_true(f:IsShown())
	assert_eq(e.ns.notes.window, f, "the window is reused lazily")
end)

T.register("notes: style applies live, is validated atomically and resets to defaults", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.notesTab)
	local c = f.controls
	c.notesWidth:SetText("400"); c.notesHeight:SetText("300"); c.notesFont:SetText("18")
	c.notesTextR:SetText("1"); c.notesTextG:SetText("0.5"); c.notesTextB:SetText("0")
	c.notesBgR:SetText("0"); c.notesBgG:SetText("0.1"); c.notesBgB:SetText("0.2"); c.notesBgA:SetText("0.5")
	click(c.notesApply)
	assert_eq(e.ns.db.notes.width, 400)
	assert_eq(e.ns.db.notes.height, 300)
	assert_eq(e.ns.db.notes.fontSize, 18)
	assert_eq(e.ns.db.notes.textColor[2], 0.5)
	assert_eq(e.ns.db.notes.background[4], 0.5)
	local win = e.ns.notes.EnsureWindow()
	assert_eq(win:GetWidth(), 400)
	assert_eq(win:GetHeight(), 300)
	local _, size = win.edit:GetFont()
	assert_eq(size, 18)
	-- An out-of-range value leaves every stored field untouched.
	c.notesWidth:SetText("10")
	click(c.notesApply)
	assert_eq(e.ns.db.notes.width, 400)
	c.notesWidth:SetText("400")
	c.notesFont:SetText("nan")
	click(c.notesApply)
	assert_eq(e.ns.db.notes.fontSize, 18)
	click(c.notesReset)
	assert_eq(e.ns.db.notes.width, e.ns.DEFAULTS.notes.width)
	assert_eq(e.ns.db.notes.fontSize, e.ns.DEFAULTS.notes.fontSize)
end)

T.register("notes: text is capped and refuses secret or non-string input", function()
	local e = Mocks.NewEnv()
	assert_false(e.ns.notes.SetText(Mocks.MakeSecret()))
	assert_false(e.ns.notes.SetText(42))
	e.ns.notes.SetText(string.rep("x", 30000))
	assert_eq(#e.ns.notes.SiteText(e.ns.notes.ActiveId()), 20000)
	local f = e.ns.notes.Open()
	assert_eq(#f.edit:GetText(), 20000)
	assert_eq(e.ns.notes.Text(), e.ns.notes.SiteText(e.ns.notes.ActiveId()))
end)

T.register("notes: floating window labels stay visible and no idle updater exists", function()
	local e = Mocks.NewEnv()
	local f = e.ns.notes.Open()
	assert_nil(f:GetScript("OnUpdate"))
	assert_not_nil(f._backdrop, "notes window has a styled background")
	local title = Mocks.FindFontString(f, "Do")
	assert_not_nil(title, "the compact notes title must exist")
	assert_true(Mocks.IsRegionVisible(title), "notes title must not be occluded by its editor")
end)

T.register("notes: saved style reaches the tab editor when options opens afterwards", function()
	local e = Mocks.NewEnv()
	assert_true(e.ns.notes.SetStyle({ width = 420, height = 260, fontSize = 20,
		textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 } }))
	local f = e.ns.OpenOptions()
	click(f.controls.notesTab)
	local _, tabSize = f.notesEditor:GetFont()
	assert_eq(tabSize, 20, "tab editor must adopt the persisted font size")
	local win = e.ns.notes.EnsureWindow()
	local _, winSize = win.edit:GetFont()
	assert_eq(winSize, 20)
end)

T.register("notes: hiding the floating window clears editor focus", function()
	local e = Mocks.NewEnv()
	local f = e.ns.notes.Open()
	f.edit:SetFocus()
	assert_true(f.edit:HasFocus())
	click(f.close)
	assert_false(f:IsShown())
	assert_false(f.edit:HasFocus(), "a closed editor must not keep keyboard focus")
end)

T.register("notes: defaults recover from a wrongly typed saved notes table", function()
	local e = Mocks.NewEnv()
	local merged = e.ns.applyDefaults({ notes = "corrupt" }, e.ns.DEFAULTS)
	assert_true(type(merged.notes) == "table", "a non-table saved value is replaced by defaults")
	assert_eq(merged.notes.width, e.ns.DEFAULTS.notes.width)
	assert_true(type(merged.notes.textColor) == "table")
	assert_eq(merged.notes.textColor[1], e.ns.DEFAULTS.notes.textColor[1])
	assert_true(type(merged.notes.sites) == "table")
end)

T.register("notes: corrupt topic entries are repaired, not duplicated or lost", function()
	local e = Mocks.NewEnv()
	-- A saved list with a bad entry is rebuilt, keeping the valid one.
	e.ns.db.notes.sites = { { id = "site-7", title = "Keep", text = "body" }, { id = 5, title = "bad" } }
	local sites = e.ns.notes.Sites()
	assert_eq(#sites, 1)
	assert_eq(sites[1].text, "body")
	-- AddSite never collides with an existing id.
	local site = e.ns.notes.AddSite("Second")
	assert_not_nil(site)
	assert_true(site.id ~= "site-7")
	assert_eq(#e.ns.notes.Sites(), 2)
end)

T.register("notes: slash commands manage topics and select by name or index", function()
	local e = Mocks.NewEnv()
	e.ns.HandleCommand("notes new Raiding")
	assert_eq(#e.ns.notes.Sites(), 2)
	assert_eq(e.ns.notes.ActiveSite().title, "Raiding")
	e.ns.notes.SetText("flask at pull")
	e.ns.HandleCommand("notes new Gold")
	e.ns.HandleCommand("notes prev")
	assert_eq(e.ns.notes.ActiveSite().title, "Raiding")
	e.ns.HandleCommand("notes site 1")
	assert_eq(e.ns.notes.ActiveSite().title, "General")
	e.ns.HandleCommand("notes site gold")
	assert_eq(e.ns.notes.ActiveSite().title, "Gold")
	e.ns.HandleCommand("notes list")
	assert_true(#Mocks.chat > 0, "list prints the topics")
	e.ns.HandleCommand("notes delete")
	assert_eq(#e.ns.notes.Sites(), 2)
	e.ns.HandleCommand("notes delete")
	e.ns.HandleCommand("notes delete")
	assert_eq(#e.ns.notes.Sites(), 1, "the last topic survives repeated deletes")
end)

T.register("notes: binding entry point toggles the floating window", function()
	local e = Mocks.NewEnv()
	assert_true(type(EllesmereUI_HoTPrediction_ToggleNotes) == "function")
	EllesmereUI_HoTPrediction_ToggleNotes()
	assert_true(e.ns.notes.window:IsShown())
	EllesmereUI_HoTPrediction_ToggleNotes()
	assert_false(e.ns.notes.window:IsShown())
end)

T.register("notes: metadata icon texture is configured in TOC", function()
	local toc = ReadFile((_G.__HOT_ROOT or ".") .. "/DoHelper/DoHelper.toc")
	assert_not_nil(toc, "TOC file must be readable")
	assert_true(contains(toc, "## IconTexture: Interface\\Icons\\INV_Misc_Note_01"), "TOC must define note icon texture")
end)

T.register("notes: style persistence, apply, reset, and atomic validation", function()
	local e = Mocks.NewEnv()
	local defaults = e.ns.DEFAULTS.notes
	assert_not_nil(defaults.titleColor, "defaults has titleColor")
	assert_not_nil(defaults.borderColor, "defaults has borderColor")
	assert_not_nil(defaults.editorBackground, "defaults has editorBackground")
	assert_false(defaults.outline, "default outline is false")

	local initial = e.ns.notes.Style()
	assert_eq(initial.outline, false)
	assert_eq(initial.titleColor[1], defaults.titleColor[1])
	assert_eq(initial.borderColor[1], defaults.borderColor[1])
	assert_eq(initial.editorBackground[4], defaults.editorBackground[4])

	-- Apply valid full custom style
	local custom = {
		width = 450,
		height = 320,
		fontSize = 18,
		outline = true,
		textColor = { 0.8, 0.85, 0.9 },
		titleColor = { 0.2, 0.7, 0.6 },
		borderColor = { 0.3, 0.4, 0.5 },
		background = { 0.1, 0.12, 0.15, 0.9 },
		editorBackground = { 0.05, 0.06, 0.08, 0.6 },
	}
	local ok, err = e.ns.notes.SetStyle(custom)
	assert_true(ok, "valid custom style applies successfully")

	local win = e.ns.notes.EnsureWindow()
	assert_eq(win:GetWidth(), 450)
	assert_eq(win:GetHeight(), 320)
	assert_eq(win._backdropColor[4], 0.9)
	assert_eq(win._borderColor[1], 0.3)
	assert_eq(win.edit._backdropColor[4], 0.6)
	assert_eq(win.edit._borderColor[1], 0.3)
	assert_eq(win.title._color[2], 0.7)
	local _, winFont, winFlags = win.edit:GetFont()
	assert_eq(winFont, 18)
	assert_eq(winFlags, "OUTLINE")

	-- Options tab editor mirrors styling
	local f = e.ns.OpenOptions()
	click(f.controls.notesTab)
	local _, tabFont, tabFlags = f.notesEditor:GetFont()
	assert_eq(tabFont, 18)
	assert_eq(tabFlags, "OUTLINE")
	assert_eq(f.notesEditor._backdropColor[4], 0.6)
	assert_eq(f.notesEditor._borderColor[1], 0.3)

	-- Atomic validation: invalid entries reject all modifications
	local badStyles = {
		{ field = "titleColor > 1", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 }, titleColor = { 1, 2, 0 } } },
		{ field = "borderColor < 0", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 }, borderColor = { -1, 0, 0 } } },
		{ field = "editorBackground missing component", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 }, editorBackground = { 0, 0, 0 } } },
		{ field = "editorBackground < 0", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 }, editorBackground = { 0, 0, 0, -0.5 } } },
		{ field = "textColor NaN", style = { width = 450, height = 320, fontSize = 18, textColor = { 0, 0/0, 0 }, background = { 0, 0, 0, 1 } } },
		{ field = "textColor inf", style = { width = 450, height = 320, fontSize = 18, textColor = { 0, 1/0, 0 }, background = { 0, 0, 0, 1 } } },
		{ field = "textColor non-table", style = { width = 450, height = 320, fontSize = 18, textColor = "invalid", background = { 0, 0, 0, 1 } } },
		{ field = "textColor secret component (RGB)", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, Mocks.MakeSecret(), 0 }, background = { 0, 0, 0, 1 } } },
		{ field = "borderColor secret component (RGB)", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 }, borderColor = { Mocks.MakeSecret(), 0.5, 0.5 } } },
		{ field = "background secret component (RGBA)", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, Mocks.MakeSecret() } } },
		{ field = "editorBackground secret component (RGBA)", style = { width = 450, height = 320, fontSize = 18, textColor = { 1, 1, 1 }, background = { 0, 0, 0, 1 }, editorBackground = { 0.1, Mocks.MakeSecret(), 0.3, 0.9 } } },
	}
	for _, tc in ipairs(badStyles) do
		local okBad, msg = e.ns.notes.SetStyle(tc.style)
		assert_false(okBad, tc.field .. " must fail validation")
		-- Stored DB values remained unchanged
		assert_eq(e.ns.db.notes.width, 450)
		assert_eq(e.ns.db.notes.outline, true)
		assert_eq(e.ns.db.notes.titleColor[2], 0.7)
		assert_eq(e.ns.db.notes.borderColor[1], 0.3)
		assert_eq(e.ns.db.notes.editorBackground[4], 0.6)
	end

	-- Outline checkbox: live apply, Apply synchronization, and Reset
	local outlineCb = f.controls.notesOutline
	assert_true(outlineCb:GetChecked(), "outline checkbox reflects true from custom style")
	outlineCb:SetChecked(false)
	click(outlineCb)
	assert_false(e.ns.db.notes.outline, "unchecking outline applies live to db")
	local _, _, offWinFlags = win.edit:GetFont()
	local _, _, offTabFlags = f.notesEditor:GetFont()
	assert_eq(offWinFlags, "", "floating editor drops outline live")
	assert_eq(offTabFlags, "", "tab editor drops outline live")

	outlineCb:SetChecked(true)
	click(outlineCb)
	assert_true(e.ns.db.notes.outline, "checking outline applies live to db")
	local _, _, onWinFlags = win.edit:GetFont()
	local _, _, onTabFlags = f.notesEditor:GetFont()
	assert_eq(onWinFlags, "OUTLINE", "floating editor gains outline live")
	assert_eq(onTabFlags, "OUTLINE", "tab editor gains outline live")

	-- Apply style preserves the checked outline
	click(f.controls.notesApply)
	assert_true(e.ns.db.notes.outline, "Apply preserves outline state")
	assert_true(outlineCb:GetChecked(), "outline checkbox stays checked after Apply")

	-- GUI controls and Reset style restores defaults
	click(f.controls.notesReset)
	assert_eq(e.ns.db.notes.width, defaults.width)
	assert_eq(e.ns.db.notes.fontSize, defaults.fontSize)
	assert_eq(e.ns.db.notes.outline, false)
	assert_eq(e.ns.db.notes.titleColor[1], defaults.titleColor[1])
	assert_eq(e.ns.db.notes.borderColor[1], defaults.borderColor[1])
	assert_eq(e.ns.db.notes.editorBackground[4], defaults.editorBackground[4])
	assert_false(outlineCb:GetChecked(), "Reset restores unchecked outline box")
	local _, _, resetWinFlags = win.edit:GetFont()
	local _, _, resetTabFlags = f.notesEditor:GetFont()
	assert_eq(resetWinFlags, "", "floating editor drops outline after Reset")
	assert_eq(resetTabFlags, "", "tab editor drops outline after Reset")
end)

T.register("notes: skin migration preserves saved custom colors but themes defaults", function()
	Mocks.Reset()
	_G.EllesmereUI_HoTPredictionDB = {
		schema = 2,
		notes = { textColor = { 1, 0.5, 0.2 }, titleColor = { 0.8, 0.3, 0.1 } },
	}
	Mocks.BuildEUF()
	local custom = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	assert_false(custom.notes.UsesSkinColors(), "existing custom note colors remain independent")
	assert_eq(custom.db.notes.textColor[1], 1)
	assert_eq(custom.db.schema, 3)

	Mocks.Reset()
	_G.EllesmereUI_HoTPredictionDB = { schema = 2, notes = { text = "old reminder" } }
	Mocks.BuildEUF()
	local defaults = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	assert_true(defaults.notes.UsesSkinColors(), "default notes adopt the whole-addon skin")
	assert_eq(defaults.db.notes.text, "old reminder")
end)

T.register("notes: visibility open and closed states survive simulated reload", function()
	local e = Mocks.NewEnv()
	assert_false(e.ns.db.notes.shown, "default notes.shown is false")

	-- 1. Opening the note sets shown = true
	local win = e.ns.notes.Open()
	assert_true(win:IsShown())
	assert_true(e.ns.db.notes.shown)

	-- Set customized content, collapsed state, and position
	win.edit:SetText("persisted reminder across reload")
	e.ns.notes.SetCollapsed(true)
	e.ns.db.notes.x = 75
	e.ns.db.notes.y = -120

	-- 2. Simulate reload: PLAYER_LOGIN restores the previously open note
	e.ns.notes.HandleEvent("PLAYER_LOGIN")
	assert_true(win:IsShown(), "open note is restored after login")
	assert_true(e.ns.db.notes.shown)
	assert_true(e.ns.notes.IsCollapsed(), "collapsed pill state preserved across reload")
	assert_eq(e.ns.notes.Text(), "persisted reminder across reload", "note text preserved across reload")
	assert_eq(e.ns.db.notes.x, 75, "position x preserved")
	assert_eq(e.ns.db.notes.y, -120, "position y preserved")

	-- 3. Exercise direct frame Hide (not notes.Close)
	win:Hide()
	assert_false(win:IsShown(), "frame is hidden")
	assert_false(e.ns.db.notes.shown, "direct frame Hide must synchronize shown to false via OnHide")

	-- 4. Simulate reload while closed: PLAYER_LOGIN leaves it hidden
	e.ns.notes.HandleEvent("PLAYER_LOGIN")
	assert_false(win:IsShown(), "previously closed note remains hidden after reload")
	assert_false(e.ns.db.notes.shown, "shown flag stays false")

	-- 5. Reopen after closed state restores properly
	e.ns.notes.Open()
	assert_true(win:IsShown())
	assert_true(e.ns.db.notes.shown)
	assert_true(e.ns.notes.IsCollapsed(), "collapsed state still preserved")
	assert_eq(e.ns.notes.Text(), "persisted reminder across reload", "text still preserved")

	-- 6. Native OnShow script synchronizes shown to true
	win:Hide()
	assert_false(e.ns.db.notes.shown)
	win:Show()
	local onShow = win:GetScript("OnShow")
	assert_not_nil(onShow, "floating frame registers native OnShow script")
	onShow(win)
	assert_true(e.ns.db.notes.shown, "native OnShow synchronizes shown to true")

	-- 7. notes.Open also synchronizes shown to true and opens frame
	win:Hide()
	assert_false(e.ns.db.notes.shown)
	e.ns.notes.Open()
	assert_true(win:IsShown())
	assert_true(e.ns.db.notes.shown, "notes.Open restores shown state")
end)

T.register("notes: secret color values in RGB and RGBA are refused and preserve saved style", function()
	local e = Mocks.NewEnv()
	local initial = e.ns.notes.Style()

	-- Secret in RGB component (textColor, borderColor, titleColor)
	local badRGB = {
		width = 400, height = 300, fontSize = 16,
		textColor = { 1, Mocks.MakeSecret(), 0 },
		background = { 0, 0, 0, 1 },
	}
	local ok, msg = e.ns.notes.SetStyle(badRGB)
	assert_false(ok, "secret RGB component must fail validation")
	assert_eq(msg, "Text RGB must be 0-1 each.")
	assert_eq(e.ns.db.notes.width, e.ns.DEFAULTS.notes.width, "saved style unchanged")

	local badBorder = {
		width = 400, height = 300, fontSize = 16,
		textColor = { 1, 1, 1 },
		background = { 0, 0, 0, 1 },
		borderColor = { 0.2, 0.2, Mocks.MakeSecret() },
	}
	ok, msg = e.ns.notes.SetStyle(badBorder)
	assert_false(ok, "secret border RGB component must fail validation")
	assert_eq(msg, "Border RGB must be 0-1 each.")

	-- Secret in RGBA component (background, editorBackground)
	local badRGBA = {
		width = 400, height = 300, fontSize = 16,
		textColor = { 1, 1, 1 },
		background = { 0, 0, 0, Mocks.MakeSecret() },
	}
	ok, msg = e.ns.notes.SetStyle(badRGBA)
	assert_false(ok, "secret background RGBA component must fail validation")
	assert_eq(msg, "Background RGBA must be 0-1 each.")

	local badEditBg = {
		width = 400, height = 300, fontSize = 16,
		textColor = { 1, 1, 1 },
		background = { 0, 0, 0, 1 },
		editorBackground = { Mocks.MakeSecret(), 0.1, 0.2, 0.8 },
	}
	ok, msg = e.ns.notes.SetStyle(badEditBg)
	assert_false(ok, "secret editorBackground RGBA component must fail validation")
	assert_eq(msg, "Editor background RGBA must be 0-1 each.")

	-- Secret style table and secret color tables themselves
	assert_false(e.ns.notes.SetStyle(Mocks.MakeSecret()), "secret style table fails")
	assert_false(e.ns.notes.SetStyle({
		width = 400, height = 300, fontSize = 16,
		textColor = Mocks.MakeSecret(),
		background = { 0, 0, 0, 1 },
	}), "secret textColor table fails")

	-- Saved style was completely untouched throughout
	local current = e.ns.notes.Style()
	assert_eq(current.width, initial.width)
	assert_eq(current.textColor[1], initial.textColor[1])
	assert_eq(current.background[4], initial.background[4])
	assert_eq(current.borderColor[1], initial.borderColor[1])
	assert_eq(current.editorBackground[4], initial.editorBackground[4])
end)
