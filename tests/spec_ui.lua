local function click(w) w:GetScript("OnClick")(w) end
local tabs = { settingsTab = "settings", spellsTab = "spells", notesTab = "notes", combatTab = "combat", weaponTab = "weapons", skinsTab = "skins", chatTab = "chat" }

T.register("UI: sidebar navigation has one selection and disjoint readable rows", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	for key, tab in pairs(tabs) do
		click(f.controls[key])
		assert_eq(f.selectedTab, tab)
		assert_eq(f.pageTitle:GetText(), f.controls[key]:GetText())
		for other, value in pairs(tabs) do
			local b = f.controls[other]
			assert_eq(b:GetParent(), f.sidebar)
			assert_eq(b.uiSelected, value == tab)
			assert_eq(b.uiIndicator:IsShown(), value == tab)
			if other ~= key then assert_false(Mocks.RectsOverlap(Mocks.FrameRect(b), Mocks.FrameRect(f.controls[key]))) end
		end
	end
end)

T.register("UI: layout stays inside shell and aside never covers page content", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	local root = Mocks.FrameRect(f)
	for _, page in ipairs({ f.sidebar, f.settingsPage, f.notesPage, f.combatPage, f.spellsPage, f.weaponPage, f.skinPage, f.chatPage, f.preview, f.helpPanel }) do
		local r = Mocks.FrameRect(page)
		assert_true(r.left >= root.left and r.right <= root.right and r.top <= root.top and r.bottom >= root.bottom)
	end
	for _, page in ipairs({ f.settingsPage, f.notesPage, f.combatPage, f.spellsPage, f.skinPage, f.chatPage }) do
		assert_false(Mocks.RectsOverlap(Mocks.FrameRect(page), Mocks.FrameRect(f.sidebar)))
		assert_false(Mocks.RectsOverlap(Mocks.FrameRect(page), Mocks.FrameRect(f.helpPanel)))
	end
end)

T.register("UI: whole-addon skins recolor shared widgets, floating notes and persist", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	assert_eq(e.ns.db.uiSkin, "classic")
	assert_true(f.skinPage ~= nil)
	click(f.controls.skinsTab)
	assert_eq(f.selectedTab, "skins")
	assert_true(f.controls.skin_accentR ~= nil)
	local notes = e.ns.notes.Open()
	assert_true(e.ns.notes.UsesSkinColors())
	click(f.skinButtons.ember)
	assert_eq(e.ns.db.uiSkin, "ember")
	assert_near(f.skinButtons.ember.uiFill._vertexColor[1], e.ns.ui.colors.selected[1])
	assert_near(f.graphicsPage.rows.groundEffectDensity.slider._thumbTexture._vertexColor[1], e.ns.ui.colors.accent[1])
	assert_near(notes._backdropColor[1], e.ns.ui.colors.noteWindow[1])
	assert_near(notes.title._color[1], e.ns.ui.colors.noteTitle[1])
	for _, role in ipairs({ "accent", "window", "panel", "text", "border" }) do
		for component = 1, 3 do f.controls["skin_" .. role .. ({"R", "G", "B"})[component]]:SetText("0.4") end
	end
	click(f.skinApply)
	assert_eq(e.ns.db.uiSkin, "custom")
	assert_near(e.ns.ui.colors.accent[1], 0.4)
	assert_near(e.ns.ui.colors.border[3], 0.4)
	assert_eq(e.ns.db.notes.useSkinColors, true)
	click(f.controls.notesTab)
	f.controls.notesFollowSkin:SetChecked(false)
	click(f.controls.notesFollowSkin)
	assert_false(e.ns.notes.UsesSkinColors())
	local customTitle = notes.title._color[1]
	click(f.controls.skinsTab)
	click(f.skinButtons.classic)
	assert_near(notes.title._color[1], customTitle, 1e-6, "Notes keep custom colors when follow-skin is off")
end)

T.register("UI: custom skin palette is restored from saved settings on startup", function()
	local e = Mocks.NewEnv()
	local colors = {
		accent = { 0.21, 0.43, 0.65 }, window = { 0.11, 0.22, 0.33 },
		panel = { 0.31, 0.42, 0.53 }, text = { 0.81, 0.82, 0.83 }, border = { 0.41, 0.52, 0.63 },
	}
	assert_true(e.ns.ui.SetSkin("custom", colors, "ember"))
	local saved = EllesmereUI_HoTPredictionDB
	Mocks.Reset()
	_G.EllesmereUI_HoTPredictionDB = saved
	Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	assert_eq(ns.ui.currentSkin, "custom")
	assert_eq(ns.ui.currentSkinBase, "ember")
	assert_near(ns.ui.colors.accent[1], 0.21)
	assert_near(ns.ui.colors.window[3], 0.33)
	assert_near(ns.ui.colors.noteTitle[1], 0.21)
	assert_near(ns.ui.colors.noteText[3], 0.83)
end)

T.register("UI: button styling preserves click handlers and tooltip hooks", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	local b = f.controls.notesTab
	local before = b.uiFill._vertexColor[2]
	b:GetScript("OnEnter")(b)
	assert_true(b.uiHover)
	assert_true(b.uiFill._vertexColor[2] > before)
	b:GetScript("OnLeave")(b); assert_false(b.uiHover)
	click(b); assert_eq(f.selectedTab, "notes")
	assert_eq(f.controls.notesApply.uiTone, "primary")
	assert_eq(f.controls.notesDelete.uiTone, "danger")
	assert_eq(f.controls.combatEnter._template, "BackdropTemplate")
end)

T.register("UI: changing pages and closing clear input focus without changing settings", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("combat")
	f.controls.combatEnter:SetFocus()
	click(f.controls.notesTab)
	assert_false(f.controls.combatEnter:HasFocus())
	f.controls.notesTitle:SetFocus()
	click(f.controls.headerClose)
	assert_false(f.controls.notesTitle:HasFocus())
	assert_false(f:IsShown())
	assert_eq(e.ns.db.alpha, 0.6)
end)

T.register("UI: settings fit smaller screens on open and restore full scale on larger screens", function()
	local e = Mocks.NewEnv()
	UIParent:SetSize(800, 600)
	local f = e.ns.OpenOptions()
	assert_true(f:GetScale() < 1)
	assert_true(f:GetWidth() * f:GetScale() <= 768)
	assert_true(f:GetHeight() * f:GetScale() <= 568)
	UIParent:SetSize(1920, 1080)
	e.ns.OpenOptions(); assert_eq(f:GetScale(), 1)
end)

T.register("UI: notes preserve saved styling and compact dimensions with themed controls", function()
	local e = Mocks.NewEnv()
	e.ns.notes.SetStyle({ width = 400, height = 300, fontSize = 20, textColor = { 1, 0.5, 0 }, background = { 0.1, 0.2, 0.3, 0.4 } })
	local f = e.ns.notes.Open()
	assert_not_nil(f.collapse.uiFill)
	assert_not_nil(f.siteTitle.uiInput)
	assert_eq(f._backdropColor[4], 0.4)
	assert_eq(select(2, f.edit:GetFont()), 20)
	e.ns.notes.SetCollapsed(true)
	assert_eq(f:GetWidth(), 60); assert_eq(f:GetHeight(), 22)
	assert_eq(f.collapse:GetText(), "^")
end)

T.register("UI: notes page controls fit and do not overlap", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.notesTab)
	local page = f.notesPage
	local pageRect = Mocks.FrameRect(page)
	local keys = {
		"notesPrev", "notesNext", "notesTitle", "notesNew", "notesDelete",
		"notesWidth", "notesHeight", "notesOutline",
		"notesFollowSkin",
		"notesFont", "notesTextR", "notesTextG", "notesTextB",
		"notesTitleR", "notesTitleG", "notesTitleB",
		"notesBorderR", "notesBorderG", "notesBorderB",
		"notesBgR", "notesBgG", "notesBgB", "notesBgA",
		"notesEditBgR", "notesEditBgG", "notesEditBgB", "notesEditBgA",
		"notesApply", "notesReset", "notesShow", "notesCollapse", "notesClose",
	}
	local rects = {}
	for _, key in ipairs(keys) do
		local ctrl = f.controls[key]
		assert_not_nil(ctrl, "control must exist: " .. key)
		local r = Mocks.FrameRect(ctrl)
		assert_true(r.left >= pageRect.left and r.right <= pageRect.right, key .. " stays inside page horizontally")
		assert_true(r.top <= pageRect.top and r.bottom >= pageRect.bottom, key .. " stays inside page vertically")
		rects[key] = r
	end
	for i = 1, #keys do
		for j = i + 1, #keys do
			assert_false(Mocks.RectsOverlap(rects[keys[i]], rects[keys[j]]), keys[i] .. " must not overlap " .. keys[j])
		end
	end
end)

T.register("UI: old enabled critSounds saved settings do not resurrect module, tab, or playback/subscriptions", function()
	Mocks.Reset()
	_G.EllesmereUI_HoTPredictionDB = {
		critSounds = {
			enabled = true,
			damage = true,
			healing = true,
			path = "Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3",
			channel = "Master",
			cooldown = 0.5,
		},
	}
	local played = {}
	_G.PlaySound = function(id, channel) played[#played + 1] = { id, channel }; return true end
	_G.PlaySoundFile = function(path, channel) played[#played + 1] = { path, channel }; return true end

	Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	Mocks.Fire("PLAYER_LOGIN")

	-- 1. module not resurrected
	assert_nil(ns.critSounds, "critSounds module must not exist in addon namespace")
	assert_nil(_G.CritSounds, "no global CritSounds")

	-- 2. tab and page not resurrected in options
	local f = ns.OpenOptions()
	assert_nil(f.soundsPage, "sounds page must not exist")
	assert_nil(f.controls.soundsTab, "sounds tab button must not exist")
	assert_nil(f.controls.soundsEnabled, "soundsEnabled checkbox must not exist")
	f.SelectTab("sounds")
	assert_eq(f.selectedTab, "settings", "attempting to select sounds tab falls back to settings")

	-- 3. no subscriptions or playback
	assert_nil(ns.critSounds)
	local t = Mocks.PackCLEU(Mocks.now, "SPELL_DAMAGE", false, Mocks.playerGUID, "Player", 0, 0, Mocks.playerGUID, "Target", 0, 0, 133, "Fireball", 0x4, 500, 0, 0, nil, nil, nil, true)
	Mocks.SetCLEU(t)
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED")
	assert_eq(#played, 0, "no audio playback attempted on crit events")

	-- On restricted engine, old enabled settings acquire no event subscription
	Mocks.Reset()
	Mocks.SetBuild("12.0.1", 1, "", 120001)
	_G.EllesmereUI_HoTPredictionDB = { critSounds = { enabled = true, path = "Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3" } }
	local nsRestricted = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	assert_false(nsRestricted.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "restricted engine acquires no CLEU subscription")

	-- 4. legacy SavedVariables preserved inertly (do not destructively clean data)
	assert_not_nil(ns.db.critSounds, "legacy critSounds table is preserved in DB")
	assert_true(ns.db.critSounds.enabled, "legacy critSounds enabled setting is preserved")
	assert_eq(ns.db.critSounds.path, "Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3", "legacy path preserved")
end)
