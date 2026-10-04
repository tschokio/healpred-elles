-- DoHelper / CritSounds.lua
-- Only positively readable player-sourced critical combat-log events qualify.
-- Reuse the existing CLEU subscription and its restricted-engine policy: this
-- module never registers forbidden events or guesses from casts/health changes.
local _, ns = ...
local UI = ns.ui
local sounds = {}
ns.critSounds = sounds

local events = {
	SWING_DAMAGE = { "damage", 18 },
	RANGE_DAMAGE = { "damage", 21 },
	SPELL_DAMAGE = { "damage", 21 },
	SPELL_PERIODIC_DAMAGE = { "damage", 21 },
	SPELL_HEAL = { "healing", 18 },
	SPELL_PERIODIC_HEAL = { "healing", 18 },
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

-- Manual preview ignores enable/filter/cooldown, but still reports playback
-- refusal honestly. No file is downloaded and missing files never fall back.
function sounds.Play(preview)
	local d = sounds.Config()
	if not d then return false, "Settings unavailable." end
	if not preview and (not d.enabled or not ns.db.enabled) then return false end
	local now = ns.now()
	local cooldown = ns.toNumber(d.cooldown) or 0.5
	if not preview and sounds.lastPlayed and now - sounds.lastPlayed < cooldown then return false end
	local channel = d.channel == "SFX" and "SFX" or "Master"
	local ok, played
	if type(d.path) == "string" and d.path ~= "" then
		if type(PlaySoundFile) ~= "function" then return false, "PlaySoundFile is unavailable." end
		ok, played = pcall(PlaySoundFile, d.path, channel)
	else
		if type(PlaySound) ~= "function" then return false, "PlaySound is unavailable." end
		ok, played = pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, channel)
	end
	if not ok or ns.isSecret(played) or played ~= true then
		return false, "Playback not confirmed. Check the file path and game sound settings."
	end
	if not preview then sounds.lastPlayed = now end
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
	sounds.Play(false)
end

function sounds.Status()
	if not ns.db.enabled then return "Helper disabled: automatic crit sounds are off." end
	if not ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED") then
		return "Crit detection unavailable: combat log is not subscribed. Test playback still works."
	end
	return "Uses readable player crits only; combat-log registration does not guarantee delivery."
end

function sounds.Setup()
	if sounds.started then return end
	sounds.started = true
	ns.on("COMBAT_LOG_EVENT_UNFILTERED", function(_, ...)
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
	label("Local .ogg / .mp3 path (blank = built-in raid warning)", 10, -136)
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
	UI.Text(label("Example: Interface\\AddOns\\DoHelper\\Sounds\\bam.ogg\nPlace the file there before launching WoW. No URLs or downloads.", 10, -192), "muted")
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
	local message = label("", 10, -310)
	local function save()
		local c = f.controls
		local ok, msg = sounds.SetConfig({ enabled = c.soundsEnabled:GetChecked(), damage = c.soundsDamage:GetChecked(),
			healing = c.soundsHealing:GetChecked(), path = c.soundsPath:GetText(),
			cooldown = c.soundsCooldown:GetText(), channel = channel.channel })
		message:SetText(msg)
		return ok
	end
	local function button(title, x, fn)
		local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		b:SetSize(160, 24); b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -276)
		b:SetText(title); b:SetScript("OnClick", fn)
		UI.Button(b)
		return b
	end
	f.controls.soundsApply = button("Apply sound settings", 10, save)
	f.controls.soundsTest = button("Apply + Test sound", 180, function()
		if save() then local _, msg = sounds.Play(true); message:SetText(msg) end
	end)
	UI.Button(f.controls.soundsTest, "primary")
	local status = label("", 10, -346)
	UI.Rect(page, 10, -330, 480, 1, UI.colors.border)
	UI.Text(label("Restricted Forever / Midnight clients may block crit data.\nThis feature never bypasses that restriction or guesses a crit.\nPets and other players do not trigger your sound.\nMaster still requires game sound enabled; SFX also requires effects enabled.", 10, -388), "muted")
	function f.RefreshSounds()
		local d, c = sounds.Config(), f.controls
		c.soundsEnabled:SetChecked(d.enabled); c.soundsDamage:SetChecked(d.damage); c.soundsHealing:SetChecked(d.healing)
		c.soundsPath:SetText(d.path); c.soundsCooldown:SetText(tostring(d.cooldown))
		channel.channel = d.channel; channel:SetText("Channel: " .. d.channel)
		status:SetText(sounds.Status())
	end
end
