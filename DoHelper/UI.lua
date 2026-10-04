-- DoHelper / UI.lua
-- Shared presentation for addon-owned widgets only. No vendor scans, secure
-- frame mutations, gameplay state, third-party assets or animation timers.
local _, ns = ...
local UI = {}
ns.ui = UI

UI.FONT = "Fonts\\ARIALN.TTF"
UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.colors = {
	window = { 0.035, 0.045, 0.065, 0.99 },
	panel = { 0.052, 0.068, 0.092, 1 },
	input = { 0.026, 0.037, 0.054, 1 },
	border = { 0.15, 0.20, 0.27, 1 },
	text = { 0.90, 0.94, 0.98, 1 },
	muted = { 0.60, 0.68, 0.77, 1 },
	accent = { 0.32, 0.83, 0.73, 1 },
	button = { 0.09, 0.13, 0.18, 1 },
	hover = { 0.13, 0.22, 0.28, 1 },
	selected = { 0.07, 0.22, 0.23, 1 },
	primary = { 0.10, 0.35, 0.33, 1 },
	danger = { 0.92, 0.52, 0.54, 1 },
}
local roles = { body = 12, muted = 11, section = 11, heading = 18, title = 24 }
local unpack = unpack or table.unpack

local function call(widget, method, ...)
	if widget and type(widget[method]) == "function" then return widget[method](widget, ...) end
end

function UI.Text(text, role)
	role = role or "body"
	call(text, "SetFont", UI.FONT, roles[role] or 12, "")
	call(text, "SetTextColor", unpack(UI.colors[role == "muted" and "muted" or role == "section" and "accent" or "text"]))
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
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); t:SetSize(width, height)
	return t
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
	call(frame, "SetBackdropColor", unpack(color or UI.colors.panel))
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
	call(c, "SetNormalTexture", ""); call(c, "SetPushedTexture", ""); call(c, "SetHighlightTexture", "")
	call(c, "SetCheckedTexture", "Interface\\Buttons\\UI-CheckBox-Check")
	local tick = call(c, "GetCheckedTexture")
	if tick then
		tick:ClearAllPoints(); tick:SetPoint("TOPLEFT", c, "TOPLEFT", 3, -3); tick:SetSize(20, 20)
		tick:SetVertexColor(unpack(UI.colors.accent))
	end
	return c
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
