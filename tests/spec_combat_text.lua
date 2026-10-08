-- tests/spec_combat_text.lua
-- Small centered +combat/-combat line with persisted styling, optional scroll
-- and independent enter/leave colours.
local function click(widget, ...)
	widget:GetScript("OnClick")(widget, ...)
end

local function optIn(env)
	env.ns.db.combatText.enabled = true
	env.ns.combatText.Refresh()
end

local function style(ct, o)
	o = o or {}
	return ct.SetStyle({
		fontSize = o.fontSize or 20,
		opacity = o.opacity or 1,
		duration = o.duration or 2,
		fade = o.fade or 0,
		x = o.x or 0,
		y = o.y or 0,
		outline = o.outline or false,
		color = o.color or { 1, 1, 1 },
		background = o.background or { 0, 0, 0, 0 },
		enterText = o.enterText,
		leaveText = o.leaveText,
		enterColor = o.enterColor,
		leaveColor = o.leaveColor,
		direction = o.direction,
		distance = o.distance,
		motion = o.motion,
	})
end

-- A fresh SavedVariables table before ADDON_LOADED, for migration tests.
local function presetEnv(db)
	Mocks.Reset()
	_G.EllesmereUI_HoTPredictionDB = db
	Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	Mocks.Fire("PLAYER_LOGIN")
	return ns
end

T.register("combat text: enter and leave transitions show the matching label", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	assert_not_nil(ct.eventFrame, "combat text owns an event frame")
	local f = ct.EnsureFrame()
	assert_false(f:IsShown(), "hidden until the first transition")
	assert_false(ct.Enabled(), "disabled by default until the user opts in")
	ct.Show("enter")
	assert_false(f:IsShown(), "disabled combat text ignores transitions")
	e.ns.db.combatText.enabled = true
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_DISABLED")
	assert_true(f:IsShown())
	assert_eq(f.label:GetText(), "+ combat")
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_ENABLED")
	assert_true(f:IsShown())
	assert_eq(f.label:GetText(), "- combat")
	assert_false(f._mouseEnabled, "click-through by default")
end)

T.register("combat text: timed line hides after its duration and 0 stays until the next change", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	assert_true(style(ct, { duration = 2, distance = 0 }))
	local f = ct.EnsureFrame()
	Mocks.SetNow(100)
	ct.Show("enter")
	assert_not_nil(f:GetScript("OnUpdate"), "a timed line counts down")
	Mocks.SetNow(102.5)
	f:GetScript("OnUpdate")(f, 0.5)
	assert_false(f:IsShown(), "it hides once the duration elapses")
	assert_nil(f:GetScript("OnUpdate"))
	assert_true(style(ct, { duration = 0, distance = 0 }))
	ct.Show("enter")
	assert_nil(f:GetScript("OnUpdate"), "a sticky line with no motion has no updater")
	assert_true(f:IsShown())
	ct.Show("leave")
	assert_eq(f.label:GetText(), "- combat")
	assert_true(f:IsShown())
end)

T.register("combat text: scroll motion progresses and a sticky line settles with no permanent updater", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	assert_true(style(ct, { duration = 0, fade = 0, distance = 18, motion = 1, direction = "up" }))
	local f = ct.EnsureFrame()
	Mocks.SetNow(100)
	ct.Show("enter")
	assert_not_nil(f:GetScript("OnUpdate"), "the scroll keeps an updater while it runs")
	local _, _, _, _, start = f:GetPoint(1)
	assert_eq(start, 0, "the scroll restarts from the saved base")
	Mocks.SetNow(100.5)
	f:GetScript("OnUpdate")(f, 0.5)
	local _, _, _, _, half = f:GetPoint(1)
	assert_eq(half, 9, "smoothstep halfway is half the distance")
	Mocks.SetNow(101)
	f:GetScript("OnUpdate")(f, 0.5)
	local _, _, _, _, done = f:GetPoint(1)
	assert_eq(done, 18, "the line settles at the final offset")
	assert_nil(f:GetScript("OnUpdate"), "no permanent updater after the scroll settles")
	assert_true(f:IsShown(), "a sticky line stays visible")
	-- A new transition restarts from the saved base, not the settled offset.
	Mocks.SetNow(105)
	ct.Show("leave")
	local _, _, _, _, restart = f:GetPoint(1)
	assert_eq(restart, 0, "the next transition restarts from the saved base")
	assert_not_nil(f:GetScript("OnUpdate"))
	Mocks.SetNow(106)
	f:GetScript("OnUpdate")(f, 1)
	local _, _, _, _, settled = f:GetPoint(1)
	assert_eq(settled, 18)
	assert_nil(f:GetScript("OnUpdate"))
end)

T.register("combat text: direction down and none are honoured", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	assert_true(style(ct, { duration = 0, fade = 0, distance = 25, motion = 1, direction = "down" }))
	local f = ct.EnsureFrame()
	Mocks.SetNow(200)
	ct.Show("enter")
	Mocks.SetNow(201)
	f:GetScript("OnUpdate")(f, 1)
	local _, _, _, _, down = f:GetPoint(1)
	assert_eq(down, -25, "down scrolls away from the top")
	assert_nil(f:GetScript("OnUpdate"))
	assert_true(style(ct, { direction = "none", duration = 0 }))
	Mocks.SetNow(210)
	ct.Show("enter")
	assert_nil(f:GetScript("OnUpdate"), "direction none has no scroll updater when duration is 0")
	local _, _, _, _, still = f:GetPoint(1)
	assert_eq(still, 0, "direction none keeps the saved base")
end)

T.register("combat text: unlocking freezes the scroll at the saved base before dragging", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	assert_true(style(ct, { x = 120, y = -40, duration = 0, fade = 0, distance = 18, motion = 1 }))
	local f = ct.EnsureFrame()
	Mocks.SetNow(300)
	ct.Show("enter")
	Mocks.SetNow(300.5)
	f:GetScript("OnUpdate")(f, 0.5)
	local _, _, _, _, midY = f:GetPoint(1)
	assert_eq(midY, -31, "mid-scroll the frame is offset from the saved base")
	assert_eq(e.ns.db.combatText.y, -40, "the saved base is untouched while scrolling")
	ct.SetUnlocked(true)
	local _, _, _, _, frozenY = f:GetPoint(1)
	assert_eq(frozenY, -40, "unlocking returns to the saved base")
	assert_eq(f.animY, 0, "the animated offset is reset for dragging")
	assert_nil(f:GetScript("OnUpdate"))
	f:GetScript("OnDragStop")(f)
	assert_eq(e.ns.db.combatText.x, 0)
	assert_eq(e.ns.db.combatText.y, 0, "drag stop saves the real centre, not a motion offset")
end)

T.register("combat text: style applies font outline colour opacity background and is validated atomically", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	assert_true(style(ct, { fontSize = 30, opacity = 0.5, outline = true, color = { 0.2, 0.4, 0.6 }, background = { 0.1, 0.2, 0.3, 0.7 } }))
	local f = ct.EnsureFrame()
	ct.Show("enter")
	local _, size, flags = f.label:GetFont()
	assert_eq(size, 30)
	assert_eq(flags, "OUTLINE")
	assert_eq(f:GetAlpha(), 0.5)
	local r = f.label:GetTextColor()
	assert_eq(r, 0.2)
	assert_eq(f._backdropColor[4], 0.7)
	assert_false(style(ct, { fontSize = 200 }), "out-of-range font is refused")
	assert_eq(ct.Style().fontSize, 30, "refused input leaves every stored value untouched")
	assert_true(style(ct, { fontSize = 12, outline = false }))
	local _, size2, flags2 = f.label:GetFont()
	assert_eq(size2, 12)
	assert_eq(flags2, "")
end)

T.register("combat text: legacy color-only SetStyle still works and sets both new colours", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	assert_true(style(ct, { color = { 0.2, 0.4, 0.6 }, distance = 0 }))
	local s = ct.Style()
	assert_eq(s.enterColor[1], 0.2, "legacy colour feeds enter")
	assert_eq(s.enterColor[3], 0.6)
	assert_eq(s.leaveColor[1], 0.2, "legacy colour feeds leave")
	assert_eq(s.leaveColor[3], 0.6)
	assert_eq(e.ns.db.combatText.color[1], 0.2, "legacy field is still stored")
end)

T.register("combat text: colour and motion validation is atomic", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	assert_true(style(ct, { enterColor = { 0.1, 0.2, 0.3 }, leaveColor = { 0.4, 0.5, 0.6 }, distance = 30, motion = 2, direction = "down" }))
	assert_false(style(ct, { enterColor = { 2, 0, 0 } }), "enter RGB above 1 refused")
	assert_false(style(ct, { leaveColor = { 0, "x", 0 } }), "non-numeric leave RGB refused")
	assert_false(style(ct, { direction = "sideways" }), "unknown direction refused")
	assert_false(style(ct, { distance = 101 }), "distance above 100 refused")
	assert_false(style(ct, { distance = -1 }), "negative distance refused")
	assert_false(style(ct, { motion = 0.05 }), "motion below 0.1 refused")
	assert_false(style(ct, { motion = 11 }), "motion above 10 refused")
	local s = ct.Style()
	assert_eq(s.enterColor[1], 0.1, "a refused style leaves the colours untouched")
	assert_eq(s.leaveColor[3], 0.6)
	assert_eq(s.distance, 30)
	assert_eq(s.motion, 2)
	assert_eq(s.direction, "down")
	-- Omitting the new fields preserves the saved values.
	assert_true(ct.SetStyle({ fontSize = 20, opacity = 1, duration = 2, fade = 0, x = 0, y = 0, background = { 0, 0, 0, 0 } }))
	local s2 = ct.Style()
	assert_eq(s2.enterColor[1], 0.1)
	assert_eq(s2.distance, 30)
	assert_eq(s2.motion, 2)
	assert_eq(s2.direction, "down")
end)

T.register("combat text: legacy colour migrates into both new colours and the old default does not", function()
	local ns = presetEnv({ combatText = { color = { 0.1, 0.2, 0.3 } } })
	local s = ns.combatText.Style()
	assert_eq(s.enterColor[1], 0.1, "a custom legacy colour is preserved for enter")
	assert_eq(s.enterColor[3], 0.3)
	assert_eq(s.leaveColor[1], 0.1, "a custom legacy colour is preserved for leave")
	assert_eq(s.leaveColor[3], 0.3)
	assert_eq(ns.db.schema, 2, "the migration marker is written")

	local ns2 = presetEnv({ combatText = { color = { 1.0, 0.9, 0.3 } } })
	local s2 = ns2.combatText.Style()
	local d = ns2.DEFAULTS.combatText
	assert_eq(s2.enterColor[1], d.enterColor[1], "the old default gets the new enter colour")
	assert_eq(s2.leaveColor[3], d.leaveColor[3], "the old default gets the new leave colour")

	local ns3 = presetEnv({ combatText = { color = { Mocks.MakeSecret(), 0.2, 0.3 } } })
	local s3 = ns3.combatText.Style()
	assert_eq(s3.enterColor[1], d.enterColor[1], "a partially secret legacy colour is not migrated")
	assert_eq(s3.enterColor[2], d.enterColor[2], "the whole corrupt legacy colour falls back to the defaults")
end)

T.register("combat text: a fresh install gets distinct enter and leave defaults", function()
	local e = Mocks.NewEnv()
	local s = e.ns.combatText.Style()
	assert_true(s.enterColor[1] ~= s.leaveColor[1] or s.enterColor[2] ~= s.leaveColor[2] or s.enterColor[3] ~= s.leaveColor[3],
		"enter and leave colours must be independent defaults")
	assert_eq(s.direction, "up")
	assert_eq(s.distance, 18)
	assert_eq(s.motion, 1)
end)

T.register("combat text: custom labels are used and validated", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	assert_true(style(ct, { enterText = "COMBAT!", leaveText = "safe" }))
	local f = ct.EnsureFrame()
	ct.Show("enter"); assert_eq(f.label:GetText(), "COMBAT!")
	ct.Show("leave"); assert_eq(f.label:GetText(), "safe")
	assert_false(style(ct, { enterText = "" }), "empty label refused")
	assert_false(style(ct, { enterText = "bad|text" }), "format codes refused")
	assert_false(style(ct, { leaveText = string.rep("x", 41) }), "too-long label refused")
	assert_eq(e.ns.db.combatText.enterText, "COMBAT!", "refused labels do not overwrite the saved ones")
end)

T.register("combat text: disabling hides it and suppresses transitions", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	local f = ct.EnsureFrame()
	ct.Show("enter"); assert_true(f:IsShown())
	e.ns.HandleCommand("combattext off")
	assert_false(f:IsShown())
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_ENABLED")
	assert_false(f:IsShown(), "a disabled line never appears")
	e.ns.HandleCommand("combattext on")
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_DISABLED")
	assert_true(f:IsShown())
end)

T.register("combat text: unlock enables dragging and locking restores click-through", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	ct.SetUnlocked(true)
	local f = ct.EnsureFrame()
	assert_true(f._mouseEnabled, "unlocked frame accepts the mouse")
	assert_true(f:IsShown())
	assert_true(type(f:GetScript("OnDragStart")) == "function")
	f:GetScript("OnDragStart")(f)
	assert_true(f._moving)
	f:GetScript("OnDragStop")(f)
	assert_eq(e.ns.db.combatText.x, 0)
	assert_eq(e.ns.db.combatText.y, 0)
	ct.SetUnlocked(false)
	assert_false(f._mouseEnabled, "locked frame is click-through")
	assert_false(f:IsShown())
	assert_nil(f:GetScript("OnDragStart"))
end)

T.register("combat text: saved position applies and no idle updater exists", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	assert_true(style(ct, { x = 120, y = -40, duration = 0, distance = 0 }))
	local f = ct.EnsureFrame()
	local point, _, relPoint, ox, oy = f:GetPoint(1)
	assert_eq(point, "CENTER")
	assert_eq(relPoint, "CENTER")
	assert_eq(ox, 120)
	assert_eq(oy, -40)
	assert_nil(f:GetScript("OnUpdate"))
	ct.Show("enter")
	assert_nil(f:GetScript("OnUpdate"), "sticky line with no motion has no updater")
end)

T.register("combat text: preview shows even when disabled and uses the saved style", function()
	local e = Mocks.NewEnv()
	e.ns.db.combatText.enabled = false
	local ct = e.ns.combatText
	local f = ct.EnsureFrame()
	ct.Preview("leave")
	assert_true(f:IsShown())
	assert_eq(f.label:GetText(), "- combat")
end)

T.register("combat text: previews use the enter and leave colours", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	assert_true(style(ct, { enterColor = { 0.1, 0.2, 0.3 }, leaveColor = { 0.7, 0.8, 0.9 }, distance = 0 }))
	local f = ct.EnsureFrame()
	ct.Preview("enter")
	local r, g, b = f.label:GetTextColor()
	assert_eq(r, 0.1); assert_eq(g, 0.2); assert_eq(b, 0.3)
	ct.Preview("leave")
	local r2, g2, b2 = f.label:GetTextColor()
	assert_eq(r2, 0.7); assert_eq(g2, 0.8); assert_eq(b2, 0.9)
end)

T.register("combat text: options tab switches cleanly and edits apply without creating the display", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	assert_nil(e.ns.combatText.window, "opening options must not create the display")
	assert_false(f.combatPage:IsShown())
	click(f.controls.combatTab)
	assert_eq(f.selectedTab, "combat")
	assert_true(f.combatPage:IsShown())
	assert_false(f.notesPage:IsShown())
	assert_false(f.settingsPage:IsShown())
	assert_false(f.spellsPage:IsShown())
	local c = f.controls
	c.combatEnter:SetText("FIGHT"); c.combatLeave:SetText("calm")
	c.combatFont:SetText("26"); c.combatOpacity:SetText("0.8")
	c.combatDuration:SetText("3"); c.combatFade:SetText("0")
	c.combatEnterR:SetText("1"); c.combatEnterG:SetText("0.5"); c.combatEnterB:SetText("0")
	c.combatLeaveR:SetText("0.2"); c.combatLeaveG:SetText("0.4"); c.combatLeaveB:SetText("0.6")
	c.combatBgR:SetText("0"); c.combatBgG:SetText("0"); c.combatBgB:SetText("0"); c.combatBgA:SetText("0.4")
	c.combatDistance:SetText("24"); c.combatMotion:SetText("1.5")
	c.combatX:SetText("50"); c.combatY:SetText("-25")
	click(c.combatApply)
	assert_eq(e.ns.db.combatText.enterText, "FIGHT")
	assert_eq(e.ns.db.combatText.fontSize, 26)
	assert_eq(e.ns.db.combatText.enterColor[1], 1)
	assert_eq(e.ns.db.combatText.enterColor[2], 0.5)
	assert_eq(e.ns.db.combatText.leaveColor[3], 0.6)
	assert_eq(e.ns.db.combatText.background[4], 0.4)
	assert_eq(e.ns.db.combatText.distance, 24)
	assert_eq(e.ns.db.combatText.motion, 1.5)
	assert_eq(e.ns.db.combatText.x, 50)
	assert_eq(e.ns.db.combatText.y, -25)
	click(c.combatPreviewEnter)
	local win = e.ns.combatText.window
	assert_eq(win.label:GetText(), "FIGHT")
	click(c.combatPreviewLeave)
	assert_eq(win.label:GetText(), "calm")
	click(c.combatResetStyle)
	assert_eq(e.ns.db.combatText.fontSize, e.ns.DEFAULTS.combatText.fontSize)
	assert_eq(e.ns.db.combatText.x, 0)
	c.combatFont:SetText("999")
	click(c.combatApply)
	assert_eq(e.ns.db.combatText.fontSize, e.ns.DEFAULTS.combatText.fontSize, "invalid apply changes nothing")
	assert_nil(e.ns.session.fake)
end)

T.register("combat text: direction button cycles and apply saves the chosen direction", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.combatTab)
	local dir = f.controls.combatDir
	assert_eq(dir.direction, "Up")
	click(dir); assert_eq(dir.direction, "Down"); assert_eq(dir:GetText(), "Direction: Down")
	click(dir); assert_eq(dir.direction, "None"); assert_eq(dir:GetText(), "Direction: None")
	click(dir); assert_eq(dir.direction, "Up")
	click(dir) -- Down
	click(f.controls.combatApply)
	assert_eq(e.ns.db.combatText.direction, "down")
end)

T.register("combat text: reset position preserves the new style and reset style resets all of it", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.combatTab)
	local c = f.controls
	c.combatEnterR:SetText("0.11"); c.combatEnterG:SetText("0.22"); c.combatEnterB:SetText("0.33")
	c.combatLeaveR:SetText("0.44"); c.combatLeaveG:SetText("0.55"); c.combatLeaveB:SetText("0.66")
	c.combatDistance:SetText("33"); c.combatMotion:SetText("3")
	c.combatX:SetText("120"); c.combatY:SetText("-40")
	click(c.combatDir) -- Down
	click(c.combatApply)
	click(c.combatResetPos)
	assert_eq(e.ns.db.combatText.x, 0)
	assert_eq(e.ns.db.combatText.y, 0)
	assert_eq(e.ns.db.combatText.enterColor[1], 0.11, "reset position keeps the enter colour")
	assert_eq(e.ns.db.combatText.leaveColor[3], 0.66, "reset position keeps the leave colour")
	assert_eq(e.ns.db.combatText.distance, 33, "reset position keeps the distance")
	assert_eq(e.ns.db.combatText.motion, 3, "reset position keeps the motion time")
	assert_eq(e.ns.db.combatText.direction, "down", "reset position keeps the direction")
	click(c.combatResetStyle)
	local d = e.ns.DEFAULTS.combatText
	assert_eq(e.ns.db.combatText.direction, d.direction)
	assert_eq(e.ns.db.combatText.distance, d.distance)
	assert_eq(e.ns.db.combatText.motion, d.motion)
	assert_eq(e.ns.db.combatText.enterColor[1], d.enterColor[1])
	assert_eq(e.ns.db.combatText.leaveColor[3], d.leaveColor[3])
	assert_eq(e.ns.db.combatText.x, 0)
	assert_eq(e.ns.db.combatText.y, 0)
end)

T.register("combat text: outline and unlock checkboxes reflect state and apply immediately", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.combatTab)
	local outline = f.controls.combatOutline
	assert_true(outline:GetChecked(), "default outline is on")
	outline:SetChecked(false); click(outline)
	assert_false(e.ns.db.combatText.outline)
	local unlock = f.controls.combatUnlock
	assert_false(unlock:GetChecked())
	unlock:SetChecked(true); click(unlock)
	assert_true(e.ns.combatText.unlocked)
	assert_true(e.ns.combatText.window:IsShown())
	unlock:SetChecked(false); click(unlock)
	assert_false(e.ns.combatText.unlocked)
	assert_false(e.ns.combatText.window:IsShown())
end)

T.register("combat text: an unlocked line is click-through during combat and draggable after", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	ct.SetUnlocked(true)
	local f = ct.EnsureFrame()
	assert_true(f._mouseEnabled)
	Mocks.inCombat = true
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_DISABLED")
	assert_true(f:IsShown())
	assert_false(f._mouseEnabled, "combat forces click-through even while unlocked")
	Mocks.inCombat = false
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_ENABLED")
	assert_true(f._mouseEnabled, "drag is restored after combat while still unlocked")
end)

T.register("combat text: reset style re-checks the outline box", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.combatTab)
	local outline = f.controls.combatOutline
	outline:SetChecked(false); click(outline)
	assert_false(e.ns.db.combatText.outline)
	click(f.controls.combatResetStyle)
	assert_true(e.ns.db.combatText.outline)
	assert_true(outline:GetChecked(), "reset style must re-check the outline box")
end)

T.register("combat text: corrupted nested colours cannot raise or retain secrets", function()
	local e = Mocks.NewEnv()
	optIn(e)
	local ct = e.ns.combatText
	e.ns.db.combatText.enterColor = { Mocks.MakeSecret(), 0.5, 0.5 }
	e.ns.db.combatText.leaveColor = { 0.1, Mocks.MakeSecret(), 0.2 }
	e.ns.db.combatText.color = { Mocks.MakeSecret(), 0.5, 0.5 }
	e.ns.db.combatText.background = { 0.1, Mocks.MakeSecret(), 0.2, 0.3 }
	local s = ct.Style()
	assert_eq(s.enterColor[1], 0.35, "a secret enter component falls back to its default")
	assert_eq(s.enterColor[2], 0.5)
	assert_eq(s.leaveColor[2], 0.74, "a secret leave component falls back to its default")
	assert_eq(s.color[1], 1, "a secret legacy component falls back")
	assert_eq(s.background[2], 0)
	assert_eq(s.background[4], 0.3)
	local f = ct.EnsureFrame()
	ct.Show("enter")
	assert_true(f:IsShown())
end)

T.register("combat text: combat page controls fit and do not overlap", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.combatTab)
	local page = f.combatPage
	local pageRect = Mocks.FrameRect(page)
	local keys = { "combatEnabled", "combatApply", "combatResetStyle", "combatPreviewEnter", "combatPreviewLeave", "combatResetPos", "combatDir" }
	local rects = {}
	for _, key in ipairs(keys) do
		local r = Mocks.FrameRect(f.controls[key])
		assert_true(r.left >= pageRect.left and r.right <= pageRect.right, key .. " stays inside the page horizontally")
		assert_true(r.top <= pageRect.top and r.bottom >= pageRect.bottom, key .. " stays inside the page vertically")
		rects[key] = r
	end
	for i = 1, #keys do
		for j = i + 1, #keys do
			assert_false(Mocks.RectsOverlap(rects[keys[i]], rects[keys[j]]), keys[i] .. " must not overlap " .. keys[j])
		end
	end
	for _, text in ipairs({ "Enable combat text", "Direction (up / down / none)", "Distance px (0-100)", "Motion seconds (0.1-10)",
		"Position offset X / Y from screen centre", "Motion restarts" }) do
		local l = Mocks.FindFontString(page, text)
		assert_not_nil(l, "label missing: " .. text)
		local lr = Mocks.RegionRect(l)
		for _, key in ipairs(keys) do
			assert_false(Mocks.RectsOverlap(lr, rects[key]), text .. " must not overlap " .. key)
		end
	end
	for _, key in ipairs({ "combatDistance", "combatMotion", "combatX", "combatY", "combatEnter", "combatLeave" }) do
		local r = Mocks.FrameRect(f.controls[key])
		assert_true(r.left >= pageRect.left and r.right <= pageRect.right, key .. " stays inside the page")
		assert_false(Mocks.RectsOverlap(rects.combatEnabled, r), "combatEnabled must not overlap " .. key)
	end
end)

T.register("combat text: enable checkbox toggles state, hides visible line immediately and suppresses transitions", function()
	local e = Mocks.NewEnv()
	local ct = e.ns.combatText
	local f = e.ns.OpenOptions("combat")
	local cb = f.controls.combatEnabled
	assert_not_nil(cb, "combatEnabled checkbox exists")
	assert_false(cb:GetChecked(), "disabled by default until the user opts in")

	-- Opt in, show a line, then verify turning it back off hides it immediately.
	local textFrame = ct.EnsureFrame()
	cb:SetChecked(true)
	cb:GetScript("OnClick")(cb)
	ct.Show("enter")
	assert_true(textFrame:IsShown(), "text is visible before disabling")

	-- Uncheck checkbox and trigger OnClick (disables visible text immediately)
	cb:SetChecked(false)
	cb:GetScript("OnClick")(cb)
	assert_false(e.ns.db.combatText.enabled, "db updated to false")
	assert_false(cb:GetChecked(), "checkbox reflects false")
	assert_false(textFrame:IsShown(), "disables visible text immediately")

	-- Suppresses enter/leave transitions
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_DISABLED")
	assert_false(textFrame:IsShown(), "enter transition suppressed when disabled")
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_ENABLED")
	assert_false(textFrame:IsShown(), "leave transition suppressed when disabled")

	-- Keep explicit previews usable when disabled, preserving current behavior
	click(f.controls.combatPreviewEnter)
	assert_true(textFrame:IsShown(), "preview + works while disabled")
	assert_eq(textFrame.label:GetText(), "+ combat")
	click(f.controls.combatPreviewLeave)
	assert_true(textFrame:IsShown(), "preview - works while disabled")
	assert_eq(textFrame.label:GetText(), "- combat")

	-- Re-enable via checkbox
	cb:SetChecked(true)
	cb:GetScript("OnClick")(cb)
	assert_true(e.ns.db.combatText.enabled, "db updated to true")
	assert_true(cb:GetChecked(), "checkbox reflects true")

	-- Transitions work again
	ct.eventFrame:GetScript("OnEvent")(ct.eventFrame, "PLAYER_REGEN_DISABLED")
	assert_true(textFrame:IsShown(), "enter transition works when re-enabled")
end)

T.register("combat text: checkbox reflects slash-command changes and persists across reloads", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("combat")
	local cb = f.controls.combatEnabled
	assert_false(cb:GetChecked(), "combat text is opt-in")

	-- Slash command disables combat text; options checkbox reflects it
	e.ns.HandleCommand("combattext off")
	assert_false(e.ns.db.combatText.enabled)
	assert_false(cb:GetChecked(), "checkbox reflects slash command off")

	-- Slash command enables combat text; options checkbox reflects it
	e.ns.HandleCommand("combattext on")
	assert_true(e.ns.db.combatText.enabled)
	assert_true(cb:GetChecked(), "checkbox reflects slash command on")

	-- Persists across reloads
	local ns2 = presetEnv({ combatText = { enabled = false } })
	assert_false(ns2.db.combatText.enabled, "loaded disabled from DB")
	local f2 = ns2.OpenOptions("combat")
	assert_false(f2.controls.combatEnabled:GetChecked(), "persisted disabled state reaches checkbox")
	local textFrame2 = ns2.combatText.EnsureFrame()
	ns2.combatText.eventFrame:GetScript("OnEvent")(ns2.combatText.eventFrame, "PLAYER_REGEN_DISABLED")
	assert_false(textFrame2:IsShown(), "transitions remain suppressed after reload")
	-- Previews still work
	ns2.combatText.Preview("enter")
	assert_true(textFrame2:IsShown(), "preview works after reload even when disabled")
end)

T.register("combat text: status and test commands report and preview", function()
	local e = Mocks.NewEnv()
	e.ns.HandleCommand("combattext status")
	e.ns.HandleCommand("combattext test leave")
	local f = e.ns.combatText.EnsureFrame()
	assert_eq(f.label:GetText(), "- combat")
	assert_true(#e.mocks.chat > 0)
end)
