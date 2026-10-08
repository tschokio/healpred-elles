-- DoHelper / UI.lua
-- Shared presentation for addon-owned widgets only. No vendor scans, secure
-- frame mutations, gameplay state, third-party assets or animation timers.
local _, ns = ...
local UI = {}
ns.ui = UI

UI.FONT = "Fonts\\ARIALN.TTF"
UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.themes = {
	classic = {
		label = "Classic parchment",
		window = { 0.12, 0.085, 0.045, 0.98 }, panel = { 0.18, 0.13, 0.07, 1 },
		input = { 0.075, 0.052, 0.03, 1 }, border = { 0.50, 0.34, 0.12, 1 },
		text = { 0.95, 0.87, 0.69, 1 }, muted = { 0.72, 0.60, 0.40, 1 },
		accent = { 1, 0.73, 0.25, 1 }, button = { 0.22, 0.15, 0.07, 1 },
		hover = { 0.34, 0.23, 0.09, 1 }, selected = { 0.40, 0.26, 0.08, 1 },
		primary = { 0.50, 0.31, 0.09, 1 }, danger = { 0.76, 0.28, 0.16, 1 },
		noteWindow = { 0.10, 0.07, 0.04, 0.97 }, noteEditor = { 0.035, 0.025, 0.015, 0.92 },
		noteText = { 0.92, 0.85, 0.70, 1 }, noteTitle = { 1, 0.73, 0.25, 1 },
		noteBorder = { 0.50, 0.34, 0.12, 1 },
	},
	ember = {
		label = "Ember and iron",
		window = { 0.075, 0.055, 0.05, 0.99 }, panel = { 0.13, 0.09, 0.075, 1 },
		input = { 0.04, 0.03, 0.027, 1 }, border = { 0.46, 0.25, 0.14, 1 },
		text = { 0.91, 0.86, 0.80, 1 }, muted = { 0.66, 0.57, 0.52, 1 },
		accent = { 0.93, 0.48, 0.24, 1 }, button = { 0.19, 0.12, 0.09, 1 },
		hover = { 0.30, 0.17, 0.11, 1 }, selected = { 0.37, 0.18, 0.09, 1 },
		primary = { 0.55, 0.22, 0.10, 1 }, danger = { 0.78, 0.28, 0.18, 1 },
		noteWindow = { 0.07, 0.05, 0.045, 0.98 }, noteEditor = { 0.025, 0.02, 0.018, 0.94 },
		noteText = { 0.91, 0.84, 0.76, 1 }, noteTitle = { 0.96, 0.53, 0.27, 1 },
		noteBorder = { 0.46, 0.25, 0.14, 1 },
	},
	neutral = {
		label = "Neutral charcoal",
		window = { 0.08, 0.08, 0.075, 0.99 }, panel = { 0.14, 0.14, 0.13, 1 },
		input = { 0.035, 0.035, 0.033, 1 }, border = { 0.37, 0.34, 0.27, 1 },
		text = { 0.91, 0.90, 0.86, 1 }, muted = { 0.67, 0.65, 0.58, 1 },
		accent = { 0.85, 0.69, 0.40, 1 }, button = { 0.17, 0.16, 0.14, 1 },
		hover = { 0.25, 0.23, 0.19, 1 }, selected = { 0.31, 0.27, 0.19, 1 },
		primary = { 0.40, 0.30, 0.16, 1 }, danger = { 0.72, 0.32, 0.24, 1 },
		noteWindow = { 0.07, 0.07, 0.065, 0.98 }, noteEditor = { 0.025, 0.025, 0.023, 0.94 },
		noteText = { 0.90, 0.88, 0.82, 1 }, noteTitle = { 0.88, 0.70, 0.42, 1 },
		noteBorder = { 0.37, 0.34, 0.27, 1 },
	},
	original = {
		label = "Original teal",
		window = { 0.035, 0.045, 0.065, 0.99 }, panel = { 0.052, 0.068, 0.092, 1 },
		input = { 0.026, 0.037, 0.054, 1 }, border = { 0.15, 0.20, 0.27, 1 },
		text = { 0.90, 0.94, 0.98, 1 }, muted = { 0.60, 0.68, 0.77, 1 },
		accent = { 0.32, 0.83, 0.73, 1 }, button = { 0.09, 0.13, 0.18, 1 },
		hover = { 0.13, 0.22, 0.28, 1 }, selected = { 0.07, 0.22, 0.23, 1 },
		primary = { 0.10, 0.35, 0.33, 1 }, danger = { 0.92, 0.52, 0.54, 1 },
		noteWindow = { 0.05, 0.07, 0.10, 0.85 }, noteEditor = { 0, 0, 0, 0.35 },
		noteText = { 0.90, 0.94, 0.98, 1 }, noteTitle = { 0.32, 0.83, 0.73, 1 },
		noteBorder = { 0.20, 0.30, 0.34, 1 },
	},
}
UI.colors = {}
local colorRoles = { "window", "panel", "input", "border", "text", "muted", "accent", "button", "hover", "selected", "primary", "danger", "noteWindow", "noteEditor", "noteText", "noteTitle", "noteBorder" }
local paletteRoles = { "window", "panel", "border", "text", "accent" }
local customRoles = { window = true, panel = true, text = true, accent = true, border = true }
local textColors = { body = "text", heading = "text", title = "text", muted = "muted", section = "accent" }
local rectRoles, surfaceRoles = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local tintedTextures = setmetatable({}, { __mode = "k" })
local textRoles, buttonWidgets = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local inputWidgets, checkWidgets = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local roles = { body = 12, muted = 11, section = 11, heading = 18, title = 24 }
local unpack = unpack or table.unpack

local function call(widget, method, ...)
	if widget and type(widget[method]) == "function" then return widget[method](widget, ...) end
end

function UI.Text(text, role)
	role = role or "body"
	textRoles[text] = textColors[role] or "text"
	call(text, "SetFont", UI.FONT, roles[role] or 12, "")
	call(text, "SetTextColor", unpack(UI.colors[textRoles[text]]))
	call(text, "SetShadowOffset", 0, 0)
	return text
end

function UI.Label(parent, text, x, y, width, role)
	local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	l:SetWidth(width or 480); l:SetJustifyH("LEFT"); l:SetWordWrap(true)
	l:SetText(text)
	return UI.Text(l, role)
end

function UI.Rect(parent, x, y, width, height, color, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(UI.WHITE); t:SetVertexColor(unpack(color))
	for key, value in pairs(UI.colors) do if value == color then rectRoles[t] = key; break end end
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); t:SetSize(width, height)
	return t
end

function UI.Tint(texture, role)
	if not texture then return texture end
	tintedTextures[texture] = role
	call(texture, "SetVertexColor", unpack(UI.colors[role] or UI.colors.accent))
	return texture
end

-- Same-frame decoration: it cannot cover labels or intercept mouse input.
function UI.Background(parent, x, y, width, height)
	local border = UI.Rect(parent, x - 1, y + 1, width + 2, height + 2, UI.colors.border)
	local fill = UI.Rect(parent, x, y, width, height, UI.colors.panel, "BORDER")
	parent.background = fill
	return fill, border
end

function UI.Surface(frame, color)
	call(frame, "SetBackdrop", { bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
	local bg = color or UI.colors.panel
	local bgRole
	for key, value in pairs(UI.colors) do if value == bg then bgRole = key; break end end
	surfaceRoles[frame] = bgRole or "panel"
	call(frame, "SetBackdropColor", unpack(bg))
	call(frame, "SetBackdropBorderColor", unpack(UI.colors.border))
end

function UI.Window(frame)
	UI.Surface(frame, UI.colors.window)
	if not frame.uiTopLine then
		frame.uiTopLine = UI.Rect(frame, 1, -1, frame:GetWidth() - 2, 2, UI.colors.accent, "BORDER")
	end
end

local function hook(widget, event, fn)
	if widget.HookScript then widget:HookScript(event, fn) else
		local old = widget:GetScript(event)
		widget:SetScript(event, function(...) if old then old(...) end; fn(...) end)
	end
end

function UI.PaintButton(b)
	if not b.uiFill then return end
	local enabled = not b.IsEnabled or b:IsEnabled()
	local color = UI.colors.button
	if b.uiSelected then color = UI.colors.selected
	elseif b.uiHover and enabled then color = UI.colors.hover
	elseif b.uiTone == "primary" then color = UI.colors.primary end
	b.uiFill:SetVertexColor(unpack(color))
	b.uiBorder:SetVertexColor(unpack(b.uiSelected and UI.colors.accent or UI.colors.border))
	b.uiIndicator:SetShown(b.uiSelected == true)
	call(b.uiText, "SetTextColor", unpack(not enabled and UI.colors.muted
		or b.uiTone == "danger" and UI.colors.danger or UI.colors.text))
	call(b.uiFill, "SetAlpha", enabled and 1 or 0.5)
end

function UI.Button(b, tone)
	b.uiTone = tone or b.uiTone
	buttonWidgets[b] = true
	if not b.uiFill then
		-- Remove parchment/gold template artwork, preserving native button input.
		for _, method in ipairs({ "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture" }) do
			call(b, method, "")
		end
		b.uiFill, b.uiBorder = UI.Background(b, 1, -1, b:GetWidth() - 2, b:GetHeight() - 2)
		b.uiIndicator = UI.Rect(b, 0, 0, 3, b:GetHeight(), UI.colors.accent, "ARTWORK")
		local text = call(b, "GetFontString")
		if not text then
			text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			call(b, "SetFontString", text)
			text:SetText(b:GetText() or "")
		end
		b.uiText = text
		text:ClearAllPoints()
		text:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -(b:GetHeight() - 12) / 2)
		text:SetWidth(b:GetWidth() - 8); text:SetJustifyH("CENTER"); text:SetWordWrap(false)
		UI.Text(text)
		hook(b, "OnEnter", function(self) self.uiHover = true; UI.PaintButton(self) end)
		hook(b, "OnLeave", function(self) self.uiHover = false; UI.PaintButton(self) end)
		hook(b, "OnEnable", UI.PaintButton)
		hook(b, "OnDisable", UI.PaintButton)
	end
	UI.PaintButton(b)
	return b
end

function UI.Selected(b, value)
	if not b then return end
	b.uiSelected = value and true or false
	UI.PaintButton(b)
end

function UI.InputState(e)
	local enabled = not e.IsEnabled or e:IsEnabled()
	local focused = e.HasFocus and e:HasFocus()
	call(e, "SetBackdropBorderColor", unpack(focused and enabled and UI.colors.accent or UI.colors.border))
end

function UI.Input(e, multiline)
	if e.uiInput then return e end
	e.uiInput = true
	inputWidgets[e] = true
	UI.Surface(e, UI.colors.input)
	UI.Text(e)
	if not multiline then call(e, "SetTextInsets", 8, 8, 0, 0) end
	hook(e, "OnEditFocusGained", UI.InputState)
	hook(e, "OnEditFocusLost", UI.InputState)
	return e
end

function UI.Checkbox(c)
	if c.uiCheck then return c end
	c.uiCheck = UI.Background(c, 5, -5, 16, 16)
	checkWidgets[c] = true
	call(c, "SetNormalTexture", ""); call(c, "SetPushedTexture", ""); call(c, "SetHighlightTexture", "")
	call(c, "SetCheckedTexture", "Interface\\Buttons\\UI-CheckBox-Check")
	local tick = call(c, "GetCheckedTexture")
	if tick then
		tick:ClearAllPoints(); tick:SetPoint("TOPLEFT", c, "TOPLEFT", 3, -3); tick:SetSize(20, 20)
		tick:SetVertexColor(unpack(UI.colors.accent))
	end
	return c
end

local function applyPalette(name, base, custom)
	if ns.isSecret(name) or type(name) ~= "string" then name = "classic" end
	if ns.isSecret(base) or type(base) ~= "string" or not UI.themes[base] then base = "classic" end
	if ns.isSecret(custom) or type(custom) ~= "table" then custom = nil end
	local theme = UI.themes[name]
	if name == "custom" then theme = UI.themes[base] or UI.themes.classic end
	if not theme then name = "classic"; theme = UI.themes.classic end
	for _, key in ipairs(colorRoles) do
		local value = theme[key]
		local supplied = custom and custom[key]
		if name == "custom" and customRoles[key] and not ns.isSecret(supplied) and type(supplied) == "table" then
			value = supplied
		elseif name == "custom" and custom then
			local source = key == "noteWindow" and "window"
				or key == "noteEditor" and "panel"
				or key == "noteText" and "text"
				or key == "noteTitle" and "accent"
				or key == "noteBorder" and "border"
			if source and not ns.isSecret(custom[source]) and type(custom[source]) == "table" then
				local alpha = theme[key] and theme[key][4] or 1
				value = { custom[source][1], custom[source][2], custom[source][3], alpha }
			end
		end
		local color = {}
		for i = 1, 4 do
			local n = ns.toNumber(type(value) == "table" and value[i] or nil)
			if n == nil or n < 0 or n > 1 then n = (theme[key] and theme[key][i]) or (i == 4 and 1 or 0) end
			color[i] = n
		end
		UI.colors[key] = color
	end
	UI.currentSkin = name
	UI.currentSkinBase = name == "custom" and base or name
	for texture, role in pairs(rectRoles) do call(texture, "SetVertexColor", unpack(UI.colors[role])) end
	for texture, role in pairs(tintedTextures) do call(texture, "SetVertexColor", unpack(UI.colors[role] or UI.colors.accent)) end
	for frame, role in pairs(surfaceRoles) do
		call(frame, "SetBackdropColor", unpack(UI.colors[role] or UI.colors.panel))
		call(frame, "SetBackdropBorderColor", unpack(UI.colors.border))
	end
	for text, role in pairs(textRoles) do call(text, "SetTextColor", unpack(UI.colors[role] or UI.colors.text)) end
	for button in pairs(buttonWidgets) do UI.PaintButton(button) end
	for input in pairs(inputWidgets) do UI.Surface(input, UI.colors.input); UI.Text(input) end
	for checkbox in pairs(checkWidgets) do
		local checked = call(checkbox, "GetCheckedTexture")
		call(checked, "SetVertexColor", unpack(UI.colors.accent))
	end
	if ns.notes and ns.notes.ApplyStyle then ns.notes.ApplyStyle() end
	local options = ns.optionsWindow
	if options then
		if options.RefreshCatalog then pcall(options.RefreshCatalog, true) end
		if options.weaponPage and options.weaponPage.Refresh then pcall(options.weaponPage.Refresh) end
		if options.graphicsPage and options.graphicsPage.Refresh then pcall(options.graphicsPage.Refresh) end
	end
	return true
end

function UI.SetSkin(name, custom, base)
	if ns.isSecret(name) or type(name) ~= "string" then return false, "Choose a known theme." end
	if name ~= "custom" and not UI.themes[name] then return false, "Choose a known theme." end
	if name == "custom" and (ns.isSecret(base) or type(base) ~= "string" or not UI.themes[base]) then base = "classic" end
	local normalized
	if name == "custom" then
		if ns.isSecret(custom) or type(custom) ~= "table" then custom = {} end
		local fallback = UI.themes[base]
		normalized = {}
		for _, role in ipairs(paletteRoles) do
			normalized[role] = {}
			local supplied = custom[role]
			if ns.isSecret(supplied) then return false, "Custom colors must be RGB values from 0 to 1." end
			for i = 1, 3 do
				local n = ns.toNumber(type(supplied) == "table" and supplied[i] or nil)
				if supplied ~= nil and (n == nil or n < 0 or n > 1) then
					return false, "Custom colors must be RGB values from 0 to 1."
				end
				normalized[role][i] = n or fallback[role][i]
			end
		end
		custom = normalized
	end
	if ns.db then
		ns.db.uiSkin = name
		ns.db.uiSkinBase = name == "custom" and base or name
		if name == "custom" then
			ns.db.uiSkinCustom = normalized
		end
	end
	return applyPalette(name, base, normalized or custom)
end

function UI.ApplySavedSkin()
	local db = ns.db or {}
	local name = not ns.isSecret(db.uiSkin) and type(db.uiSkin) == "string" and db.uiSkin or "classic"
	local base = not ns.isSecret(db.uiSkinBase) and type(db.uiSkinBase) == "string" and db.uiSkinBase or "classic"
	local custom = not ns.isSecret(db.uiSkinCustom) and type(db.uiSkinCustom) == "table" and db.uiSkinCustom or nil
	return applyPalette(name, base, custom)
end

function UI.Palette(name, base, custom)
	if ns.isSecret(name) or type(name) ~= "string" then name = "classic" end
	if ns.isSecret(base) or type(base) ~= "string" or not UI.themes[base] then base = "classic" end
	if ns.isSecret(custom) or type(custom) ~= "table" then custom = nil end
	local theme = UI.themes[name == "custom" and (base or "classic") or name] or UI.themes.classic
	local result = {}
	for _, role in ipairs(paletteRoles) do
		local value = name == "custom" and custom and customRoles[role] and custom[role] or nil
		if ns.isSecret(value) then value = nil end
		value = value or theme[role]
		result[role] = {}
		for i = 1, 3 do
			local n = ns.toNumber(type(value) == "table" and value[i] or nil)
			result[role][i] = n and n >= 0 and n <= 1 and n or theme[role][i]
		end
	end
	return result
end

-- Fit each settings/dialog root on open, without shrinking saved note sizes or
-- running a screen-size poll. UIParent dimensions are already in UI coordinates.
function UI.FitWindow(f)
	if not UIParent or not f.SetScale then return end
	local width, height = ns.toNumber(UIParent:GetWidth()), ns.toNumber(UIParent:GetHeight())
	if width and height and width > 32 and height > 32 then
		f:SetScale(math.min(1, (width - 32) / f:GetWidth(), (height - 32) / f:GetHeight()))
	end
end
