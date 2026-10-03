-- tests/spec_debugwindow.lua
-- Copyable debug snapshot window: lazy creation, one reusable frame, forced
-- internals, selection/refresh/close behaviour, and graceful degradation.

local unpack = unpack or table.unpack

local WINDOW_NAME = "EllesmereUI_HoTPredictionDebugWindow"

local function newEnv(opts)
	return Mocks.NewEnv(opts)
end

-- Drive the addon's real periodic overlay timer callback (not a manual state
-- setup), so we can prove a live tick never touches the debug EditBox.
local function runTimer()
	for i = #Mocks.tickers, 1, -1 do
		if Mocks.tickers[i].interval == 0.15 then
			Mocks.tickers[i].fn()
			return true
		end
	end
	return false
end

local function countNamed(name)
	local n = 0
	for i = 1, #Mocks.frames do
		if Mocks.frames[i]._name == name then n = n + 1 end
	end
	return n
end

-- Emulate the client's Escape handling of UISpecialFrames (hide each shown
-- registered frame). This exercises the frame's OnHide cleanup.
local function pressEscape()
	for i = #UISpecialFrames, 1, -1 do
		local fr = _G[UISpecialFrames[i]]
		if fr and fr.IsShown and fr:IsShown() then fr:Hide() end
	end
end

------------------------------------------------------------------------------

T.register("debugwindow: created lazily, one frame reused, escape registered once", function()
	local env = newEnv()
	assert_nil(env.ns.debugWindow, "no window before first open")
	assert_nil(_G[WINDOW_NAME], "no named global before first open")

	local f = env.ns.OpenDebugWindow()
	assert_not_nil(f, "window created on demand")
	assert_eq(_G[WINDOW_NAME], f, "named frame registered globally")
	assert_eq(countNamed(WINDOW_NAME), 1, "exactly one named frame")
	assert_true(f:IsShown(), "open shows the window")

	local f2 = env.ns.OpenDebugWindow()
	assert_eq(f2, f, "repeated open reuses the same frame")
	assert_eq(countNamed(WINDOW_NAME), 1, "never creates a second frame")

	local hits = 0
	for i = 1, #UISpecialFrames do
		if UISpecialFrames[i] == WINDOW_NAME then hits = hits + 1 end
	end
	assert_eq(hits, 1, "registered with UISpecialFrames exactly once")
end)

T.register("debugwindow: open/refresh is quiet (no chat spam)", function()
	local env = newEnv()
	local before = #Mocks.chat
	env.ns.OpenDebugWindow()
	env.ns.RefreshDebugWindow()
	env.ns.RefreshDebugWindow()
	assert_eq(#Mocks.chat, before, "opening/refreshing never prints chat")
end)

T.register("debugwindow: report forces rich internals while debug stays off", function()
	local env = newEnv()
	local ns = env.ns
	assert_false(ns.db.debug, "debug is off to begin with")
	local before = #Mocks.chat

	local off = ns.BuildStatusReport()
	assert_true(off:match("enabled=") ~= nil, "concise status present")
	assert_true(off:match("policy=") == nil, "internals omitted while debug off")

	local on = ns.BuildStatusReport(true)
	assert_true(on:match("policy=") ~= nil, "internals forced when requested")
	assert_true(on:match("lua=") ~= nil, "lua internals present")
	assert_true(on:match("manual calibration") ~= nil, "calibration internals present")
	assert_true(on:match("cleu function=") ~= nil, "CLEU capability present")
	assert_true(on:match("build=") ~= nil, "client build present")
	assert_true(on:match("tracked active HoTs=") ~= nil, "tracked HoTs line present")

	assert_eq(#Mocks.chat, before, "building a report never prints chat")
	assert_false(ns.db.debug, "debug setting was not changed by a forced report")

	-- The snapshot the window shows combines both, driven through the window.
	ns.OpenDebugWindow()
	local text = ns.debugWindow.editBox:GetText()
	assert_true(text:match("teststatus unit=") ~= nil, "compact teststatus in snapshot")
	assert_true(text:match("forced internals") ~= nil, "forced status section in snapshot")
	assert_true(text:match("policy=") ~= nil, "snapshot has rich internals")
	assert_eq(#Mocks.chat, before, "opening the window never prints chat")
	assert_false(ns.db.debug, "opening the window never changes the debug setting")
end)

T.register("debugwindow: builders are plain text without colour codes", function()
	local env = newEnv()
	local s = env.ns.StripFormatting("a|cff00ff00b|rc|Hitem:1|hx|h|Ttex|t")
	assert_true(s:match("|c") == nil and s:match("|r") == nil and s:match("|H") == nil and s:match("|T") == nil, "no formatting codes")
	assert_eq(s, "abcx", "visible content preserved")
	local line = env.ns.BuildTestStatusReport()
	assert_eq(select(2, line:gsub("\n", "\n")), 0, "teststatus builder is one line")
end)

T.register("debugwindow: refresh captures a changed fake amount", function()
	local env = newEnv()
	local ns = env.ns
	ns.OpenDebugWindow()
	local t1 = ns.RefreshDebugWindow()
	assert_true(t1:match("fakeRequested=1234") == nil, "no fake in first snapshot")

	ns.HandleCommand("test 1234")
	local t2 = ns.RefreshDebugWindow()
	assert_true(t2 ~= t1, "a new snapshot differs from the previous one")
	assert_true(t2:match("fakeRequested=1234") ~= nil, "fake amount visible in fresh snapshot")
	assert_eq(ns.debugWindow.editBox:GetText(), t2, "edit box holds the fresh report")
end)

T.register("debugwindow: Refresh drops old selection/focus and resets scroll", function()
	local env = newEnv()
	local ns = env.ns
	ns.OpenDebugWindow()
	local eb = ns.debugWindow.editBox
	local sf = ns.debugWindow.scrollFrame
	ns.SelectAllDebugWindow()
	assert_true(eb:HasFocus(), "select all focuses")
	sf:SetVerticalScroll(50)
	ns.RefreshDebugWindow()
	assert_false(eb:HasFocus(), "refresh clears focus")
	assert_eq(eb:GetSelectedText(), "", "refresh clears selection")
	assert_eq(eb:GetCursorPosition(), 0, "cursor reset to 0")
	assert_eq(sf:GetVerticalScroll(), 0, "scroll reset to top")
end)

T.register("debugwindow: Select All focuses and selects the whole report", function()
	local env = newEnv()
	local ns = env.ns
	ns.OpenDebugWindow()
	local eb = ns.debugWindow.editBox
	assert_false(eb:HasFocus(), "opening does not steal focus")
	ns.SelectAllDebugWindow()
	assert_true(eb:HasFocus(), "explicit select all focuses")
	local text = eb:GetText()
	assert_true(#text > 0, "report is non-empty")
	assert_eq(#eb:GetSelectedText(), #text, "selection covers the whole report")
end)

T.register("debugwindow: manual editing cannot mutate addon data", function()
	local env = newEnv()
	local ns = env.ns
	ns.HandleCommand("test 500")
	ns.OpenDebugWindow()
	local eb = ns.debugWindow.editBox
	local debugBefore, enabledBefore, alphaBefore = ns.db.debug, ns.db.enabled, ns.db.alpha
	local fakeBefore = ns.session.fake.value

	eb:SetText("tampered by the user")
	eb:Insert("!")
	assert_eq(ns.db.debug, debugBefore, "editing never changes debug")
	assert_eq(ns.db.enabled, enabledBefore, "editing never changes enabled")
	assert_eq(ns.db.alpha, alphaBefore, "editing never changes alpha")
	assert_eq(ns.session.fake.value, fakeBefore, "editing never changes the fake test")
end)

T.register("debugwindow: Close hides, clears focus and reuses the frame on reopen", function()
	local env = newEnv()
	local ns = env.ns
	local f = ns.OpenDebugWindow()
	local eb = ns.debugWindow.editBox
	ns.SelectAllDebugWindow()
	assert_true(eb:HasFocus(), "focused before close")

	assert_true(ns.CloseDebugWindow(), "close reports success")
	assert_false(f:IsShown(), "close hides the window")
	assert_false(eb:HasFocus(), "close clears focus via OnHide")

	assert_eq(ns.OpenDebugWindow(), f, "reopen reuses the hidden frame")
	assert_true(f:IsShown(), "reopen shows the same frame")
end)

T.register("debugwindow: Escape hides it and clears focus", function()
	local env = newEnv()
	local ns = env.ns
	local f = ns.OpenDebugWindow()
	local eb = ns.debugWindow.editBox
	ns.SelectAllDebugWindow()
	-- Escape pressed inside the EditBox drops focus first...
	eb:GetScript("OnEscapePressed")(eb)
	assert_false(eb:HasFocus(), "editbox escape clears focus")
	assert_true(f:IsShown(), "the box alone does not hide the window")
	-- ...then the client hides frames registered in UISpecialFrames.
	pressEscape()
	assert_false(f:IsShown(), "escape hides the window")
	assert_false(eb:HasFocus(), "hidden window leaves no focus")
end)

T.register("debugwindow: scroll child, multiline and newline report content", function()
	local env = newEnv()
	local ns = env.ns
	ns.OpenDebugWindow()
	local f = ns.debugWindow
	assert_eq(f.scrollFrame:GetScrollChild(), f.editBox, "edit box bound as scroll child")
	assert_true(f.editBox:IsMultiLine(), "edit box is multiline")
	assert_false(f.editBox._autoFocus, "no autofocus")
	local text = f.editBox:GetText()
	assert_true(text:match("\n") ~= nil, "report is newline delimited")
	assert_true(#text > 200, "report is long enough to need scrolling")
end)

T.register("debugwindow: a live overlay tick never touches the copy selection", function()
	local env = newEnv()
	local ns = env.ns
	ns.OpenDebugWindow()
	ns.SelectAllDebugWindow()
	local eb = ns.debugWindow.editBox
	local textBefore = eb:GetText()
	local selBefore = eb:GetSelectedText()
	assert_true(#selBefore > 0, "selection armed")
	assert_true(runTimer(), "overlay tick actually ran")
	assert_eq(eb:GetText(), textBefore, "tick did not rewrite the report text")
	assert_eq(eb:GetSelectedText(), selBefore, "tick did not change the selection")
end)

T.register("debugwindow: adds no ticker/event/OnUpdate and touches no native frame", function()
	local env = newEnv()
	local ns = env.ns
	local tickersBefore = #Mocks.tickers
	local hooksBefore = #Mocks.hooks
	local valueBefore = env.ab._predMy:GetValue()
	local texBefore = env.ab._predMy:GetStatusBarTexture():GetTexture()
	local moduleBefore = _G.EllesmereUI._ModuleNS.EllesmereUIUnitFrames

	ns.OpenDebugWindow()
	ns.RefreshDebugWindow()
	ns.SelectAllDebugWindow()
	local f = ns.debugWindow

	assert_eq(#Mocks.tickers, tickersBefore, "no new ticker")
	assert_eq(#Mocks.hooks, hooksBefore, "no new secure hook")
	assert_nil(next(f._events), "window registers no events")
	assert_nil(f:GetScript("OnUpdate"), "window has no OnUpdate")
	assert_eq(env.ab._predMy:GetValue(), valueBefore, "native value untouched")
	assert_eq(env.ab._predMy:GetStatusBarTexture():GetTexture(), texBefore, "native texture untouched")
	assert_eq(_G.EllesmereUI._ModuleNS.EllesmereUIUnitFrames, moduleBefore, "module table untouched")
end)

T.register("debugwindow: /window and /debug window open it; /debug on still toggles", function()
	local env = newEnv()
	local ns = env.ns
	ns.HandleCommand("window")
	assert_not_nil(ns.debugWindow, "slash window opened it")
	assert_true(ns.debugWindow:IsShown(), "slash window shows it")
	ns.CloseDebugWindow()
	ns.HandleCommand("debug window")
	assert_true(ns.debugWindow:IsShown(), "debug window alias shows it")
	ns.HandleCommand("debug on")
	assert_true(ns.db.debug, "existing /debug on still works")
	ns.HandleCommand("debug off")
	assert_false(ns.db.debug, "existing /debug off still works")
end)

T.register("debugwindow: missing Ellesmere/CLEU/secret range yields copyable text", function()
	local env = newEnv({ noCLEU = true })
	local ns = env.ns
	_G.EllesmereUI = nil
	env.ab._predMy:SetMinMaxValues(0, Mocks.MakeSecret())
	Mocks.health = Mocks.MakeSecret()
	Mocks.maxHealth = Mocks.MakeSecret()

	local ok, report = pcall(ns.BuildStatusReport, true)
	assert_true(ok, "status builder never raises")
	assert_true(report:match("cleu function=false") ~= nil, "honest CLEU absence")
	assert_true(report:match("overlay frame=") ~= nil, "overlay line present even without EUF")
	assert_true(report:match("attempt to use a secret value") == nil, "no raw secret error")

	local ok2, snap = pcall(ns.BuildSnapshotReport)
	assert_true(ok2 and type(snap) == "string" and #snap > 0, "snapshot still copyable")

	-- And through chat it must not raise either.
	assert_true(pcall(function() ns.EmitStatus() end), "EmitStatus safe with missing APIs")
end)

T.register("debugwindow: graceful failure when CreateFrame is unavailable", function()
	local env = newEnv()
	local ns = env.ns
	local saved = _G.CreateFrame
	_G.CreateFrame = nil
	local before = #Mocks.chat
	assert_nil(ns.OpenDebugWindow(), "no window without CreateFrame")
	assert_eq(#Mocks.chat, before + 1, "one clear failure line, not a stack trace")
	assert_true(Mocks.chat[#Mocks.chat]:match("debug window unavailable") ~= nil, "useful message")
	assert_true(type(ns.BuildSnapshotReport()) == "string", "report still builds without a window")
	_G.CreateFrame = saved
end)
