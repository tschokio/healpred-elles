-- EllesmereUI_HoTPrediction / DebugWindow.lua
-- A lazy, copyable in-game diagnostic snapshot window.
--
-- Design constraints (see README):
--   * Created ONLY when the user opens it (/euihot window, /euihot debug window).
--   * Exactly one named addon-owned frame; no other new globals. The name is
--     registered with UISpecialFrames so Escape closes it.
--   * Hidden, never deleted, so it is reused and keeps its position while the
--     session lasts.
--   * No timers, no OnUpdate, no network, no frame scans. A snapshot is captured
--     only on Open/Refresh, so a live tick can never steal the user's selection.
--   * The EditBox is plain text (no |c/|r artifacts) and never contains a raw
--     secret value; editing it only edits the on-screen copy, it can never mutate
--     addon settings or learned data.
--
-- This file only builds the widget and assembles report text. The report text
-- itself comes from the shared, non-printing builders in Core.lua.

local addonName, ns = ...

-- The one named frame global we introduce. Everything else lives on `ns` or is
-- local to this file.
local WINDOW_NAME = "EllesmereUI_HoTPredictionDebugWindow"
local TITLE = "EllesmereUI HoTPrediction - debug snapshot"
local HINT = "Select All, then Ctrl+C to copy; Refresh captures a new snapshot (a snapshot is not live)."

-- Call a widget method if it exists, swallowing errors: the window must degrade
-- gracefully on a client that is missing an optional API instead of raising.
local function safe(obj, method, ...)
	if obj == nil then return nil end
	local ok, fn = pcall(function() return obj[method] end)
	if not ok or type(fn) ~= "function" then return nil end
	local ok2, res = pcall(fn, obj, ...)
	if ok2 then return res end
	return nil
end

------------------------------------------------------------------------------
-- snapshot text (public, non-printing)
------------------------------------------------------------------------------

-- A copyable snapshot: a compact one-line teststatus plus the full status with
-- rich internals FORCED on, irrespective of the persisted debug setting (which
-- is not changed). Both come from the shared builders, so neither prints chat.
function ns.BuildSnapshotReport()
	local ok, res = pcall(ns._BuildSnapshotReport)
	if ok and type(res) == "string" and res ~= "" then
		return ns.StripFormatting(res)
	end
	return ns.BuildStatusFallback(ok and "empty report" or res)
end

function ns._BuildSnapshotReport()
	local t = ns.toNumber(GetTime and GetTime() or nil)
	local tlabel = t and string.format("%.2f", t) or "unknown"
	local lines = {
		string.format("EllesmereUI_HoTPrediction v%s - diagnostic snapshot", tostring(ns.version)),
		string.format("captured t=%s (public GetTime seconds; a snapshot, not a live log)", tlabel),
		"copy: click Select All, then Ctrl+C (the operating system owns the clipboard).",
		"--- teststatus ---",
		ns.BuildTestStatusReport(),
		"--- status (forced internals) ---",
		ns.BuildStatusReport(true),
	}
	return table.concat(lines, "\n")
end

------------------------------------------------------------------------------
-- lazy window construction
------------------------------------------------------------------------------

local function ensureDebugWindow()
	if ns.debugWindow then return ns.debugWindow end
	if type(CreateFrame) ~= "function" then return nil end

	local parent = UIParent
	local f = CreateFrame("Frame", WINDOW_NAME, parent, "BackdropTemplate")
	if not f then return nil end
	ns.debugWindow = f

	safe(f, "SetSize", 600, 440)
	safe(f, "SetPoint", "CENTER", parent or UIParent, "CENTER", 0, 0)
	safe(f, "SetMovable", true)
	safe(f, "SetClampedToScreen", true)
	safe(f, "EnableMouse", true)
	safe(f, "SetFrameStrata", "DIALOG")
	safe(f, "SetToplevel", true)
	safe(f, "SetBackdrop", {
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = false, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	safe(f, "SetBackdropColor", 0.04, 0.05, 0.06, 0.97)
	safe(f, "SetBackdropBorderColor", 0.25, 0.65, 0.4, 1)
	safe(f, "RegisterForDrag", "LeftButton")
	safe(f, "SetScript", "OnDragStart", function(self) safe(self, "StartMoving") end)
	safe(f, "SetScript", "OnDragStop", function(self) safe(self, "StopMovingOrSizing") end)
	safe(f, "Hide")

	local title = safe(f, "CreateFontString", nil, "OVERLAY", "GameFontNormalLarge")
	if title then
		safe(title, "SetPoint", "TOPLEFT", f, "TOPLEFT", 12, -10)
		safe(title, "SetJustifyH", "LEFT")
		safe(title, "SetText", TITLE)
	end
	local hint = safe(f, "CreateFontString", nil, "OVERLAY", "GameFontHighlightSmall")
	if hint then
		safe(hint, "SetPoint", "TOPLEFT", f, "TOPLEFT", 12, -30)
		safe(hint, "SetPoint", "TOPRIGHT", f, "TOPRIGHT", -12, -30)
		safe(hint, "SetJustifyH", "LEFT")
		safe(hint, "SetText", HINT)
	end

	-- ScrollFrame + multiline EditBox: the text is selectable/copyable while
	-- staying scrollable for a long newline-delimited report.
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	safe(scroll, "SetPoint", "TOPLEFT", f, "TOPLEFT", 12, -52)
	safe(scroll, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 42)
	safe(scroll, "SetClipsChildren", true)
	safe(scroll, "EnableMouseWheel", true)
	safe(scroll, "SetScript", "OnMouseWheel", function(self, delta)
		local position = safe(self, "GetVerticalScroll") or 0
		local range = safe(self, "GetVerticalScrollRange") or 0
		safe(self, "SetVerticalScroll", math.max(0, math.min(range, position - delta * 32)))
	end)
	local edit = CreateFrame("EditBox", nil, scroll)
	safe(edit, "SetMultiLine", true)
	safe(edit, "SetAutoFocus", false)
	safe(edit, "SetMaxLetters", 0)
	if edit.SetFont then
		safe(edit, "SetFont", (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 11, "")
	end
	safe(edit, "SetTextInsets", 4, 4, 4, 4)
	safe(edit, "SetJustifyH", "LEFT")
	safe(edit, "SetJustifyV", "TOP")
	safe(edit, "SetWidth", 556)
	safe(edit, "SetPoint", "TOPLEFT", scroll, "TOPLEFT", 0, 0)
	safe(scroll, "SetScrollChild", edit)
	safe(edit, "SetScript", "OnEscapePressed", function() ns.CloseDebugWindow() end)

	-- Measure wrapped text with the same font instead of assuming the EditBox
	-- grows its scroll-child rectangle automatically on every supported client.
	local measure = safe(f, "CreateFontString", nil, "BACKGROUND", "GameFontHighlightSmall")
	if measure then
		safe(measure, "SetFont", STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
		safe(measure, "SetWordWrap", true)
		safe(measure, "Hide")
	end
	local function sizeText()
		local width = safe(scroll, "GetWidth") or 556
		if width < 1 then width = 556 end
		safe(edit, "SetWidth", width)
		if measure then
			safe(measure, "SetWidth", math.max(1, width - 8))
			safe(measure, "SetText", safe(edit, "GetText") or "")
		end
		local height = measure and safe(measure, "GetStringHeight") or nil
		safe(edit, "SetHeight", math.max(safe(scroll, "GetHeight") or 346, (height or 346) + 12))
		safe(scroll, "UpdateScrollChildRect")
	end
	safe(edit, "SetScript", "OnTextChanged", sizeText)
	safe(scroll, "SetScript", "OnSizeChanged", sizeText)

	f.editBox = edit
	f.scrollFrame = scroll

	-- Hiding (button, Escape, or /reload) always clears the selection/focus so no
	-- invisible select-all text stays armed on a hidden frame.
	safe(f, "SetScript", "OnHide", function()
		local eb = ns.debugWindow and ns.debugWindow.editBox
		safe(eb, "ClearFocus")
	end)

	local function button(label, offset, onclick)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		safe(b, "SetSize", 90, 22)
		safe(b, "SetPoint", "BOTTOMRIGHT", f, "BOTTOMRIGHT", offset, 12)
		safe(b, "SetText", label)
		safe(b, "SetScript", "OnClick", onclick)
		return b
	end
	button("Select All", -216, function() ns.SelectAllDebugWindow() end)
	button("Refresh", -114, function() ns.RefreshDebugWindow() end)
	button("Close", -12, function() ns.CloseDebugWindow() end)

	-- Escape integration: register the one named frame once.
	if type(UISpecialFrames) == "table" then
		local present = false
		for i = 1, #UISpecialFrames do
			if UISpecialFrames[i] == WINDOW_NAME then present = true break end
		end
		if not present then UISpecialFrames[#UISpecialFrames + 1] = WINDOW_NAME end
	end

	return f
end

------------------------------------------------------------------------------
-- public open/close/refresh/select-all
------------------------------------------------------------------------------

-- Open creates lazily on the first call, then reuses the same frame.
function ns.OpenDebugWindow()
	local f = ensureDebugWindow()
	if not f then
		ns.print("debug window unavailable: this client cannot create frames.")
		return nil
	end
	ns.RefreshDebugWindow()
	safe(f, "Show")
	return f
end

-- Hide (not delete); position is retained for the rest of the session.
function ns.CloseDebugWindow()
	local f = ns.debugWindow
	if not f then return false end
	safe(f, "Hide")
	return true
end

-- Capture a fresh snapshot: drop the stale selection/focus first, write the full
-- report, then reset the scroll to the top.
function ns.RefreshDebugWindow()
	local f = ns.debugWindow
	if not f then return nil end
	local eb = f.editBox
	if not eb then return nil end
	safe(eb, "ClearFocus")
	safe(eb, "SetCursorPosition", 0)
	local text = ns.BuildSnapshotReport()
	safe(eb, "SetText", text)
	safe(eb, "SetCursorPosition", 0)
	safe(f.scrollFrame, "SetVerticalScroll", 0)
	return text
end

-- Focus the EditBox and highlight everything so native Ctrl+A/Ctrl+C work.
function ns.SelectAllDebugWindow()
	local f = ns.debugWindow
	if not f then return false end
	local eb = f.editBox
	if not eb then return false end
	safe(eb, "SetFocus")
	safe(eb, "HighlightText")
	return true
end
