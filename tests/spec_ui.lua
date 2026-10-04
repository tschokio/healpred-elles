local function click(w) w:GetScript("OnClick")(w) end
local tabs = { settingsTab = "settings", spellsTab = "spells", notesTab = "notes", combatTab = "combat", soundsTab = "sounds", weaponTab = "weapons" }

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
	for _, page in ipairs({ f.sidebar, f.settingsPage, f.notesPage, f.combatPage, f.spellsPage, f.soundsPage, f.weaponPage, f.preview, f.helpPanel }) do
		local r = Mocks.FrameRect(page)
		assert_true(r.left >= root.left and r.right <= root.right and r.top <= root.top and r.bottom >= root.bottom)
	end
	for _, page in ipairs({ f.settingsPage, f.notesPage, f.combatPage, f.spellsPage, f.soundsPage }) do
		assert_false(Mocks.RectsOverlap(Mocks.FrameRect(page), Mocks.FrameRect(f.sidebar)))
		assert_false(Mocks.RectsOverlap(Mocks.FrameRect(page), Mocks.FrameRect(f.helpPanel)))
	end
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
	assert_eq(f.controls.soundsPath._template, "BackdropTemplate")
end)

T.register("UI: changing pages and closing clear input focus without changing settings", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("sounds")
	f.controls.soundsPath:SetFocus()
	click(f.controls.notesTab)
	assert_false(f.controls.soundsPath:HasFocus())
	f.controls.notesTitle:SetFocus()
	click(f.controls.headerClose)
	assert_false(f.controls.notesTitle:HasFocus())
	assert_false(f:IsShown())
	assert_eq(e.ns.db.critSounds.path, "")
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
