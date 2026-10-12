-- Graphics CVars belong to the game, not DoHelper's SavedVariables. No startup
-- writes, timers, console execution or automatic reapplication on login.
local _, ns = ...
local G = { entries = {}, original = {} }
ns.graphics = G
local UI = ns.ui
local definitions = {
	{ "groundEffectDensity", "Ground clutter density", 16, 256, 256, "Higher: more grass, flowers and small rocks." },
	{ "groundEffectFade", "Ground clutter fade distance", 0, 600, 600, "Higher: fades later; coordinate with clutter distance." },
	{ "groundEffectDist", "Ground clutter distance", 32, 600, 600, "Higher: renders ground clutter farther away." },
	{ "lodObjectFadeScale", "Object fade scale", 50, 300, 300, "Higher: keeps distant objects visible longer." },
	{ "lodObjectCullSize", "Object culling size", 1, 100, 1, "LOWER: retains smaller objects. Higher: fewer objects." },
	{ "terrainLodDist", "Terrain detail distance", 128, 5248, 5248, "Higher: keeps detailed terrain farther away." },
	{ "ResampleAlwaysSharpen", "Always sharpen", 0, 1, 1, "Off reverses sharpening; effect depends on resampling." },
	{ "reflectionMode", "Water reflection mode", 0, 4, 3, "Higher modes add reflection detail; client support and effects vary." },
}
local byName = {}
for _, row in ipairs(definitions) do
	local entry = { name = row[1], title = row[2], min = row[3], max = row[4], preset = row[5], help = row[6] }
	G.entries[#G.entries + 1] = entry
	byName[entry.name] = entry
end

local PRESETS = {
	dense = {}, -- Filled from each entry's high-detail preset above.
	balanced = {
		groundEffectDensity = 128,
		groundEffectFade = 300,
		groundEffectDist = 316,
		lodObjectFadeScale = 175,
		lodObjectCullSize = 8,
		terrainLodDist = 2688,
		ResampleAlwaysSharpen = 1,
		reflectionMode = 2,
	},
	herbs = {
		groundEffectDensity = 16,
		groundEffectFade = 0,
		groundEffectDist = 32,
		lodObjectFadeScale = 300,
		lodObjectCullSize = 1,
		terrainLodDist = 128,
		ResampleAlwaysSharpen = 0,
		reflectionMode = 0,
	},
	beyondUltra = {
		-- Supported overlap from the community's Forever macro guide. Other
		-- macro CVars remain excluded until verified in this client's CVar API.
		groundEffectDensity = 256,
		groundEffectFade = 600,
		groundEffectDist = 500,
		lodObjectFadeScale = 300,
		lodObjectCullSize = 1,
		terrainLodDist = 2000,
		reflectionMode = 4,
	},
}
for _, entry in ipairs(G.entries) do PRESETS.dense[entry.name] = entry.preset end
G.presets = PRESETS

local function api(name)
	if C_CVar and type(C_CVar[name]) == "function" then return C_CVar[name] end
	if type(_G[name]) == "function" then return _G[name] end
end

local function number(value)
	if ns.isSecret(value) then return nil end
	if type(value) ~= "string" and type(value) ~= "number" then return nil end
	return ns.toNumber(tonumber(value))
end

function G.Read(name, defaults)
	if not byName[name] then return nil end
	local fn = api(defaults and "GetCVarDefault" or "GetCVar")
	if not fn then return nil end
	local ok, value = pcall(fn, name)
	if not ok then return nil end
	return number(value)
end

function G.Export()
	local lines = {}
	for _, entry in ipairs(G.entries) do
		local value = G.Read(entry.name)
		if value then lines[#lines + 1] = "/console " .. entry.name .. " " .. string.format("%.10g", value) end
	end
	return table.concat(lines, "\n"), #lines
end

-- Preflight every draft before writing; verify readback rather than assuming
-- SetCVar's nil return means success. Best-effort rollback on clamp/refusal.
function G.Apply(values, restoring)
	if ns.api and ns.api.InCombat() then return false, "Change graphics out of combat; nothing changed." end
	local set = api("SetCVar")
	if not set then return false, "This client cannot set CVars; nothing changed." end
	if type(values) ~= "table" then return false, "Invalid graphics draft; nothing changed." end
	local pending = {}
	for name, value in pairs(values) do
		local entry = byName[name]
		local n = number(value)
		if not entry or not n or (not restoring and n ~= G.Read(name) and (n < entry.min or n > entry.max or n ~= math.floor(n))) then
			return false, "Invalid value or range for " .. tostring(name) .. "; nothing changed."
		end
	end
	for _, entry in ipairs(G.entries) do
		local value = values[entry.name]
		if value ~= nil then
			local old = G.Read(entry.name)
			if old == nil then return false, entry.name .. " is unavailable; nothing changed." end
			if number(value) ~= old then pending[#pending + 1] = { name = entry.name, value = number(value), old = old } end
		end
	end
	if #pending == 0 then return true, "No graphics changes needed. Current values kept." end
	local touched = {}
	for _, item in ipairs(pending) do
		touched[#touched + 1] = item
		if G.original[item.name] == nil then G.original[item.name] = item.old end
		local ok, result = pcall(set, item.name, tostring(item.value))
		local readback = G.Read(item.name)
		if not ok or result == false or readback ~= item.value then
			local rolledBack = true
			for i = #touched, 1, -1 do
				local old = touched[i]
				pcall(set, old.name, tostring(old.old))
				if G.Read(old.name) ~= old.old then rolledBack = false end
			end
			local detail = not ok and "setter raised an error" or result == false and "setter reported failure"
				or readback == nil and "readback is unavailable" or ("read back " .. tostring(readback))
			return false, item.name .. " could not hold " .. tostring(item.value) .. " (" .. detail .. "). " ..
				(rolledBack and "Previous values restored." or "Rollback incomplete; check current values and use Restore original.")
		end
	end
	return true, "Graphics applied and verified. Higher detail can lower FPS. Some effects need a zone change or game restart."
end

function G.Restore()
	return G.Apply(G.original, true)
end

function G.BuildOptionsUI(f)
	local page = CreateFrame("Frame", nil, f)
	page:SetSize(764, 540)
	page:SetPoint("TOPLEFT", f, "TOPLEFT", f.contentX, f.contentY)
	f.graphicsPage = page
	UI.Background(page, -3, 4, 764, 540)
	local message = UI.Label(page, "Draft only: click Apply graphics to change the game.", 10, -496, 736, "muted")
	page.message, page.rows = message, {}
	local draft, refreshing = {}, false
	local function button(key, text, x, y, width, action)
		local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		b:SetSize(width, 24); b:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
		b:SetText(text); b:SetScript("OnClick", action); UI.Button(b)
		f.controls[key] = b
		return b
	end
	local function display(entry, value)
		local row = page.rows[entry.name]
		row.input:SetText(value == nil and "N/A" or tostring(value))
		if row.slider then row.slider:SetValue(math.max(entry.min, math.min(entry.max, value or entry.min))) end
		if row.toggle then row.toggle:SetChecked(value == 1) end
		if row.mode then row.mode:SetText(value == nil and "Unavailable" or ("Mode " .. value)) end
	end
	for i, entry in ipairs(G.entries) do
		local y = -8 - (i - 1) * 48
		local row = {}
		page.rows[entry.name] = row
		UI.Label(page, entry.title .. " (" .. entry.min .. "-" .. entry.max .. ")", 10, y, 268)
		UI.Label(page, entry.help, 10, y - 19, 465, "muted")
		local input = CreateFrame("EditBox", nil, page, "BackdropTemplate")
		input:SetSize(65, 22); input:SetPoint("TOPLEFT", page, "TOPLEFT", 410, y + 3)
		input:SetAutoFocus(false); input:SetMaxLetters(12); UI.Input(input)
		input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		input:SetScript("OnTextChanged", function(self)
			if refreshing then return end
			draft[entry.name] = self:GetText()
			local value = number(draft[entry.name])
			if value and value >= entry.min and value <= entry.max and value == math.floor(value) then
				refreshing = true
				if row.slider then row.slider:SetValue(value) end
				if row.toggle then row.toggle:SetChecked(value == 1) end
				if row.mode then row.mode:SetText("Mode " .. value) end
				refreshing = false
			end
			message:SetText("Draft only. Click Apply graphics when ready.")
		end)
		row.input = input
		f.controls["graphics_" .. entry.name] = input
		if entry.name == "ResampleAlwaysSharpen" then
			local c = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
			c:SetSize(26, 26); c:SetPoint("TOPLEFT", page, "TOPLEFT", 280, y + 5); UI.Checkbox(c)
			c:SetScript("OnClick", function(self) input:SetText(self:GetChecked() and "1" or "0") end)
			row.toggle = c
		elseif entry.name == "reflectionMode" then
			row.mode = button("graphicsReflection", "Mode 0", 280, y + 3, 112, function()
				local value = number(draft[entry.name]) or 0
				value = (math.floor(value) + 1) % (entry.max + 1)
				input:SetText(tostring(value)); row.mode:SetText("Mode " .. value)
			end)
		else
			local slider = CreateFrame("Slider", nil, page)
			slider:SetSize(112, 18); slider:SetPoint("TOPLEFT", page, "TOPLEFT", 280, y)
			slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(entry.min, entry.max)
			UI.Background(slider, 0, -7, 112, 4)
			local thumb = slider:CreateTexture(nil, "ARTWORK")
			thumb:SetTexture(UI.WHITE); thumb:SetSize(10, 18)
			UI.Tint(thumb, "accent"); slider:SetThumbTexture(thumb)
			slider:SetValueStep(1)
			if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
			slider:SetScript("OnValueChanged", function(_, value)
				if not refreshing then input:SetText(tostring(math.floor(value + 0.5))) end
			end)
			row.slider = slider
		end
	end
	UI.Rect(page, 492, -6, 1, 414, UI.colors.border)
	UI.Label(page, "SHARE CURRENT SETTINGS", 508, -8, 240, "section")
	UI.Label(page, "Export reads the game, not your draft. Select all, Ctrl+C, then send the commands. Run each line separately in chat.", 508, -32, 240, "muted")
	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetSize(220, 232); scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 508, -88)
	local share = CreateFrame("EditBox", nil, scroll, "BackdropTemplate")
	share:SetSize(220, 232); share:SetMultiLine(true); share:SetAutoFocus(false)
	share:SetMaxLetters(4096); share:SetTextInsets(8, 8, 8, 8); UI.Input(share, true)
	scroll:SetScrollChild(share)
	share:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local measure = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	measure:SetWidth(204); measure:SetWordWrap(true); UI.Text(measure); measure:Hide()
	-- User edits are copy-only: this field is never interpreted or executed.
	share:SetScript("OnTextChanged", function(self)
		measure:SetText(self:GetText())
		self:SetHeight(math.max(232, measure:GetStringHeight() + 24)); scroll:UpdateScrollChildRect()
	end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
	end)
	f.controls.graphicsExportText, page.share = share, share
	button("graphicsExport", "Export current", 508, -334, 116, function()
		local text, count = G.Export()
		share:ClearFocus(); share:SetText(text); scroll:SetVerticalScroll(0)
		message:SetText("Exported " .. count .. "/8 readable CVars. Ctrl+C copies selected text; unsupported CVars are omitted.")
	end)
	button("graphicsSelectAll", "Select all", 632, -334, 116, function() share:SetFocus(); share:HighlightText() end)
	UI.Label(page, "Ranges are practical controls, not guaranteed Forever limits. Unsupported settings show N/A. The game may clamp values. Graphics options or other addons can overwrite them.", 508, -370, 240, "muted")
	local function stage(source)
		refreshing = true
		for _, entry in ipairs(G.entries) do
			if G.Read(entry.name) ~= nil then
				local value = source(entry)
				if value ~= nil then draft[entry.name] = value; display(entry, value) end
			end
		end
		refreshing = false
	end
	button("graphicsPreset", "Dense + realistic", 10, -394, 112, function()
		stage(function(entry) return PRESETS.dense[entry.name] end)
		message:SetText("Dense, high-detail settings staged. Expect a substantial performance cost; click Apply graphics to use them.")
	end)
	button("graphicsBalancedPreset", "Balanced", 128, -394, 112, function()
		stage(function(entry) return PRESETS.balanced[entry.name] end)
		message:SetText("Balanced scenery staged. Click Apply graphics to use it.")
	end)
	button("graphicsHerbPreset", "Herb visibility", 246, -394, 112, function()
		stage(function(entry) return PRESETS.herbs[entry.name] end)
		message:SetText("Minimum ground clutter staged; small and distant objects are preserved. Some effects cannot be fully disabled with these CVars.")
	end)
	button("graphicsBeyondUltra", "Beyond Ultra", 364, -394, 112, function()
		stage(function(entry) return PRESETS.beyondUltra[entry.name] end)
		message:SetText("Supported Beyond Ultra macro settings staged. Unverified macro CVars are excluded; click Apply graphics to use supported values.")
	end)
	button("graphicsDefaults", "Stage game defaults", 10, -426, 148, function()
		local missing = 0
		stage(function(entry)
			local value = G.Read(entry.name, true)
			if value == nil then missing = missing + 1 end
			return value
		end)
		message:SetText("Available game defaults staged; " .. missing .. " defaults unavailable (draft kept). Click Apply graphics.")
	end)
	button("graphicsRefresh", "Read current", 166, -426, 148, function()
		page.Refresh(); message:SetText("Draft replaced with current game values; nothing changed.")
	end)
	UI.Button(button("graphicsApply", "Apply graphics", 10, -460, 148, function()
		local ok, status = G.Apply(draft)
		page.Refresh(not ok)
		if not ok then status = status .. " Draft kept so you can adjust the named setting or use Read current." end
		message:SetText(status)
	end), "primary")
	button("graphicsRestore", "Restore original", 166, -460, 148, function()
		local _, status = G.Restore()
		page.Refresh(); message:SetText(status)
	end)
	UI.Label(page, "Original backup lasts this login only.\nNo automatic changes on login.", 322, -458, 400, "muted")
	function page.Refresh(keepDraft)
		if not keepDraft then draft = {} end
		refreshing = true
		for _, entry in ipairs(G.entries) do
			local current = G.Read(entry.name)
			local value = keepDraft and draft[entry.name] or current
			local row = page.rows[entry.name]
			if not keepDraft and current ~= nil then draft[entry.name] = current end
			display(entry, value)
			row.input:SetEnabled(current ~= nil)
			if current == nil then row.input:ClearFocus() end
			if row.slider then row.slider:EnableMouse(current ~= nil) end
			if row.toggle then row.toggle:SetEnabled(current ~= nil) end
			if row.mode then row.mode:SetEnabled(current ~= nil) end
		end
		refreshing = false
	end
	page.Refresh()
end
