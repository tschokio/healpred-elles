-- EllesmereUI_HoTPrediction / Overlay.lua
-- Owns the single overlay bar that draws our conservative remainder segment at
-- the far end of the native incoming-heal chain. It never modifies native
-- frames or functions: it only reads them, creates its own StatusBar, and
-- secure-hooks native apply/layout callbacks (out of combat only) so it can
-- re-attach when the unit frame is rebuilt.

local addonName, ns = ...
local overlay = {}
ns.overlay = overlay

local TICK_INTERVAL = 0.15

overlay.state = {
	frame = nil,
	ab = nil,
	player = nil,
	hp = nil,
	parent = nil,
	chain = nil,
	pending = false,
	hooksInstalled = false,
}

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return false end
	return a, b, c
end

function overlay.IsCombat()
	return ns.api and ns.api.InCombat and ns.api.InCombat()
end

------------------------------------------------------------------------------
-- frame lifecycle
------------------------------------------------------------------------------

function overlay.EnsureFrame()
	local f = overlay.state.frame
	if f then return f end
	if type(CreateFrame) ~= "function" then return nil end
	local parent = (UIParent and UIParent) or nil
	f = CreateFrame("StatusBar", "EllesmereUI_HoTPredictionOverlay", parent)
	if f.SetMinMaxValues then f:SetMinMaxValues(0, 1) end
	if f.SetValue then f:SetValue(0) end
	if f.SetStatusBarTexture then f:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end
	if f.Hide then f:Hide() end
	overlay.state.frame = f
	return f
end

local function anchorTo(refBar, hpBar, ours, vertical, reversed)
	if not refBar then return false end
	local ref = refBar
	if refBar.GetStatusBarTexture then
		local tex = safeCall(refBar.GetStatusBarTexture, refBar)
		if tex then ref = tex end
	end
	if not ours.ClearAllPoints or not ours.SetPoint then return false end
	ours:ClearAllPoints()
	if not vertical and not reversed then
		ours:SetPoint("LEFT", ref, "RIGHT", 0, 0)
	elseif not vertical and reversed then
		ours:SetPoint("RIGHT", ref, "LEFT", 0, 0)
	elseif vertical and not reversed then
		ours:SetPoint("BOTTOM", ref, "TOP", 0, 0)
	else
		ours:SetPoint("TOP", ref, "BOTTOM", 0, 0)
	end
	if ours.SetOrientation then ours:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL") end
	if ours.SetReverseFill then ours:SetReverseFill(reversed) end
	if hpBar and ours.SetSize and hpBar.GetWidth and hpBar.GetHeight then
		ours:SetSize(hpBar:GetWidth(), hpBar:GetHeight())
	end
	local above = nil
	if refBar.GetFrameLevel then above = ns.toNumber(safeCall(refBar.GetFrameLevel, refBar)) end
	if above and ours.SetFrameLevel then ours:SetFrameLevel(above + 1) end
	return true
end

-- Pick orientation/reverse from the native prediction bar, else the health bar.
local function resolveAxes(ab, hp)
	local info = ns.api.GetBarInfo(ab and ab._predMy)
	if info and info.orientation then
		return info.orientation == "VERTICAL", info.reversed and true or false
	end
	info = ns.api.GetBarInfo(hp)
	return info and info.orientation == "VERTICAL" or false, (info and info.reversed) and true or false
end

local function chooseParent(ab, player)
	if ab and ab._missClip and ab._missClip.SetParent then return ab._missClip end
	if ab and ab.SetParent then return ab end
	if player and player.SetParent then return player end
	return UIParent
end

-- Structural resolve: find the native module, hook it once, re-parent/re-anchor
-- our own frame. Deferred entirely while in combat.
function overlay.Resolve()
	local ab, player, hp = ns.api.GetAbsorbFrame()
	if not ab or not player then
		overlay.Hide("native prediction module missing")
		return
	end
	if overlay.IsCombat() then
		overlay.state.pending = true
		return
	end
	overlay.state.ab = ab
	overlay.state.player = player
	overlay.state.hp = hp

	if not overlay.state.hooksInstalled then
		overlay.InstallHooks()
	end

	local parent = chooseParent(ab, player)
	local f = overlay.EnsureFrame()
	if not f then return end
	if overlay.state.parent ~= parent then
		f:SetParent(parent)
		overlay.state.parent = parent
	end

	local vertical, reversed = resolveAxes(ab, hp)
	overlay.state.vertical = vertical
	overlay.state.reversed = reversed
	local chain = ns.api.GetNativeChain(ab)
	overlay.state.chain = chain
	local ref = chain[#chain] or ab._predMy or hp
	anchorTo(ref, hp, f, vertical, reversed)
	if player.GetFrameStrata and f.SetFrameStrata then
		local strata = safeCall(player.GetFrameStrata, player)
		if strata then f:SetFrameStrata(strata) end
	end
	overlay.state.pending = false
end

-- Secure hooks only; native behaviour is observed, never replaced.
function overlay.InstallHooks()
	if overlay.state.hooksInstalled then return end
	local euf = ns.api.GetEUF()
	if not euf or type(hooksecurefunc) ~= "function" then return end
	local function reattach() overlay.Resolve() end
	for _, name in ipairs({ "UF_HealPredApply", "UF_AnchorHealPred", "UF_HealPredLayout" }) do
		if type(euf[name]) == "function" then
			local ok = pcall(hooksecurefunc, euf, name, reattach)
			if ok then ns.debug("hook installed: " .. name) end
		end
	end
	overlay.state.hooksInstalled = true
end

function overlay.ApplyPending()
	if overlay.state.pending then
		overlay.Resolve()
	end
end

------------------------------------------------------------------------------
-- rendering
------------------------------------------------------------------------------

function overlay.Hide(reason)
	local f = overlay.state.frame
	if f and f.Hide then f:Hide() end
	if reason then ns.session.lastSuppress = reason end
end

-- Max value for scaling. Prefer the native bar max (matches the native chain),
-- else readable max health, else a documented fallback.
local function resolveMax(ab)
	if ab and ab._predMy and ab._predMy.GetMinMaxValues then
		local ok, _min, max = pcall(ab._predMy.GetMinMaxValues, ab._predMy)
		if ok and ns.toNumber(max) and max > 0 then return max end
	end
	local health = ns.api.GetHealthNumbers and ns.api.GetHealthNumbers()
	if health and health.max and health.max > 0 then return health.max end
	return nil
end

local function applyColor(color)
	if not color then return end
	local f = overlay.state.frame
	if not f then return end
	if f.SetStatusBarColor then f:SetStatusBarColor(color[1], color[2], color[3]) end
end

function overlay.RenderValue(value, reason)
	if not ns.db or not ns.db.enabled then
		overlay.Hide("addon disabled")
		return
	end
	local ab = overlay.state.ab
	if not ab then
		overlay.Resolve()
		ab = overlay.state.ab
	end
	if not ab then
		overlay.Hide("no native prediction frame")
		return
	end
	local f = overlay.EnsureFrame()
	if not f then return end

	if not value or value <= 0 then
		overlay.Hide(reason or "nothing to append")
		return
	end
	local max = resolveMax(ab)
	if not max then
		overlay.Hide("no readable max for overlay scaling")
		return
	end
	-- copy principal native styling for texture continuity
	local info = ns.api.GetBarInfo(ab._predMy)
	if info and info.texture and f.SetStatusBarTexture then
		f:SetStatusBarTexture(info.texture)
	end
	local color = ns.db.overlayColor or { 1, 0.82, 0 }
	if ns.db.shareNativeStyle and info and info.color then color = info.color end
	if f.SetMinMaxValues then f:SetMinMaxValues(0, max) end
	if f.SetValue then f:SetValue(value) end
	if f.SetAlpha then f:SetAlpha(ns.db.alpha or 0.6) end
	applyColor(color)
	if f.Show then f:Show() end
end

------------------------------------------------------------------------------
-- periodic evaluation
------------------------------------------------------------------------------

function overlay.Tick()
	if not ns.db or not ns.db.enabled then
		overlay.Hide("addon disabled")
		return
	end
	if overlay.IsCombat() and not overlay.state.parent then
		overlay.state.pending = true
		return
	end
	if not overlay.state.ab then
		overlay.Resolve()
	end
	local fake = ns.session.fake
	if fake then
		local value = fake.value or fake.hot or 0
		local collector = ns.model.Evaluate(ns.now(), { fake = true, ab = overlay.state.ab })
		overlay.RenderValue(value, "fake test")
		if ns.db.debug then
			ns.debug(string.format("fake render value=%s native=%s hot=%s", tostring(value),
				tostring(collector.native and collector.native.total), tostring(collector.hotEstimate)))
		end
		return
	end
	local res = ns.model.Evaluate(ns.now(), { ab = overlay.state.ab })
	ns.session.lastStatus = res
	if res.added and res.added > 0 then
		overlay.RenderValue(res.added, res.reason)
	else
		overlay.Hide(res.reason)
	end
	if ns.db.debug then
		ns.debug(string.format("tick hot=%s native=%s added=%s reason=%s",
			tostring(res.hotEstimate), tostring(res.native and res.native.total),
			tostring(res.added), tostring(res.reason)))
	end
end

function overlay.Setup()
	ns.resetSession()
	if ns.overlay.Resolve then ns.overlay.Resolve() end
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(TICK_INTERVAL, function() ns.overlay.Tick() end)
	elseif type(CreateFrame) == "function" then
		local t = CreateFrame("Frame")
		local elapsed = 0
		t:SetScript("OnUpdate", function(_, dt)
			elapsed = elapsed + (dt or 0)
			if elapsed >= TICK_INTERVAL then
				elapsed = 0
				ns.overlay.Tick()
			end
		end)
	end
end
