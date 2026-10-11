-- Optional bypass for EllesmereUI's WoW Forever /rl confirmation popup.
-- Use Blizzard's own /reload slash handler so the client still performs its
-- secure reload path; calling ReloadUI() directly from addon code is blocked.
local _, ns = ...
local wrapper

local function install()
	if type(SlashCmdList) ~= "table" then return false end
	local original = SlashCmdList.RL
	if original == wrapper then return true end
	if type(original) ~= "function" then return false end

	wrapper = function(msg, editBox, ...)
		local db = ns.db
		local eui = _G.EllesmereUI
		if db and db.skipRLConfirm and eui and eui.IS_FOREVER == true then
			-- Match EllesmereUI's combat guard; its confirmation popup cannot issue
			-- the secure reload while combat lockdown is active.
			if type(InCombatLockdown) == "function" and InCombatLockdown() then
				return original(msg, editBox, ...)
			end
			-- /reload is a client command on Forever, not reliably exposed as
			-- SlashCmdList.RELOADUI. Re-submit it through Blizzard's chat parser so
			-- it follows the same trusted path as the user typing /reload.
			local commandBox = editBox or _G.ChatFrame1EditBox
			if commandBox and type(_G.ChatEdit_SendText) == "function"
				and type(commandBox.SetText) == "function" then
				commandBox:SetText("/reload")
				return _G.ChatEdit_SendText(commandBox, 0)
			end
			-- Some clients/addons expose the native slash callback directly. Use
			-- it only as a last resort; directly calling ReloadUI is not safe here.
			local nativeReload = SlashCmdList.RELOADUI
			if type(nativeReload) == "function" then return nativeReload() end
			if ns.print then ns.print("Could not run the native /reload command; chat input is unavailable.") end
			return
		end
		return original(msg, editBox, ...)
	end
	SlashCmdList.RL = wrapper
	return true
end

install()

-- DoHelper's normal event dispatcher intentionally stops when its gameplay
-- feature is disabled. Keep this tiny registration retry independent so /rl
-- still works when that feature is off and if EllesmereUI registers its command
-- after DoHelper's files load.
if type(_G.CreateFrame) == "function" then
	local frame = CreateFrame("Frame")
	ns.reloadPromptFrame = frame
	frame:RegisterEvent("ADDON_LOADED")
	frame:RegisterEvent("PLAYER_LOGIN")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(self, event)
		install()
		if event == "PLAYER_LOGIN" then self:UnregisterEvent("PLAYER_LOGIN") end
		if event == "PLAYER_ENTERING_WORLD" then self:UnregisterEvent("PLAYER_ENTERING_WORLD") end
	end)
end
