local function env(opts)
	local e = Mocks.NewEnv(opts)
	local actions, current, macroSpells, currentSpells = {}, {}, {}, {}
	_G.C_ActionBar, _G.C_Spell = nil, nil
	_G.GetActionInfo = function(slot)
		local a = actions[slot]
		if a then return a[1], a[2] end
	end
	_G.IsCurrentAction = function(slot) return current[slot] == true end
	_G.IsCurrentSpell = function(id) return currentSpells[id] == true end
	_G.GetMacroSpell = function(id) return macroSpells[id] end
	local function button(index, slot, id, kind)
		local b = CreateFrame("CheckButton", "EABButton" .. index, UIParent)
		b:SetAttribute("action", slot)
		actions[slot] = { kind or "spell", id }
		return b
	end
	e.actions, e.current, e.macroSpells, e.currentSpells, e.button = actions, current, macroSpells, currentSpells, button
	e.swing = e.ns.queuedSwing
	return e
end
local function border(e, b) return e.swing.buttons[b].border end
local function poll(e)
	local script = e.swing.driver:GetScript("OnUpdate")
	if script then script(e.swing.driver, 0.05) end
end

T.register("queue: Throw and custom IDs require actual state and reject auto-repeat", function()
	local e = env()
	local throw = e.button(1, 1, 2764)
	local custom = e.button(2, 2, 987654)
	e.swing.Scan()
	assert_false(border(e, throw):IsShown())
	Mocks.Fire("UNIT_SPELLCAST_SENT", "player", "target", "cast", 2764)
	assert_false(border(e, throw):IsShown())
	e.ns.HandleCommand("queue add 987654 Custom Swing")
	assert_eq(e.swing.spells[987654], "Custom Swing")
	assert_nil(e.ns.spells.Meta(987654), "queue registration does not register healing")
	e.current[1], e.current[2] = true, true
	e.swing.Refresh()
	assert_true(border(e, throw):IsShown()); assert_true(border(e, custom):IsShown())
	_G.IsAutoRepeatAction = function(slot) return slot == 2 end
	e.swing.Refresh(); assert_false(border(e, custom):IsShown())
	_G.IsAutoRepeatAction = nil
	e.current[1], e.current[2] = false, false
	e.swing.Refresh()
	assert_false(border(e, throw):IsShown()); assert_false(border(e, custom):IsShown())
end)

T.register("queue: add remove reset and database reinitialization preserve exact registry", function()
	local e = env()
	e.ns.HandleCommand("queue add 987654 Custom Swing")
	e.ns.HandleCommand("queue remove 2764")
	e.ns.InitDatabase(); e.swing.SetEnabled()
	assert_eq(e.swing.spells[987654], "Custom Swing"); assert_nil(e.swing.spells[2764])
	assert_true(e.ns.BuildSpellCatalog():find("Disabled by your settings: 2764", 1, true) ~= nil)
	e.ns.HandleCommand("queue reset 2764"); assert_eq(e.swing.spells[2764], "Throw")
	e.ns.HandleCommand("queue remove 987654"); assert_nil(e.swing.spells[987654])
	e.ns.HandleCommand("queue reset 987654")
	assert_nil(e.ns.db.extraQueueSpells[987654]); assert_nil(e.ns.db.removedQueueSpells[987654])
	for _, id in ipairs({6603, 75, 5019, 0, -1, 1.5, 100000001}) do
		assert_false(e.swing.EditSpell("add", id, "Invalid"))
		assert_nil(e.swing.spells[id])
	end
	assert_false(e.swing.EditSpell("add", 987654, "|cffffffffbad"))
	assert_false(e.swing.EditSpell("add", 987654, string.rep("x", 81)))
end)

T.register("queue: cast attempts and failed resource/range checks never light buttons", function()
	local e = env({ noCLEU = true })
	local b = e.button(1, 1, 6807)
	e.swing.Scan()
	Mocks.Fire("UNIT_SPELLCAST_SENT", "player", "target", "cast", 6807)
	Mocks.Fire("UNIT_SPELLCAST_FAILED", "player", "cast", 6807)
	poll(e)
	assert_false(border(e, b):IsShown())
	assert_eq(e.swing.active, 0)
	e.current[1] = true
	Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	assert_true(border(e, b):IsShown(), "real state paints during event, not next timer")
	assert_eq(border(e, b)._borderColor[4], 1)
	assert_nil(b:GetScript("OnClick"), "no vendor button hooks or click changes")
end)

T.register("queue: execution cancellation and invalidation clear state without a combat log", function()
	local e = env({ noCLEU = true })
	local b = e.button(1, 1, 78)
	e.current[1] = true
	e.swing.Scan()
	e.current[1] = false
	Mocks.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 78)
	assert_false(border(e, b):IsShown())
	e.current[1] = true; Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	e.current[1] = false; Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	assert_false(border(e, b):IsShown())
	e.current[1] = true; Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	e.current[1] = false -- no event: safety poll must still clear it
	poll(e)
	assert_false(border(e, b):IsShown())
end)

T.register("queue: ranks duplicates and replacing Heroic Strike with Cleave", function()
	local e = env()
	local hs = e.button(1, 1, 11567)
	local duplicate = e.button(2, 2, 11567)
	local cleave = e.button(3, 3, 20569)
	e.current[1], e.current[2] = true, true
	e.swing.Scan()
	assert_true(border(e, hs):IsShown()); assert_true(border(e, duplicate):IsShown())
	assert_false(border(e, cleave):IsShown())
	e.current[1], e.current[2], e.current[3] = false, false, true
	Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	assert_false(border(e, hs):IsShown()); assert_false(border(e, duplicate):IsShown())
	assert_true(border(e, cleave):IsShown())
end)

T.register("queue: auto attack autorepeat and unrelated spells are excluded", function()
	local e = env()
	local attack = e.button(1, 1, 6603)
	local hot = e.button(2, 2, 774)
	e.current[1], e.current[2] = true, true
	e.swing.Scan()
	assert_eq(#e.swing.candidates, 0)
	assert_false(border(e, attack):IsShown()); assert_false(border(e, hot):IsShown())
end)

T.register("queue: action slot is live attribute not original name or protected action mirror", function()
	local e = env()
	local b = e.button(1, 73, 6807)
	b.action = Mocks.MakeSecret()
	e.current[73] = true
	e.swing.Scan()
	assert_true(border(e, b):IsShown())
	e.actions[85] = { "spell", 774 }; e.current[85] = true
	b:SetAttribute("action", 85)
	poll(e)
	assert_false(border(e, b):IsShown(), "paging without an event cannot retain previous glow")
	e.actions[85] = { "spell", 9881 }
	Mocks.Fire("UPDATE_SHAPESHIFT_FORM")
	assert_true(border(e, b):IsShown())
end)

T.register("queue: effective macro spell uses real spell state not macro press or tooltip", function()
	local e = env()
	local b = e.button(1, 1, 7, "macro")
	e.macroSpells[7] = 6807
	e.current[1] = true -- a current macro slot alone is not queue evidence
	e.swing.Scan()
	assert_false(border(e, b):IsShown())
	e.currentSpells[6807] = true
	Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	assert_true(border(e, b):IsShown())
	e.macroSpells[7] = 774
	poll(e)
	assert_false(border(e, b):IsShown())
	e.macroSpells[7] = nil
	Mocks.Fire("UPDATE_MACROS")
	assert_eq(#e.swing.candidates, 0)
end)

T.register("queue: missing erroring and secret state fail closed; false stays authoritative", function()
	local e = env()
	local b = e.button(1, 1, 78)
	e.current[1] = true; e.swing.Scan()
	_G.IsCurrentAction = function() return Mocks.MakeSecret() end
	poll(e)
	assert_false(border(e, b):IsShown())
	assert_eq(e.swing.reason, "queue API unavailable/restricted")
	_G.IsCurrentAction = function() error("unavailable") end
	poll(e); assert_false(border(e, b):IsShown())
	_G.IsCurrentAction = nil; _G.IsCurrentSpell = nil
	poll(e); assert_false(border(e, b):IsShown())
	_G.IsCurrentSpell = function() return true end
	poll(e); assert_true(border(e, b):IsShown(), "public spell fallback")
	_G.IsCurrentAction = function() return false end
	poll(e); assert_false(border(e, b):IsShown(), "never override false with fallback")
	b:SetAttribute("action", Mocks.MakeSecret())
	poll(e); assert_false(border(e, b):IsShown())
end)

T.register("queue: modern namespaced adapters and legacy numeric flags", function()
	local e = env()
	local b = e.button(1, 1, 845)
	_G.C_ActionBar = { GetActionInfo = function() return "spell", 845 end,
		IsCurrentAction = function() return 1 end }
	_G.GetActionInfo = nil; _G.IsCurrentAction = nil
	e.swing.Scan(); assert_true(border(e, b):IsShown())
	_G.C_ActionBar.IsCurrentAction = function() return 0 end
	poll(e); assert_false(border(e, b):IsShown())
	_G.C_ActionBar = nil
end)

T.register("queue: combat only updates prepared own borders; late creation waits for regen", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.swing.Scan()
	local old = border(e, b)
	Mocks.inCombat = true
	e.current[1] = true; Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	assert_eq(border(e, b), old); assert_true(old:IsShown())
	local late = e.button(2, 2, 845)
	e.current[2] = true
	e.swing.Scan()
	assert_nil(border(e, late))
	Mocks.inCombat = false; Mocks.Fire("PLAYER_REGEN_ENABLED")
	assert_true(border(e, late):IsShown())
	_G.EABButton1 = nil
	e.swing.Scan()
	assert_false(old:IsShown(), "replaced or removed frames hide old owned borders")
end)

T.register("queue: settings persisted independently; disabling stops poll and hides immediately", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.current[1] = true; e.swing.Scan()
	e.ns.HandleCommand("queue color 1 0.3 0")
	assert_eq(border(e, b)._borderColor[2], 0.3)
	e.ns.HandleCommand("queue color 2 0 0")
	assert_eq(e.ns.db.queuedSwingColor[2], 0.3)
	e.ns.HandleCommand("queue off")
	assert_false(border(e, b):IsShown()); assert_nil(e.swing.driver:GetScript("OnUpdate"))
	e.ns.HandleCommand("queue on")
	assert_true(border(e, b):IsShown())
	e.ns.HandleCommand("enable off")
	assert_false(border(e, b):IsShown()); assert_nil(e.swing.driver:GetScript("OnUpdate"))
	assert_false(e.ns.eventRegistered("ACTIONBAR_UPDATE_STATE"))
	e.ns.HandleCommand("enable on")
	assert_true(border(e, b):IsShown())
	assert_true(e.ns.BuildStatusReport():find("next%-swing enabled=true") ~= nil)
end)

T.register("queue: existing timer discovers late buttons without native heal prediction", function()
	local e = env()
	e.ab._predOn = false
	local b = e.button(1, 1, 6807)
	e.current[1] = true
	Mocks.now = Mocks.now + 1.1
	e.ns.overlay.Tick()
	assert_true(border(e, b):IsShown())
	e.ns.OpenOptions()
	assert_true(e.ns.optionsWindow.controls.queue:GetChecked())
end)

T.register("queue: legacy macro ID tuple and restricted identities are guarded", function()
	local e = env()
	local b = e.button(1, 1, 7, "macro")
	_G.GetMacroSpell = function() return "Maul", "Rank 1", 6807 end
	e.currentSpells[6807] = true
	e.swing.Scan()
	assert_true(border(e, b):IsShown())
	_G.GetMacroSpell = function() return Mocks.MakeSecret() end
	poll(e); assert_false(border(e, b):IsShown())
	_G.GetActionInfo = function() return Mocks.MakeSecret(), Mocks.MakeSecret() end
	poll(e); assert_false(border(e, b):IsShown())
	_G.GetActionInfo = function() error("restricted action info") end
	poll(e); assert_false(border(e, b):IsShown())
end)

local function click(widget) widget:GetScript("OnClick")(widget) end

T.register("queue appearance: GUI saves thickness size opacity and RGB without faking a queue", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.swing.Scan()
	assert_nil(e.ns.queueAppearanceWindow)
	local options = e.ns.OpenOptions()
	click(options.controls.queueAppearance)
	local f = e.ns.queueAppearanceWindow
	assert_true(f:IsShown())
	local c = f.controls
	c.thickness:SetText("6"); c.padding:SetText("8"); c.alpha:SetText("0.4")
	c.red:SetText("1"); c.green:SetText("0.5"); c.blue:SetText("0")
	c.padding:SetFocus()
	click(c.apply)
	assert_eq(e.ns.db.queuedSwingThickness, 6)
	assert_eq(e.ns.db.queuedSwingPadding, 8)
	assert_eq(e.ns.db.queuedSwingAlpha, 0.4)
	assert_eq(EllesmereUI_HoTPredictionDB.queuedSwingColor[2], 0.5)
	assert_false(c.padding:HasFocus())
	local own = border(e, b)
	assert_eq(own._backdrop.edgeSize, 6)
	local _, relative, _, x, y = own:GetPoint(1)
	assert_eq(relative, b); assert_eq(x, -8); assert_eq(y, 8)
	assert_eq(own._borderColor[4], 0.4)
	assert_false(own:IsShown(), "appearance edits do not pretend the ability is queued")
	assert_nil(e.ns.session.fake)
	assert_eq(b:GetWidth(), 100, "actual button size untouched")
	e.current[1] = true; Mocks.Fire("ACTIONBAR_UPDATE_STATE")
	assert_true(own:IsShown())
	assert_eq(own._borderColor[2], 0.5)
	click(c.close); assert_false(f:IsShown())
	e.ns.OpenQueueAppearance(); assert_eq(e.ns.queueAppearanceWindow, f)
	assert_eq(c.padding:GetText(), "8")
	assert_nil(f:GetScript("OnUpdate"))
	local registered = 0
	for _, name in ipairs(UISpecialFrames) do if name == f:GetName() then registered = registered + 1 end end
	assert_eq(registered, 1)
end)

T.register("queue appearance: invalid inputs are atomic and defaults restore only border appearance", function()
	local e = env()
	assert_true(e.swing.SetAppearance(6, -2, 0.5, 1, 0, 0))
	local f = e.ns.OpenQueueAppearance()
	f.controls.thickness:SetText("10"); f.controls.padding:SetText("bad")
	click(f.controls.apply)
	assert_eq(e.ns.db.queuedSwingThickness, 6)
	assert_eq(e.ns.db.queuedSwingPadding, -2)
	assert_false(e.swing.SetAppearance(nil, 3, 1, 0, 1, 1))
	assert_false(e.swing.SetAppearance(0, 3, 1, 0, 1, 1))
	assert_false(e.swing.SetAppearance(13, 3, 1, 0, 1, 1))
	assert_false(e.swing.SetAppearance(3, -13, 1, 0, 1, 1))
	assert_false(e.swing.SetAppearance(3, 25, 1, 0, 1, 1))
	assert_false(e.swing.SetAppearance(3, 3, 2, 0, 1, 1))
	assert_false(e.swing.SetAppearance(3, 3, 1, Mocks.MakeSecret(), 1, 1))
	e.ns.db.alpha = 0.2; e.ns.db.queuedSwingEnabled = false
	click(f.controls.defaults)
	assert_eq(e.ns.db.queuedSwingThickness, 3)
	assert_eq(e.ns.db.queuedSwingPadding, 3)
	assert_eq(e.ns.db.queuedSwingAlpha, 1)
	assert_eq(e.ns.db.queuedSwingColor[1], 0)
	assert_eq(e.ns.db.alpha, 0.2)
	assert_false(e.ns.db.queuedSwingEnabled)
	assert_true(e.swing.SetAppearance(1, -12, 0, 0, 0, 0))
end)

T.register("queue appearance: combat defers geometry but not opacity color or queue clearing", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.current[1] = true; e.swing.Scan()
	local own = border(e, b)
	Mocks.inCombat = true
	assert_true(e.swing.SetAppearance(8, 10, 0.25, 1, 0, 0))
	assert_eq(own._backdrop.edgeSize, 3)
	local _, _, _, x = own:GetPoint(1)
	assert_eq(x, -3)
	assert_eq(own._borderColor[4], 0.25)
	assert_eq(own._borderColor[1], 1)
	e.current[1] = false; poll(e)
	assert_false(own:IsShown())
	Mocks.inCombat = false; Mocks.Fire("PLAYER_REGEN_ENABLED")
	assert_eq(own._backdrop.edgeSize, 8)
	local _, _, _, updated = own:GetPoint(1)
	assert_eq(updated, -10)
	assert_false(own:IsShown())
end)

T.register("queue preview: clicking sample and selecting icons never changes genuine queue state", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.swing.Scan()
	local f = e.ns.OpenOptions()
	assert_true(f.preview.border:IsShown())
	assert_false(border(e, b):IsShown())
	click(f.preview.button)
	assert_false(f.preview.border:IsShown())
	click(f.preview.button)
	assert_true(f.preview.border:IsShown())
	for _, select in ipairs(f.preview.abilities) do click(select) end
	assert_eq(e.swing.active, 0)
	assert_nil(e.ns.session.fake)
	assert_true(e.ns.db.queuedSwingEnabled)
	assert_nil(f.preview:GetScript("OnUpdate"))
	assert_nil(f.preview.button:GetScript("OnUpdate"))
	assert_eq(f.preview.button:GetWidth(), 48)
end)

T.register("queue preview: live draft updates geometry and color but saves only on Apply", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.current[1] = true; e.swing.Scan()
	local main = e.ns.OpenOptions()
	local f = e.ns.OpenQueueAppearance()
	local c, sample = f.controls, f.preview.border
	c.thickness:SetText("7"); c.padding:SetText("12"); c.alpha:SetText("0.2")
	c.red:SetText("1"); c.green:SetText("0"); c.blue:SetText("0.5")
	assert_eq(sample._backdrop.edgeSize, 7)
	local _, relative, _, x = sample:GetPoint(1)
	assert_eq(relative, f.preview.button); assert_eq(x, -12)
	assert_eq(sample._borderColor[4], 0.2)
	assert_eq(sample._borderColor[3], 0.5)
	assert_eq(e.ns.db.queuedSwingThickness, 3)
	assert_eq(border(e, b)._backdrop.edgeSize, 3)
	assert_true(border(e, b):IsShown())
	c.padding:SetText("bad")
	local _, _, _, old = sample:GetPoint(1)
	assert_eq(old, -12, "invalid draft retains last valid sample")
	click(c.apply)
	assert_eq(e.ns.db.queuedSwingThickness, 3)
	c.padding:SetText("12"); click(c.apply)
	assert_eq(e.ns.db.queuedSwingThickness, 7)
	assert_eq(border(e, b)._backdrop.edgeSize, 7)
	assert_eq(main.preview.border._backdrop.edgeSize, 7)
	assert_eq(e.swing.active, 1)
	assert_nil(e.ns.session.fake)
end)

T.register("queue preview: close discards drafts and combat preview has independent geometry", function()
	local e = env()
	local b = e.button(1, 1, 6807)
	e.swing.Scan()
	local f = e.ns.OpenQueueAppearance()
	Mocks.inCombat = true
	f.controls.thickness:SetText("10")
	assert_eq(f.preview.border._backdrop.edgeSize, 10)
	assert_eq(border(e, b)._backdrop.edgeSize, 3)
	click(f.controls.close)
	e.ns.OpenQueueAppearance()
	assert_eq(f.controls.thickness:GetText(), "3")
	assert_eq(f.preview.border._backdrop.edgeSize, 3)
	assert_eq(e.ns.db.queuedSwingThickness, 3)
end)

T.register("queue preview: sample panel labels sit above its own opaque frame", function()
	local e = env()
	local f = e.ns.OpenOptions()
	local pv = f.preview
	-- The sample panel is a real container frame (its labels must live on it),
	-- so nothing on the settings page may cover those labels either.
	for _, l in ipairs(pv._fontStrings) do
		if l:GetText() ~= "" then
			assert_true(Mocks.IsRegionVisible(l), "hidden preview label: " .. l:GetText())
		end
	end
	local state = Mocks.FindFontString(pv, "QUEUED")
	assert_not_nil(state, "queued state label must exist")
	assert_true(state:GetText():find("QUEUED") ~= nil)
	-- Decorative settings-page background is a texture and cannot swallow clicks.
	local fill = Mocks.FindTexture(f.settingsPage, "BACKGROUND")
	assert_not_nil(fill)
	assert_nil(fill.EnableMouse)
	click(pv.button)
	assert_false(pv.border:IsShown())
	click(pv.button)
	assert_true(pv.border:IsShown())
	assert_nil(e.ns.session.fake)
end)
