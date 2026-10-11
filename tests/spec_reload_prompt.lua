T.register("reload prompt: late /rl registration is wrapped and routes through native chat parsing", function()
	local e = Mocks.NewEnv()
	local originalCalls = 0
	local original = function() originalCalls = originalCalls + 1; return "popup" end
	SlashCmdList.RL = original -- Simulate EllesmereUI registering after DoHelper loaded.
	EllesmereUI = { IS_FOREVER = true }
	e.ns.reloadPromptFrame:GetScript("OnEvent")(e.ns.reloadPromptFrame, "ADDON_LOADED", "EllesmereUI")
	assert_true(SlashCmdList.RL ~= original, "late command registration receives the DoHelper wrapper")

	local box = { text = "/rl" }
	function box:SetText(text) self.text = text end
	function box:GetText() return self.text end
	local submitted
	ChatEdit_SendText = function(editBox) submitted = editBox:GetText(); return "native" end
	e.ns.db.skipRLConfirm = true
	assert_eq(SlashCmdList.RL("", box), "native")
	assert_eq(submitted, "/reload", "uses the client's native /reload command, not ReloadUI directly")
	assert_eq(originalCalls, 0, "the EUI confirmation handler is bypassed")

	e.ns.db.skipRLConfirm = false
	assert_eq(SlashCmdList.RL("", box), "popup", "opt-out preserves EllesmereUI's handler")
	assert_eq(originalCalls, 1)

	e.ns.db.skipRLConfirm = true
	InCombatLockdown = function() return true end
	assert_eq(SlashCmdList.RL("", box), "popup", "combat still uses the original warning")
	assert_eq(originalCalls, 2)
end)

T.register("reload prompt: registration retry works when DoHelper gameplay is disabled", function()
	local e = Mocks.NewEnv({ disabled = true })
	local originalCalls = 0
	SlashCmdList.RL = function() originalCalls = originalCalls + 1 end
	EllesmereUI = { IS_FOREVER = true }
	e.ns.reloadPromptFrame:GetScript("OnEvent")(e.ns.reloadPromptFrame, "ADDON_LOADED", "EllesmereUI")
	local submitted
	ChatFrame1EditBox = { SetText = function(_, text) submitted = text end }
	ChatEdit_SendText = function() end
	e.ns.db.skipRLConfirm = true
	SlashCmdList.RL()
	assert_eq(submitted, "/reload", "global edit box is used without the normal event dispatcher")
	assert_eq(originalCalls, 0)
end)
