local function env()
	local e = Mocks.NewEnv({ noCLEU = true, build = { "1.60.1", 70205, "2026-10-04", 16001 } })
	e.ns.HandleCommand("approximate on")
	e.target = { guid = "Target-A", dead = false, hostile = true, exists = true, auras = {} }
	local original = C_UnitAuras.GetAuraDataByIndex
	C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if unit == "target" then
			e.target.scans = (e.target.scans or 0) + 1
			assert_true(filter == "HARMFUL|PLAYER" or filter == "HARMFUL")
			return e.target.auras[i]
		end
		return original(unit, i, filter)
	end
	_G.UnitGUID = function(unit) return unit == "target" and e.target.guid or Mocks.playerGUID end
	_G.UnitExists = function(unit) return unit ~= "target" or e.target.exists end
	_G.UnitCanAttack = function(_, unit) return unit == "target" and e.target.hostile end
	_G.UnitIsDeadOrGhost = function(unit) return unit == "target" and e.target.dead or false end
	return e
end
local function aura(id, duration, expires, source)
	return { spellId = id, applications = 0, duration = duration, expirationTime = expires,
		auraInstanceID = 10, sourceUnit = source or "player" }
end
local function total(e)
	e.ns.overlay.Tick(true)
	return e.ns.session.lastStatus.hotEstimate
end

T.register("all classes: every Raptor Strike rank lights only with readable actual current state", function()
	local e = env()
	local current = false
	_G.GetActionInfo = function() return "spell", e.rank end
	_G.IsCurrentAction = function() return current end
	local b = CreateFrame("CheckButton", "EABButton1", UIParent)
	b:SetAttribute("action", 1)
	for _, id in ipairs({ 2973,14260,14261,14262,14263,14264,14265,14266 }) do
		e.rank = id; current = false; e.ns.queuedSwing.Scan()
		local border = e.ns.queuedSwing.buttons[b].border
		assert_false(border:IsShown())
		Mocks.Fire("UNIT_SPELLCAST_SENT", "player", "target", "cast", id)
		assert_false(border:IsShown())
		current = true; Mocks.Fire("ACTIONBAR_UPDATE_STATE"); assert_true(border:IsShown())
		current = false; Mocks.Fire("ACTIONBAR_UPDATE_STATE"); assert_false(border:IsShown())
	end
	for _, id in ipairs({679,10333,23881,402927,6603,75,17364,1310222,20165}) do
		e.rank = id; current = true; e.ns.queuedSwing.Scan()
		assert_false(e.ns.queuedSwing.buttons[b].border:IsShown(), "instant attacks and procs never treated as queues")
	end
end)

T.register("all classes: all Drain Life ranks require real channel and clear at cancellation", function()
	local e = env()
	for _, id in ipairs({689,699,709,7651,11699,11700}) do
		Mocks.descriptions[id] = "Transfers 51 health every 1 second from the target to the caster. Lasts 5 sec."
		Mocks.channel = { id = id, start = 100000, finish = 105000 }
		assert_eq(total(e), 255)
		Mocks.now = 102.1; assert_eq(total(e), 153)
		Mocks.channel = nil; total(e); assert_false(e.ns.overlay.state.frame:IsShown())
		Mocks.now = 100
	end
	Mocks.channel = { id = 689, start = Mocks.MakeSecret(), finish = 105000 }
	assert_nil(e.ns.api.ReadPlayerChannel())
	Mocks.channel = { id = 689, start = 100000, finish = 105000 }
	e.ns.HandleCommand("approximate off")
	assert_nil(e.ns.api.ReadPlayerChannel())
	total(e); assert_false(e.ns.overlay.state.frame:IsShown())
end)

T.register("all classes: owned current-target Siphon Life and Devouring Plague sum self healing", function()
	local e = env()
	local siphon = {18265,18879,18880,18881}
	local plague = {2944,19276,19277,19278,19279,19280}
	for _, id in ipairs(siphon) do
		Mocks.descriptions[id] = "Transfers 41 health from the target to the caster every 3 sec. Lasts 30 sec."
		e.target.auras = { aura(id, 30, 130) }; Mocks.Fire("UNIT_AURA", "target")
		assert_eq(total(e), 410)
	end
	for _, id in ipairs(plague) do
		Mocks.descriptions[id] = "Afflicts the target with a disease that causes 848 Shadow damage over 24 sec. Damage caused by the Devouring Plague heals the caster."
		e.target.auras = { aura(id, 24, 124) }; Mocks.Fire("UNIT_AURA", "target")
		assert_eq(total(e), 848)
	end
	e.target.auras = { aura(18881, 30, 130), aura(19280, 24, 124) }
	Mocks.SetAuras({ aura(774, 12, 112) }); Mocks.descriptions[774] = "Heals 48 over 12 sec."
	Mocks.Fire("UNIT_AURA", "target")
	assert_eq(total(e), 410 + 848 + 48)
	local scans = e.target.scans
	total(e); assert_eq(e.target.scans, scans, "reuse target aura cache while identity is unchanged")
	Mocks.now = 131; total(e)
	assert_false(e.ns.overlay.state.frame:IsShown())
end)

T.register("all classes: target drain removal death identity and restricted data fail closed", function()
	local e = env()
	Mocks.descriptions[18881] = "Transfers 41 health from the target to the caster every 3 sec. Lasts 30 sec."
	e.target.auras = { aura(18881, 30, 130) }
	assert_eq(total(e), 410)
	e.target.guid, e.target.auras = "Target-B", {}
	total(e); assert_false(e.ns.overlay.state.frame:IsShown(), "identity probe clears old target without event")
	e.target.auras = { aura(18881, 30, 130) }; Mocks.Fire("UNIT_AURA", "target")
	assert_eq(total(e), 410)
	for _, field in ipairs({ "dead", "hostile", "exists", "guid" }) do
		local original = e.target[field]
		e.target[field] = field == "dead" and true or field == "guid" and Mocks.MakeSecret() or false
		total(e); assert_false(e.ns.overlay.state.frame:IsShown(), "unusable target: " .. field)
		e.target[field] = original
	end
	for _, source in ipairs({ "party1", Mocks.MakeSecret() }) do
		e.target.auras = { aura(18881, 30, 130, source) }; Mocks.Fire("UNIT_AURA", "target")
		total(e); assert_false(e.ns.overlay.state.frame:IsShown())
	end
	e.target.auras = { aura(18881, Mocks.MakeSecret(), 130) }; Mocks.Fire("UNIT_AURA", "target")
	total(e); assert_false(e.ns.overlay.state.frame:IsShown())
	e.target.auras = { Mocks.MakeSecret() }; Mocks.Fire("UNIT_AURA", "target")
	total(e); assert_false(e.ns.overlay.state.frame:IsShown())
	-- A player buff with a damaging-drain ID is NOT a hostile target application.
	e.target.auras = {}; Mocks.SetAuras({ aura(18881, 30, 130) })
	total(e); assert_false(e.ns.overlay.state.frame:IsShown())
end)

T.register("all classes: target aura tooltip is read from target and target identity invalidates magnitude", function()
	local e = env()
	e.target.auras = { aura(18881, 30, 130) }
	local amount = 41
	_G.C_TooltipInfo = { GetUnitAuraByAuraInstanceID = function(unit, instance, filter)
		assert_eq(unit, "target"); assert_eq(filter, "HARMFUL")
		return { lines = { { leftText = "Transfers " .. amount .. " health from the target to the caster every 3 sec. Lasts 30 sec." } } }
	end }
	assert_eq(total(e), 410)
	e.target.guid, amount = "Target-New", 30
	assert_eq(total(e), 300, "same instance/expiry on new target cannot reuse tooltip amount")
	e.ns.HandleCommand("approximate off")
	total(e); assert_false(e.ns.overlay.state.frame:IsShown())
end)

T.register("all classes: English German transfer and plague text parsing", function()
	local e = env()
	_G.GetLocale = function() return "deDE" end
	Mocks.descriptions[18881] = "Überträgt alle 3 Sek. 41 Gesundheit vom Ziel auf den Zaubernden. Hält 30 Sek. lang an."
	e.target.auras = { aura(18881, 30, 130) }
	assert_eq(total(e), 410)
	Mocks.descriptions[19280] = "Infiziert das Ziel mit einer Krankheit und fügt so 24 Sek. lang 848 Punkt(e) Schattenschaden zu. Schaden, der durch 'Verschlingende Seuche' zugefügt wird, heilt den Zaubernden."
	e.target.auras = { aura(19280, 24, 124) }; Mocks.Fire("UNIT_AURA", "target")
	assert_eq(total(e), 848)
	local parse = e.ns.estimates.ParseLifeDrain
	assert_nil(parse(Mocks.MakeSecret(), "enUS"))
	assert_nil(parse("Grants 100 mana every 3 seconds", "enUS"))
	assert_nil(parse("Transfers 41 health from the target to the caster every 3 sec.", "frFR"))
	assert_nil(parse("848 Shadow damage over 0 sec. Damage heals the caster.", "enUS"))
	assert_nil(parse("fügt so 0 Sek. lang 848 Punkt(e) Schattenschaden zu und heilt den Zaubernden.", "deDE"))
end)

T.register("all classes: Lightwell applied Renew requires cadence not summon lifetime", function()
	local e = env()
	for _, ids in ipairs({{7001,724},{27873,27870},{27874,27871}}) do
		local id, summon = ids[1], ids[2]
		Mocks.descriptions[summon] = "Creates a Lightwell that restores 1600 health over 10 sec. Lightwell lasts for 3 min or 5 charges."
		Mocks.SetAuras({ aura(id, 10, 110) })
		total(e); assert_false(e.ns.overlay.state.frame:IsShown(), "no invented cadence")
		e.ns.HandleCommand("interval " .. id .. " 2")
		assert_eq(total(e), 1600)
		Mocks.SetAuras({}); total(e); assert_false(e.ns.overlay.state.frame:IsShown())
		Mocks.SetAuras({ aura(summon, 180, 280) }); total(e); assert_false(e.ns.overlay.state.frame:IsShown())
	end
	Mocks.SetAuras({ aura(7001, 10, 110, "party1") })
	total(e); assert_false(e.ns.overlay.state.frame:IsShown(), "other players' Lightwells remain outside scope")
end)
