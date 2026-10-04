-- DoHelper / CritSounds.lua
-- Only positively readable player-sourced critical combat-log events qualify.
-- Reuse the existing CLEU subscription and its restricted-engine policy: this
-- module never registers forbidden events or guesses from casts/health changes.
-- The Sounds tab's explicit "Try crit detection" button is the ONLY place this
-- module can request the guarded subscription; enabling sounds or a reload never
-- registers anything by itself.
local _, ns = ...
local UI = ns.ui
local sounds = {}
ns.critSounds = sounds

local BAM_PATH = "Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3"

local events = {
	SWING_DAMAGE = { "damage", 18 },
	RANGE_DAMAGE = { "damage", 21 },
	SPELL_DAMAGE = { "damage", 21 },
	SPELL_PERIODIC_DAMAGE = { "damage", 21 },
	SPELL_HEAL = { "healing", 18 },
	SPELL_PERIODIC_HEAL = { "healing", 18 },
}

-- Session-only diagnostics. Nothing here is written to SavedVariables: a reload
-- starts clean, and no counter can pretend a registered event was delivered.
sounds.diagnostics = {
	attempts = 0,            -- explicit Try crit detection clicks
	delivered = 0,           -- CLEU events actually delivered this session
	playerCrits = 0,         -- readable player crits observed (before playback)
	lastAttemptAccepted = nil,
	lastAttemptAt = nil,
	lastPlaybackOk = nil,
	lastPlaybackReason = nil,
	lastPlaybackPreview = nil,
	lastPlaybackAt = nil,
}

function sounds.Config()
	return ns.db and ns.db.critSounds
end

function sounds.SetConfig(values)
	if type(values) ~= "table" then return false, "No settings supplied." end
	local path = values.path
	if ns.isSecret(path) or type(path) ~= "string" then return false, "Enter a local sound-file path." end
	path = path:gsub("/", "\\"):gsub("^%s+", ""):gsub("%s+$", "")
	if #path > 240 or path:find("..", 1, true) or path:find("[%c|]") then
		return false, "Invalid sound-file path."
	end
	if path ~= "" and (not path:lower():match("^interface\\addons\\")
		or not (path:lower():match("%.ogg$") or path:lower():match("%.mp3$"))) then
		return false, "Use Interface\\AddOns\\... with an .ogg or .mp3 file (not a URL)."
	end
	local cooldown = not ns.isSecret(values.cooldown) and ns.toNumber(tonumber(values.cooldown)) or nil
	if not ns.isFinite(cooldown) or cooldown > 30 then return false, "Cooldown must be 0-30 seconds." end
	if values.channel ~= "Master" and values.channel ~= "SFX" then return false, "Choose Master or SFX." end
	local d = sounds.Config()
	if not d then return false, "Settings unavailable." end
	d.enabled, d.damage, d.healing = values.enabled == true, values.damage == true, values.healing == true
	d.path, d.channel, d.cooldown = path, values.channel, cooldown
	sounds.lastPlayed = nil
	return true, "Sound settings saved."
end

local function recordPlayback(ok, reason, preview)
	sounds.diagnostics.lastPlaybackOk = ok and true or false
	sounds.diagnostics.lastPlaybackReason = reason
	sounds.diagnostics.lastPlaybackPreview = preview and true or false
	sounds.diagnostics.lastPlaybackAt = ns.now()
end

-- Manual preview ignores enable/filter/cooldown, but still reports playback
-- refusal honestly. No file is downloaded and missing files never fall back.
function sounds.Play(preview)
	local d = sounds.Config()
	if not d then return false, "Settings unavailable." end
	if not preview and (not d.enabled or not ns.db.enabled) then recordPlayback(false, "disabled", preview); return false end
	local now = ns.now()
	local cooldown = ns.toNumber(d.cooldown) or 0.5
	if not preview and sounds.lastPlayed and now - sounds.lastPlayed < cooldown then
		recordPlayback(false, "cooldown", preview)
		return false
	end
	local channel = d.channel == "SFX" and "SFX" or "Master"
	local ok, played
	if type(d.path) == "string" and d.path ~= "" then
		if type(PlaySoundFile) ~= "function" then
			recordPlayback(false, "PlaySoundFile unavailable", preview)
			return false, "PlaySoundFile is unavailable."
		end
		ok, played = pcall(PlaySoundFile, d.path, channel)
	else
		if type(PlaySound) ~= "function" then
			recordPlayback(false, "PlaySound unavailable", preview)
			return false, "PlaySound is unavailable."
		end
		ok, played = pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, channel)
	end
	if not ok or ns.isSecret(played) or played ~= true then
		recordPlayback(false, "playback not confirmed", preview)
		return false, "Playback not confirmed. Check the file path and game sound settings."
	end
	if not preview then sounds.lastPlayed = now end
	recordPlayback(true, preview and "preview played" or "played", preview)
	return true, "Sound played."
end

function sounds.HandleCLEU(args)
	local d = sounds.Config()
	if not d or not d.enabled or not ns.db.enabled or type(args) ~= "table" then return end
	local sub, source = args[2], args[4]
	if ns.isSecret(sub) or type(sub) ~= "string" or ns.isSecret(source) then return end
	local event = events[sub]
	if not event or d[event[1]] ~= true then return end
	local player = ns.api.PlayerGUID()
	if ns.isSecret(player) or type(player) ~= "string" or source ~= player then return end
	local critical = args[event[2]]
	if ns.isSecret(critical) or critical ~= true then return end
	-- A readable player crit is observed even when playback is refused later;
	-- the counter must not imply the sound actually played.
	sounds.diagnostics.playerCrits = (sounds.diagnostics.playerCrits or 0) + 1
	sounds.Play(false)
end

-- Honest state: registration is never treated as proof of delivery. States are
-- disabled / unsupported / blocked / rejected / unverified / delivering /
-- verified / idle.
function sounds.DetectionState()
	if not ns.db or not ns.db.enabled then return "disabled" end
	local available = ns.api and ns.api.CombatLogAvailable and ns.api.CombatLogAvailable() or false
	if not available then return "unsupported" end
	if ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
		local diag = sounds.diagnostics
		if (diag.delivered or 0) == 0 then return "unverified" end
		if (diag.playerCrits or 0) == 0 then return "delivering" end
		return "verified"
	end
	if sounds.diagnostics.lastAttemptAccepted == false then return "rejected" end
	if ns.RestrictedEngineReason then
		local restricted = ns.RestrictedEngineReason()
		if restricted then return "blocked" end
	end
	return "idle"
end

local STATE_TEXT = {
	disabled = "Crit detection: helper disabled, automatic crit sounds are off.",
	unsupported = "Crit detection unsupported: CombatLogGetCurrentEventInfo is unavailable on this client; no registration was attempted.",
	blocked = "Crit detection blocked: this restricted engine gate keeps the combat log unsubscribed. Click Try crit detection to request it for this session; delivery is still unverified.",
	rejected = "Crit detection rejected: the client refused the combat-log subscription. No workaround is attempted.",
	unverified = "Crit detection unverified: the subscription was accepted, but no combat-log event has been delivered yet. Registration is not delivery.",
	delivering = "Crit detection is delivering combat-log events, but no readable player crit has been observed yet.",
	verified = "Crit detection verified this session: readable player crits were observed and playback was attempted.",
	idle = "Crit detection idle: no combat-log subscription for this session.",
}

function sounds.Status()
	local diag = sounds.diagnostics
	local state = sounds.DetectionState()
	local playback
	if diag.lastPlaybackOk == nil then playback = "no attempt"
	elseif diag.lastPlaybackOk then playback = diag.lastPlaybackPreview and "preview played" or "played"
	else playback = "refused (" .. tostring(diag.lastPlaybackReason or "unknown") .. ")" end
	local line = string.format(
		"crit detection=%s | registered=%s | events delivered=%d | readable player crits=%d | last playback=%s",
		state, tostring(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED")),
		diag.delivered or 0, diag.playerCrits or 0, playback)
	return line .. "\n" .. (STATE_TEXT[state] or "")
end

-- Explicit, session-only opt-in. This is the only GUI path that may request the
-- guarded CLEU registration; it never writes ns.observeCLEU to SavedVariables.
function sounds.TryDetection()
	local diag = sounds.diagnostics
	if not ns.db or not ns.db.enabled then
		return false, "Helper is disabled: enable it before trying crit detection."
	end
	ns.observeCLEU = true
	diag.attempts = (diag.attempts or 0) + 1
	diag.lastAttemptAt = ns.now()
	if not (ns.api and ns.api.CombatLogAvailable and ns.api.CombatLogAvailable()) then
		diag.lastAttemptAccepted = false
		return false, "CombatLogGetCurrentEventInfo is unavailable on this client; crit detection cannot work and no registration was attempted."
	end
	local accepted = ns.SetupCLEU(true)
	diag.lastAttemptAccepted = accepted and true or false
	if not accepted then
		return false, "The client refused the combat-log subscription; automatic crit sounds cannot work. No workaround is attempted."
	end
	return true, "Combat-log subscription requested and accepted for this session. Delivery is unverified until an event arrives; the counters are the only proof."
end

-- Session-only stop; mirrors /euihot observe off without a chat line.
function sounds.StopDetection()
	ns.observeCLEU = false
	if ns.capabilities then
		ns.capabilities.cleuRequested = false
		ns.capabilities.cleuAccepted = false
		ns.capabilities.cleuOverride = false
		ns.capabilities.cleuGateReason = "disabled from the Sounds tab for this session"
	end
	ns.unregister("COMBAT_LOG_EVENT_UNFILTERED")
	return true, "Combat-log subscription removed for this session."
end

function sounds.Setup()
	if sounds.started then return end
	sounds.started = true
	ns.on("COMBAT_LOG_EVENT_UNFILTERED", function(_, ...)
		-- Count deliveries before any filter: this is the honest proof that the
		-- client is actually sending the event, whatever playback decides.
		sounds.diagnostics.delivered = (sounds.diagnostics.delivered or 0) + 1
		local d = sounds.Config()
		if not d or not d.enabled then return end
		if select("#", ...) > 0 then sounds.HandleCLEU(ns.pack(...))
		else sounds.HandleCLEU(ns.api.GetCLEU()) end
	end)
end

function sounds.BuildOptionsUI(f)
	local page = CreateFrame("Frame", nil, f)
	page:SetSize(510, 492)
	page:SetPoint("TOPLEFT", f, "TOPLEFT", f.contentX or 15, f.contentY or -100)
	f.soundsPage = page
	UI.Background(page, -3, 4, 516, 492)
	local function label(text, x, y, width)
		return UI.Label(page, text, x, y, width or 480)
	end
	UI.Text(label("CRITICAL HITS & HEALS", 10, -5), "section")
	local function check(key, title, y)
		local c = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
		c:SetSize(26, 26); c:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y)
		label(title, 40, y - 6)
		UI.Checkbox(c)
		f.controls[key] = c
	end
	check("soundsEnabled", "Enable crit sounds (off by default)", -30)
	check("soundsDamage", "Damage crits (melee, ranged, spells and periodic damage)", -62)
	check("soundsHealing", "Healing crits (direct and periodic heals)", -94)
	label("Local .ogg / .mp3 path (blank = built-in raid warning)", 10, -136, 330)
	local function field(key, x, y, width)
		local e = CreateFrame("EditBox", nil, page, "BackdropTemplate")
		e:SetSize(width, 24); e:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
		e:SetAutoFocus(false); e:SetMaxLetters(240)
		e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		UI.Input(e)
		f.controls[key] = e
		return e
	end
	field("soundsPath", 14, -158, 470)
	local cue = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	cue:SetSize(150, 24); cue:SetPoint("TOPLEFT", page, "TOPLEFT", 350, -131)
	UI.Button(cue)
	f.controls.soundsCue = cue
	local function cueLabel(path)
		if path == BAM_PATH then return "Cue: bam.mp3" end
		if path == nil or path == "" then return "Cue: built-in" end
		return "Cue: custom"
	end
	cue:SetScript("OnClick", function()
		-- Small predefined picker: bundled bam.mp3 <-> built-in raid warning.
		-- The manual path field is kept, so any custom path still works.
		local path = f.controls.soundsPath
		path:SetText(path:GetText() == BAM_PATH and "" or BAM_PATH)
		cue:SetText(cueLabel(path:GetText()))
	end)
	UI.Text(label("Default: Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3\nPlace the file there before launching WoW. No URLs or downloads.", 10, -192), "muted")
	label("Cooldown (0-30 seconds)", 10, -238, 200)
	field("soundsCooldown", 212, -232, 70)
	local channel = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	channel:SetSize(150, 24); channel:SetPoint("TOPLEFT", page, "TOPLEFT", 302, -232)
	channel:SetScript("OnClick", function(self)
		self.channel = self.channel == "Master" and "SFX" or "Master"
		self:SetText("Channel: " .. self.channel)
	end)
	f.controls.soundsChannel = channel
	UI.Button(channel)
	local message = label("", 10, -334)
	local function save()
		local c = f.controls
		local ok, msg = sounds.SetConfig({ enabled = c.soundsEnabled:GetChecked(), damage = c.soundsDamage:GetChecked(),
			healing = c.soundsHealing:GetChecked(), path = c.soundsPath:GetText(),
			cooldown = c.soundsCooldown:GetText(), channel = channel.channel })
		message:SetText(msg)
		return ok
	end
	local function button(title, x, y, width, fn)
		local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		b:SetSize(width, 24); b:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
		b:SetText(title); b:SetScript("OnClick", fn)
		UI.Button(b)
		return b
	end
	f.controls.soundsApply = button("Apply sound settings", 10, -270, 160, save)
	f.controls.soundsTest = button("Apply + Test sound", 180, -270, 160, function()
		if save() then local _, msg = sounds.Play(true); message:SetText(msg) end
	end)
	UI.Button(f.controls.soundsTest, "primary")
	f.controls.soundsDetect = button("Try crit detection", 10, -300, 160, function()
		local _, msg = sounds.TryDetection()
		message:SetText(msg)
		f.RefreshSounds()
	end)
	UI.Button(f.controls.soundsDetect, "primary")
	f.controls.soundsStop = button("Stop detection", 180, -300, 160, function()
		local _, msg = sounds.StopDetection()
		message:SetText(msg)
		f.RefreshSounds()
	end)
	UI.Button(f.controls.soundsStop, "danger")
	UI.Rect(page, 10, -362, 480, 1, UI.colors.border)
	local status = label("", 10, -372, 486)
	sounds.statusLabel = status
	UI.Text(label("Restricted Forever / Midnight clients may block crit data. Registration is not delivery; only the counters above can confirm it. This feature never bypasses that restriction or guesses a crit. Pets and other players never trigger your sound.", 10, -430, 486), "muted")
	function f.RefreshSounds()
		local d, c = sounds.Config(), f.controls
		c.soundsEnabled:SetChecked(d.enabled); c.soundsDamage:SetChecked(d.damage); c.soundsHealing:SetChecked(d.healing)
		c.soundsPath:SetText(d.path); c.soundsCooldown:SetText(tostring(d.cooldown))
		channel.channel = d.channel; channel:SetText("Channel: " .. d.channel)
		c.soundsCue:SetText(cueLabel(d.path))
		status:SetText(sounds.Status())
	end
end
