-- Read-only EllesmereUI action-bar integration. Never infer a queue from a cast
-- attempt, cooldown, Rage, usability, range, or Blizzard's proc-glow state.
local _, ns = ...
local swing = { buttons = {}, candidates = {}, active = 0, reason = "not scanned" }
ns.queuedSwing = swing

-- Exact next-melee rank IDs, not localized names. Modern instant versions with
-- these IDs still require the client's current-action flag; a press isn't enough.
local spells = {}
local families = {
	Maul = { 6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996, 48479, 48480 },
	["Heroic Strike"] = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286, 25242, 29707, 30324, 47449, 47450 },
	Cleave = { 845, 7369, 11608, 11609, 20569, 25231, 47519, 47520 },
}
for family, ids in pairs(families) do
	for _, id in ipairs(ids) do spells[id] = family end
end
swing.spells = spells -- GUI catalog uses the detector's actual registry.

local function api(group, key, legacy)
	local t = _G[group]
	if type(t) == "table" and type(t[key]) == "function" then return t[key] end
	return type(_G[legacy]) == "function" and _G[legacy] or nil
end

local function enabled()
	return ns.db and ns.db.enabled and ns.db.queuedSwingEnabled
end

local function publicBoolean(fn, arg)
	if not fn then return nil end
	local ok, value = pcall(fn, arg)
	if not ok or ns.isSecret(value) then return nil end
	if value == true or value == 1 then return true end
	if value == false or value == 0 then return false end
	return nil
end

local function resolve(button)
	-- Do not read/write btn.action (a protected derived mirror in EllesmereUI).
	local ok, slot = pcall(button.GetAttribute, button, "action")
	slot = ok and ns.toNumber(slot) or nil
	if not slot or not ns.isPositiveInt(slot) then return nil end
	local getInfo = api("C_ActionBar", "GetActionInfo", "GetActionInfo")
	if not getInfo then return nil end
	local success, kind, id = pcall(getInfo, slot)
	if not success or ns.isSecret(kind) then return nil end
	id = ns.toNumber(id)
	if not id then return nil end
	if kind == "macro" then
		-- Only the client's effective macro spell, never #showtooltip or a text
		-- parser. Ambiguous/item/castsequence macros without an ID stay unlit.
		if type(GetMacroSpell) ~= "function" then return nil end
		local good, first, _, third = pcall(GetMacroSpell, id)
		if not good then return nil end
		id = ns.toNumber(first) or ns.toNumber(third)
	elseif kind ~= "spell" then
		return nil
	end
	if not id or not spells[id] then return nil end
	return slot, id, kind
end

local function queued(slot, id, kind)
	local currentAction = api("C_ActionBar", "IsCurrentAction", "IsCurrentAction")
	local currentSpell = api("C_Spell", "IsCurrentSpell", "IsCurrentSpell")
	-- A readable false is authoritative; do not override it with a guessed state.
	-- Macros need the effective spell query, since IsCurrentAction isn't reliable
	-- for macro slots. A missing/restricted API is unknown, NEVER queued.
	if kind == "macro" then return publicBoolean(currentSpell, id) end
	if currentAction then return publicBoolean(currentAction, slot) end
	return publicBoolean(currentSpell, id)
end

local function prepare(button)
	if ns.api.InCombat() or type(CreateFrame) ~= "function" then return nil end
	local ok, border = pcall(function()
		local f = CreateFrame("Frame", nil, button, "BackdropTemplate")
		f:Hide()
		f:EnableMouse(false)
		f:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
		f:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 3, -3)
		f:SetFrameLevel(button:GetFrameLevel() + 10)
		f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
		return f
	end)
	return ok and border or nil
end

local function style(record)
	local f, db = record.border, ns.db
	if not f then return end
	-- Reconfigure only our decoration, never resize the actual action button.
	-- Geometry edits wait for regen; color/opacity can change immediately.
	if not ns.api.InCombat() then
		if record.thickness ~= db.queuedSwingThickness then
			f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = db.queuedSwingThickness })
			record.thickness, record.color = db.queuedSwingThickness, nil
		end
		if record.padding ~= db.queuedSwingPadding then
			local p = db.queuedSwingPadding
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", record.button, "TOPLEFT", -p, p)
			f:SetPoint("BOTTOMRIGHT", record.button, "BOTTOMRIGHT", p, -p)
			record.padding = p
		end
	end
	local c = db.queuedSwingColor
	if record.color ~= c or record.alpha ~= db.queuedSwingAlpha then
		f:SetBackdropBorderColor(c[1], c[2], c[3], db.queuedSwingAlpha)
		record.color, record.alpha = c, db.queuedSwingAlpha
	end
end

-- One atomic, validated appearance update shared by the GUI and renderer.
function swing.SetAppearance(thickness, padding, alpha, r, g, b)
	if not ns.toNumber(thickness) or not ns.toNumber(padding) or not ns.toNumber(alpha)
		or not ns.toNumber(r) or not ns.toNumber(g) or not ns.toNumber(b)
		or thickness < 1 or thickness > 12 or padding < -12 or padding > 24
		or alpha < 0 or alpha > 1 or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return false end
	ns.db.queuedSwingThickness, ns.db.queuedSwingPadding, ns.db.queuedSwingAlpha = thickness, padding, alpha
	ns.db.queuedSwingColor = { r, g, b }
	for _, record in pairs(swing.buttons) do style(record) end
	swing.Refresh()
	return true
end

function swing.Refresh()
	swing.active = 0
	local unknown = false
	for _, record in ipairs(swing.candidates) do
		-- Re-resolve every sample: paging, form swaps and macro changes cannot
		-- leave a border attached to the previous spell/slot.
		local slot, id, kind = resolve(record.button)
		local value = slot and queued(slot, id, kind)
		if slot and value == nil then unknown = true end
		local shown = enabled() and value == true
		local f = record.border
		if f then
			if shown then
				style(record)
				if not record.shown then f:Show() end
				swing.active = swing.active + 1
			elseif record.shown then
				f:Hide()
			end
			record.shown = shown and true or false
		end
	end
	swing.reason = not enabled() and "disabled" or (unknown and "queue API unavailable/restricted" or "public queue state")
end

function swing.Scan()
	local found, candidates = {}, {}
	-- Supplied EllesmereUI owns EABButton<slot>, through page 15 (180).
	-- Never scan unrelated Blizzard, stance, pet, or proc-highlight buttons.
	for i = 1, 180 do
		local button = _G["EABButton" .. i]
		if button and not ns.isSecret(button) then
			local record = swing.buttons[button] or { button = button }
			record.border = record.border or prepare(button)
			style(record)
			found[button] = record
			if resolve(button) then candidates[#candidates + 1] = record
			elseif record.border then record.border:Hide(); record.shown = false end
		end
	end
	for button, record in pairs(swing.buttons) do
		if not found[button] and record.border then record.border:Hide() end
	end
	swing.buttons, swing.candidates = found, candidates
	swing.nextScan = ns.now() + 1
	swing.Refresh()
	-- Fast safety net only when next-swing buttons exist; events paint immediately.
	if not swing.driver and #candidates > 0 and CreateFrame then swing.driver = CreateFrame("Frame") end
	if swing.driver then
		swing.driver:SetScript("OnUpdate", #candidates > 0 and function(_, elapsed)
			swing.elapsed = (swing.elapsed or 0) + elapsed
			if swing.elapsed >= 0.05 then
				swing.elapsed = 0
				local ok = pcall(swing.Refresh)
				if not ok then swing.Hide(); swing.reason = "queue refresh failed (protected)" end
			end
		end or nil)
	end
end

function swing.Hide()
	for _, record in pairs(swing.buttons) do
		if record.border then record.border:Hide() end
		record.shown = false
	end
	swing.active = 0
end

-- The existing helper timer handles late-created/replaced vendor frames. It
-- continues even when native healing prediction is absent; no second ticker.
function swing.Tick()
	if enabled() and (not swing.nextScan or ns.now() >= swing.nextScan) then swing.Scan() end
end

function swing.SetEnabled()
	if swing.driver then swing.driver:SetScript("OnUpdate", nil) end
	swing.elapsed, swing.nextScan = 0, nil
	swing.Hide()
	if enabled() then swing.Scan() else swing.reason = "disabled" end
end

local function update(event, unit)
	if unit and ns.isSecret(unit) then return end
	if unit and type(unit) == "string" and unit ~= "player" then return end
	if not enabled() then return end
	if event == "ACTIONBAR_UPDATE_STATE" or event == "UNIT_POWER_UPDATE"
		or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
		swing.Refresh()
	else swing.Scan() end
end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"ACTIONBAR_UPDATE_STATE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_SHAPESHIFT_FORM", "UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR",
	"UPDATE_VEHICLE_ACTIONBAR", "UPDATE_MACROS", "SPELLS_CHANGED", "PLAYER_TARGET_CHANGED",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_DISPLAYPOWER", "UNIT_POWER_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE" }) do
	ns.on(event, update)
end
