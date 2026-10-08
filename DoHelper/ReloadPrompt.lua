-- Optional bypass for EllesmereUI's WoW Forever /rl confirmation popup.
-- Use Blizzard's own /reload slash handler so the client still performs its
-- secure reload path; calling ReloadUI() directly from addon code is blocked.
local _, ns = ...
local installed = false

local function install()
	if type(SlashCmdList) ~= "table" then return false end
	if installed then return true end
	local original = SlashCmdList.RL
	if type(original) ~= "function" then return false end

	local wrapper = function(...)
		local db = ns.db
		local eui = _G.EllesmereUI
		if db and db.skipRLConfirm and eui and eui.IS_FOREVER == true then
			-- Match EllesmereUI's combat guard; its confirmation popup cannot issue
			-- the secure reload while combat lockdown is active.
			if type(InCombatLockdown) == "function" and InCombatLockdown() then
				return original(...)
			end
			local nativeReload = SlashCmdList.RELOADUI
			if type(nativeReload) == "function" then return nativeReload(...) end
		end
		return original(...)
	end
	SlashCmdList.RL = wrapper
	installed = true
	return true
end

-- EUI and its slash aliases load before DoHelper through the unit-frame
-- dependency. Retry at login as a guard for clients that register slash aliases
-- late; the wrapper reads the option dynamically, so toggling needs no reinstall.
install()
if ns.on then ns.on("PLAYER_LOGIN", install) end
