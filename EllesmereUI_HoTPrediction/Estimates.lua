-- Optional rough estimates from PUBLIC tooltip text; never a combat-log sample.
-- Only verified supported periodic families are parsed. No spell-power coefficient
-- tables, base heal constants, or parsing of restricted strings are used.
local addonName, ns = ...
local estimates = {}
ns.estimates = estimates
local NUMBER = "(%d[%d%.,]*)"
local CACHE_SECONDS = 5
local forever

function estimates.Invalidate()
	if ns.session then ns.session.tooltipCache = nil end
end

local function isForever()
	if forever == nil then
		local ok, _, _, _, toc = pcall(GetBuildInfo or function() end)
		local n = ok and ns.toNumber(toc)
		forever = n ~= nil and n >= 16000 and n <= 19999
	end
	return forever
end

local function number(text, locale)
	if locale == "deDE" then text = text:gsub("%.", ""):gsub(",", ".")
	else text = text:gsub(",", "") end
	local n = ns.toNumber(tonumber(text))
	if n and n > 0 and n <= ns.AMOUNT_OVERRIDE_MAX then return n end
end

-- Fail closed on unknown locales, ranges or ambiguous periodic clauses. In
-- particular Regrowth/Riptide's initial direct heal must never enter the estimate.
function estimates.Parse(text, locale)
	if ns.isSecret(text) then return nil, "tooltip text restricted" end
	if type(text) ~= "string" or text == "" then return nil, "tooltip text unavailable" end
	if #text > 8192 then return nil, "tooltip text too long" end
	if locale ~= "enUS" and locale ~= "enGB" and locale ~= "deDE" then
		return nil, "tooltip locale unsupported; use manual amount"
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
	-- Join grouped thousands without treating the trailing group as the amount.
	for i = 1, 3 do
		text = text:gsub("(%d)\194\160(%d)", "%1%2")
		text = text:gsub("(%d)\226\128\175(%d)", "%1%2")
		text = text:gsub("(%d)%s+(%d)", "%1%2")
	end
	if not (text:find("heal", 1, true) or text:find("restor", 1, true)
		or text:find("heil", 1, true) or text:find("regener", 1, true)
		or text:find("gesundheit", 1, true)) then return nil, "no healing clause in tooltip" end
	-- Percentage conversion must not be parsed as flat healing. The resource
	-- model is gated by metadata and handles only current readable rage.
	local cap, percent
	if locale == "deDE" then
		cap = text:match("bis%s+zu%s+" .. NUMBER .. "%s+wut%s+pro%s+sek")
		percent = text:match("jeder%s+punkt%s+wut.-in%s+" .. NUMBER .. "%%%s+gesundheit")
	else
		cap = text:match("up%s+to%s+" .. NUMBER .. "%s+rage%s+per%s+second")
		percent = text:match("each%s+point%s+of%s+rage.-into%s+" .. NUMBER .. "%%%s+health")
	end
	if cap and percent then
		cap, percent = number(cap, locale), number(percent, locale)
		if cap and percent and cap <= 100 and percent <= 100 then
			return { kind = "ragePercent", amount = percent, seconds = 1, rageCap = cap }
		end
		return nil, "invalid rage conversion tooltip"
	end

	local patterns
	if locale == "deDE" then
		patterns = {
			{ NUMBER .. "%s+sek%.?%s+lang%s+um%s+" .. NUMBER .. "%s+schadenspunkt", "total", true },
			{ "alle%s+" .. NUMBER .. "%s+sek%.?%s+" .. NUMBER .. "%s+gesundheit", "tick", true },
			{ NUMBER .. "%s+gesundheit%s+alle%s+" .. NUMBER .. "%s+sek", "tick" },
			{ "alle%s+" .. NUMBER .. "%s+sek.-um%s+" .. NUMBER, "tick", true },
			{ "im%s+verlauf%s+von%s+" .. NUMBER .. "%s+sek%.?%s+um%s+weitere%s+" .. NUMBER, "total", true },
			{ "im%s+verlauf%s+von%s+" .. NUMBER .. "%s+sek%.?%s+um%s+" .. NUMBER, "total", true },
			{ NUMBER .. "%s+gesundheit%s+über%s+" .. NUMBER .. "%s+sek", "total" },
			{ "um%s+" .. NUMBER .. "%s+in%s+" .. NUMBER .. "%s+sek", "total" },
		}
	else
		patterns = {
			{ NUMBER .. "%s+damage%s+over%s+" .. NUMBER .. "%s+sec", "total" },
			{ NUMBER .. "%s+every%s+" .. NUMBER .. "%s+sec", "tick" },
			{ NUMBER .. "%s+health%s+every%s+" .. NUMBER .. "%s+sec", "tick" },
			{ NUMBER .. "%s+over%s+" .. NUMBER .. "%s+sec", "total" },
			{ NUMBER .. "%s+over%s+the%s+next%s+" .. NUMBER .. "%s+sec", "total" },
			{ NUMBER .. "%s+health%s+over%s+" .. NUMBER .. "%s+sec", "total" },
		}
	end
	local result
	for _, spec in ipairs(patterns) do
		local pos = 1
		while pos <= #text do
			local first, last, a, b = text:find(spec[1], pos)
			if not first then break end
			local prefix = text:sub(1, first - 1)
			if prefix:match("to%s*$") or prefix:match("%-%s*$") then
				return nil, "ranged periodic amount; use manual amount"
			end
			a, b = number(a, locale), number(b, locale)
			if spec[3] then a, b = b, a end
			if not a or not b or b > 3600 then return nil, "invalid tooltip healing values" end
			local candidate = { kind = spec[2], amount = a, seconds = b }
			if result and (result.kind ~= candidate.kind or result.amount ~= a or result.seconds ~= b) then
				return nil, "ambiguous periodic tooltip; use manual amount"
			end
			result = candidate
			pos = last + 1
		end
	end
	if result then return result end
	return nil, "periodic tooltip wording unsupported; use manual amount"
end

local function field(obj, key)
	if ns.isSecret(obj) or type(obj) ~= "table" then return nil end
	local ok, v = pcall(function() return obj[key] end)
	if ok and not ns.isSecret(v) then return v end
end

local function locale()
	local ok, value = pcall(GetLocale or function() return "enUS" end)
	if ok and not ns.isSecret(value) and type(value) == "string" then return value end
	return "unknown"
end

local function readTooltip(id, aura, meta)
	local lang = locale()
	local why
	local fn = C_TooltipInfo and C_TooltipInfo.GetUnitAuraByAuraInstanceID
	local instance = aura and ns.toNumber(aura.instanceID)
	if type(fn) == "function" and instance then
		local ok, info = pcall(fn, "player", instance, "HELPFUL")
		local lines = ok and field(info, "lines")
		local result
		for i = 1, 40 do
			local line = field(lines, i)
			if not line then break end
			local parsed, err = estimates.Parse(field(line, "leftText"), lang)
			if parsed then
				if result and (result.kind ~= parsed.kind or result.amount ~= parsed.amount or result.seconds ~= parsed.seconds) then
					return nil, nil, "ambiguous aura tooltip; use manual amount"
				end
				result = parsed
			else why = err end
		end
		if result then return result, "active aura tooltip" end
	end
	fn = C_Spell and C_Spell.GetSpellDescription
	if type(fn) == "function" then
		local ids = { id }
		if meta and meta.tooltipSpellID and meta.tooltipSpellID ~= id then ids[2] = meta.tooltipSpellID end
		for _, spellID in ipairs(ids) do
			local ok, text = pcall(fn, spellID) -- exact rank or explicit verified effect alias
			if ok then
				local parsed, err = estimates.Parse(text, lang)
				if parsed then return parsed, spellID == id and "spell description" or "spell description (effect alias)" end
				why = err
			else why = "spell description read failed" end
		end
	end
	return nil, nil, why or "tooltip APIs unavailable; use manual amount"
end

function estimates.Fill(data, id, aura)
	local meta = ns.spells.Meta(id)
	if not meta then return end
	local automaticFamily = meta.foreverInterval ~= nil
	if automaticFamily and not data.interval and isForever() then
		data.interval = meta.foreverInterval
		data.intervalSource = "Forever " .. tostring(meta.foreverInterval) .. "s cadence (approximate)"
	end
	if not automaticFamily then return end
	if data.basePerStack and data.interval then return end -- manual/observed wins
	local cache = ns.session.tooltipCache
	if not cache then cache = {}; ns.session.tooltipCache = cache end
	local now = ns.now()
	local instance = aura and ns.toNumber(aura.instanceID)
	local expiration = aura and ns.toNumber(aura.expirationTime)
	local entry = cache[id]
	if not entry or entry.untilTime <= now or entry.instance ~= instance or entry.expiration ~= expiration then
		local parsed, source, why = readTooltip(id, aura, meta)
		entry = { parsed = parsed, source = source, why = why, instance = instance,
			expiration = expiration, untilTime = now + CACHE_SECONDS }
		cache[id] = entry -- PUBLIC parsed values only; never retain tooltip strings
	end
	local parsed = entry.parsed
	if parsed then
		if parsed.kind == "ragePercent" then
			if meta.resourceHealing then
				data.ragePercent, data.rageCap = parsed.amount, parsed.rageCap
				data.amountSource = entry.source .. " (current-rage budget; future rage not predicted)"
			else data.estimateError = "percentage tooltip unsupported for this family" end
			return
		end
		if not data.interval and parsed.kind == "tick" then
			data.interval, data.intervalSource = parsed.seconds, entry.source
		elseif parsed.kind == "tick" and not data.manualInterval and not (ns.session.learned[id] or {}).interval then
			data.interval, data.intervalSource = parsed.seconds, entry.source
		end
		if not data.basePerStack then
			local amount
			if parsed.kind == "tick" then amount = parsed.amount
			elseif data.interval then
				local ticks = math.floor(parsed.seconds / data.interval + ns.model.EPS)
				if ticks >= 1 and ticks <= 10000 then amount = parsed.amount / ticks end
			end
			if amount then
				data.basePerStack, data.amountSource = amount, entry.source .. " (approximate)"
				if meta.family == "WildGrowth" and parsed.kind == "total" then
					data.amountSource = data.amountSource .. "; average tick, taper unmodelled"
				end
			end
		end
	else
		data.estimateError = entry.why
		data.nextEstimateRetry = entry.untilTime
	end
end
