local function click(widget) widget:GetScript("OnClick")(widget) end
local function contains(text, fragment) return text:find(fragment, 1, true) ~= nil end

T.register("spell catalog: GUI tabs switch cleanly and catalog scrolls without side effects", function()
	local e = Mocks.NewEnv()
	assert_nil(e.ns.optionsWindow)
	local f = e.ns.OpenOptions()
	assert_eq(f.selectedTab, "settings")
	assert_true(f.settingsPage:IsShown()); assert_false(f.spellsPage:IsShown())
	local saved = e.ns.db.queuedSwingEnabled
	f.controls.alpha:SetFocus()
	click(f.controls.spellsTab)
	assert_eq(f.selectedTab, "spells")
	assert_false(f.settingsPage:IsShown()); assert_true(f.spellsPage:IsShown())
	assert_false(f.controls.alpha:HasFocus())
	assert_eq(e.ns.db.queuedSwingEnabled, saved)
	assert_nil(e.ns.session.fake)
	assert_nil(f.spellsPage:GetScript("OnUpdate"))
	local text = f.catalogSnapshot
	assert_true(contains(text, "Rejuvenation")); assert_true(contains(text, "25299"))
	assert_true(contains(text, "Riptide")); assert_true(contains(text, "1239243"))
	assert_true(contains(text, "Heroic Strike")); assert_true(contains(text, "47450"))
	assert_true(contains(text, "Other players' HoTs are NOT implemented"))
	assert_true(contains(text, "CANDIDATES: MANUAL / OBSERVATION ONLY"))
	assert_true(contains(text, "Lifebloom")); assert_true(contains(text, "Germination"))
	assert_true(f.catalogScroll:GetVerticalScrollRange() > 0)
	f.catalogScroll:GetScript("OnMouseWheel")(f.catalogScroll, -10)
	assert_true(f.catalogScroll:GetVerticalScroll() > 0)
	click(f.controls.settingsTab)
	assert_true(f.settingsPage:IsShown()); assert_false(f.spellsPage:IsShown())
	click(f.controls.spellsTab)
	click(f.controls.close)
	assert_false(f:IsShown())
	e.ns.OpenOptions()
	assert_eq(e.ns.optionsWindow, f); assert_eq(f.selectedTab, "spells")
end)

T.register("spell catalog: every registry ID appears and custom/disabled entries refresh on open", function()
	local e = Mocks.NewEnv()
	e.ns.HandleCommand("spell add 99999 CustomHoT")
	e.ns.HandleCommand("spell remove 774")
	local text = e.ns.BuildSpellCatalog()
	assert_true(contains(text, "CustomHoT")); assert_true(contains(text, "99999"))
	assert_true(contains(text, "Disabled by your settings: 774"))
	for id in pairs(e.ns.spells.BASE) do assert_true(contains(text, tostring(id))) end
	for id in pairs(e.ns.queuedSwing.spells) do assert_true(contains(text, tostring(id))) end
	local f = e.ns.OpenOptions()
	click(f.controls.spellsTab)
	e.ns.HandleCommand("spell add 99998 NewHoT")
	assert_false(contains(f.catalogSnapshot, "NewHoT"), "snapshot has no background updater")
	click(f.controls.settingsTab); click(f.controls.spellsTab)
	assert_true(contains(f.catalogSnapshot, "NewHoT"))
	assert_eq(f.catalogScroll:GetVerticalScroll(), 0)
	assert_nil(e.ns.session.fake)
end)

T.register("spell catalog: text renders above the decorative catalog background", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.spellsTab)
	assert_true(f.spellsPage:IsShown())
	-- The catalog backdrop is a BACKGROUND draw-layer texture on the catalog
	-- frame; a child frame here would also cover the window tabs' hit area.
	assert_not_nil(Mocks.FindTexture(f.spellsPage, "BACKGROUND"), "catalog background must be a texture")
	for _, card in ipairs(f.catalogRows) do
		if card:IsShown() then
			assert_true(Mocks.IsRegionVisible(card.title), "catalog card title must stay readable")
			if card.note:GetText() ~= "" then assert_true(Mocks.IsRegionVisible(card.note)) end
		end
	end
	-- Background decoration is a texture: it has no mouse surface at all.
	local fill = Mocks.FindTexture(f.spellsPage, "BACKGROUND")
	assert_nil(fill.EnableMouse, "background decoration must not intercept mouse input")
	assert_true(f.controls.spellsTab:IsShown() and f.controls.settingsTab:IsShown())
end)

T.register("spell catalog: class icon filters and reusable cards expose readable rank details", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.spellsTab)
	local initialRows = #f.catalogRows
	for _, class in ipairs(e.ns.catalogClasses) do
		if class.key ~= "CUSTOM" then
			assert_not_nil(f.catalogClassButtons[class.key])
			click(f.catalogClassButtons[class.key])
			assert_eq(f.catalogFilter, class.key)
			assert_eq(f.catalogScroll:GetVerticalScroll(), 0)
			local entries = 0
			for _, card in ipairs(f.catalogRows) do
				if card:IsShown() then
					assert_not_nil(card.icon:GetTexture())
					assert_true(card.title:GetText() ~= "")
					assert_true(Mocks.IsRegionVisible(card.title))
					if card.entry and card.key:sub(1,6) ~= "class:" then
						assert_eq(card.entry.class, class.key)
						entries = entries + 1
					end
				end
			end
			assert_true(entries > 0, "reviewed class must have coverage or exclusion cards")
		end
	end
	click(f.catalogClassButtons.HUNTER)
	local raptor
	for _, card in ipairs(f.catalogRows) do if card:IsShown() and card.title:GetText() == "Raptor Strike" then raptor = card end end
	assert_not_nil(raptor)
	assert_eq(raptor.ids:GetText(), "")
	click(raptor.details)
	assert_true(contains(raptor.ids:GetText(), "2973")); assert_true(contains(raptor.ids:GetText(), "14266"))
	assert_true(contains(raptor.status:GetText(), "Next-swing queue"))
	click(raptor.details); assert_eq(raptor.ids:GetText(), "")
	click(f.catalogClassButtons.ALL)
	assert_eq(#f.catalogRows, initialRows, "pool reuses existing rows rather than growing on every refresh")
	assert_nil(e.ns.session.fake)
	assert_nil(f.catalogScroll:GetScript("OnUpdate"))
end)

T.register("spell catalog: registry coverage grouped by class includes conditional limitations", function()
	local e = Mocks.NewEnv()
	local classes, ids, queueIDs = {}, {}, {}
	local total = 0
	for _, group in ipairs(e.ns.GetSpellCatalog()) do
		classes[group.key] = true; total = total + (group.count or 0)
		for _, row in ipairs(group.rows) do
			assert_eq(row.class, group.key)
			for _, id in ipairs(row.ids) do
				if row.key:sub(1, 6) == "queue:" then queueIDs[id] = true else ids[id] = true end
			end
		end
	end
	assert_eq(total, 503)
	for id in pairs(e.ns.spells.BASE) do assert_true(ids[id], "healing rank missing from catalog " .. id) end
	for id in pairs(e.ns.queuedSwing.spells) do assert_true(queueIDs[id], "queue rank missing " .. id) end
	assert_true(classes.MAGE and classes.ROGUE and classes.PALADIN and classes.SHAMAN)
	local text = e.ns.BuildSpellCatalog()
	assert_true(contains(text, "Needs triggered aura IDs"))
	assert_true(contains(text, "Pet healing excluded"))
	assert_true(contains(text, "Forever Bloodthirst grants movement speed"))
	assert_true(contains(text, "Holy Strike explicitly attacks instantly"))
end)
