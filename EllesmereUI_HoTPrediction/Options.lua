-- Addon-owned configuration UI. No libraries, native frame edits or idle timers.
-- The only OnUpdate exists while the user drags the minimap button.
local addonName, ns = ...
local WINDOW = "EllesmereUI_HoTPredictionOptions"

local function safe(obj, method, ...)
	if obj and type(obj[method]) == "function" then return obj[method](obj, ...) end
end

local function label(parent, text, x, y, width)
	local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	l:SetWidth(width or 490)
	l:SetJustifyH("LEFT")
	l:SetText(text)
	return l
end

function ns.UpdateMinimapButton()
	local b = ns.minimapButton
	if not b then return end
	local angle = ns.toNumber(ns.db.minimapAngle) or 225
	angle = angle % 360
	ns.db.minimapAngle = angle
	local radians = angle * math.pi / 180
	local rx = (Minimap:GetWidth() / 2) + 8
	local ry = (Minimap:GetHeight() / 2) + 8
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * rx, math.sin(radians) * ry)
	b:SetShown(not ns.db.minimapHidden)
end

local function dragPosition()
	if not GetCursorPosition or not Minimap.GetCenter then return end
	local cx, cy = Minimap:GetCenter()
	if not cx or not cy then return end
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	x, y = x / scale - cx, y / scale - cy
	if x == 0 and y == 0 then return end
	local angle
	if math.atan2 then angle = math.atan2(y, x)
	elseif x == 0 then angle = y > 0 and math.pi / 2 or -math.pi / 2
	else
		angle = math.atan(y / x)
		if x < 0 then angle = angle + math.pi end
	end
	ns.db.minimapAngle = (angle * 180 / math.pi) % 360
	ns.UpdateMinimapButton()
end

function ns.InitOptions()
	-- A small entry in Blizzard's AddOns settings opens the same lazy window.
	-- Support modern Settings and the older Interface Options API if present.
	if not ns.optionsCategoryPanel and CreateFrame and ((Settings and Settings.RegisterCanvasLayoutCategory
		and Settings.RegisterAddOnCategory) or InterfaceOptions_AddCategory) then
		local panel = CreateFrame("Frame", nil, UIParent)
		panel.name = "EllesmereUI HoT Prediction"
		label(panel, panel.name, 16, -16)
		label(panel, "Configure the player healing overlay. Settings also open via /euihot options.", 16, -44)
		local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		open:SetSize(180, 26)
		open:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -76)
		open:SetText("Open HoT settings")
		open:SetScript("OnClick", function() ns.OpenOptions() end)
		panel:Hide()
		local ok = pcall(function()
			if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
				local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
				Settings.RegisterAddOnCategory(category)
			else InterfaceOptions_AddCategory(panel) end
		end)
		if ok then ns.optionsCategoryPanel = panel end
	end
	if ns.minimapButton or not Minimap or not CreateFrame then return end
	local b = CreateFrame("Button", "EllesmereUI_HoTPredictionMinimapButton", Minimap)
	ns.minimapButton = b
	b:SetSize(30, 30)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Spell_Nature_Rejuvenation")
	safe(icon, "SetAllPoints", b)
	safe(icon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then ns.OpenDebugWindow() else ns.OpenOptions() end
	end)
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("EllesmereUI HoT Prediction")
		GameTooltip:AddLine("Left-click: settings | Right-click: diagnostics", 1, 1, 1)
		GameTooltip:AddLine("Drag: move around minimap", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	b:SetScript("OnDragStart", function(self)
		if GameTooltip then GameTooltip:Hide() end
		self:SetScript("OnUpdate", dragPosition)
	end)
	local function stop(self) self:SetScript("OnUpdate", nil) end
	b:SetScript("OnDragStop", stop)
	b:SetScript("OnHide", stop)
	ns.UpdateMinimapButton()
end

-- Retry once at login if the minimap was absent during ADDON_LOADED.
ns.on("PLAYER_LOGIN", function() ns.InitOptions() end)

function ns.OpenQueueAppearance()
	local f = ns.queueAppearanceWindow
	if not f then
		if not CreateFrame then ns.print("settings unavailable: this client cannot create frames."); return end
		f = CreateFrame("Frame", "EllesmereUI_HoTPredictionQueueAppearance", UIParent, "BackdropTemplate")
		ns.queueAppearanceWindow = f
		f:SetSize(510, 360)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		f:SetFrameStrata("DIALOG")
		f:SetClampedToScreen(true)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", function(self) self:StartMoving() end)
		f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
		f:SetBackdropColor(0.04, 0.05, 0.06, 0.97)
		f:SetBackdropBorderColor(0.25, 0.65, 0.4, 1)
		label(f, "Next-swing border appearance", 20, -18, 470)
		label(f, "Changes the highlight only, not the action button or queue detection.", 20, -42, 470)
		f.controls = {}
		local function field(key, title, y)
			label(f, title, 24, y - 5, 335)
			local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
			e:SetSize(90, 24)
			e:SetPoint("TOPLEFT", f, "TOPLEFT", 375, y)
			e:SetAutoFocus(false)
			e:SetMaxLetters(12)
			e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
			f.controls[key] = e
		end
		field("thickness", "Border thickness (1-12 pixels)", -76)
		field("padding", "Border size / spacing (-12 to 24 pixels per side)", -110)
		field("alpha", "Opacity (0-1)", -144)
		label(f, "Color RGB (0-1 each)", 24, -187, 200)
		for i, key in ipairs({ "red", "green", "blue" }) do
			local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
			e:SetSize(65, 24)
			e:SetPoint("TOPLEFT", f, "TOPLEFT", 230 + (i - 1) * 80, -182)
			e:SetAutoFocus(false)
			e:SetMaxLetters(12)
			e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
			f.controls[key] = e
		end
		label(f, "Positive spacing enlarges the border; negative brings it inside the icon.\nSize/thickness edits made in combat take effect when combat ends.", 24, -222, 460)
		local message = label(f, "", 24, -268, 460)
		local function button(key, text, x, width, action)
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			b:SetSize(width, 24)
			b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -310)
			b:SetText(text)
			b:SetScript("OnClick", action)
			f.controls[key] = b
		end
		local function clearFocus()
			for _, key in ipairs({ "thickness", "padding", "alpha", "red", "green", "blue" }) do
				f.controls[key]:ClearFocus()
			end
		end
		f.Refresh = function()
			local c, db = f.controls, ns.db
			c.thickness:SetText(tostring(db.queuedSwingThickness))
			c.padding:SetText(tostring(db.queuedSwingPadding))
			c.alpha:SetText(tostring(db.queuedSwingAlpha))
			for i, key in ipairs({ "red", "green", "blue" }) do c[key]:SetText(tostring(db.queuedSwingColor[i])) end
		end
		button("apply", "Apply appearance", 24, 160, function()
			local c = f.controls
			local success = ns.queuedSwing.SetAppearance(tonumber(c.thickness:GetText()), tonumber(c.padding:GetText()),
				tonumber(c.alpha:GetText()), tonumber(c.red:GetText()), tonumber(c.green:GetText()), tonumber(c.blue:GetText()))
			if not success then message:SetText("Enter numbers within the listed ranges; nothing changed."); return end
			clearFocus()
			message:SetText(ns.api.InCombat() and "Saved. Size/thickness will apply after combat." or "Appearance saved.")
			f.Refresh()
		end)
		button("defaults", "Restore defaults", 198, 150, function()
			local d = ns.DEFAULTS
			ns.queuedSwing.SetAppearance(d.queuedSwingThickness, d.queuedSwingPadding, d.queuedSwingAlpha,
				d.queuedSwingColor[1], d.queuedSwingColor[2], d.queuedSwingColor[3])
			clearFocus()
			f.Refresh()
			message:SetText(ns.api.InCombat() and "Defaults saved. Size applies after combat." or "Default cyan border restored.")
		end)
		button("close", "Close", 370, 110, function() f:Hide() end)
		f:SetScript("OnHide", clearFocus)
		f:SetScript("OnShow", function() f.Refresh(); message:SetText("") end)
		if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
		f:Hide()
	end
	f.Refresh()
	f:Show()
	return f
end

local function ensureWindow()
	if ns.optionsWindow then return ns.optionsWindow end
	if not CreateFrame then return nil end
	local f = CreateFrame("Frame", WINDOW, UIParent, "BackdropTemplate")
	ns.optionsWindow = f
	f:SetSize(540, 650)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	f:SetBackdropColor(0.04, 0.05, 0.06, 0.97)
	f:SetBackdropBorderColor(0.25, 0.65, 0.4, 1)
	label(f, "EllesmereUI HoT Prediction", 18, -16)
	label(f, "Player only. Requires EllesmereUIUnitFrames native heal prediction.", 18, -38)
	local page = CreateFrame("Frame", nil, f)
	page:SetSize(540, 610)
	page:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -34)
	f.settingsPage = page
	local catalog = CreateFrame("Frame", nil, f)
	catalog:SetSize(510, 492)
	catalog:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -100)
	f.spellsPage = catalog
	local scroll = CreateFrame("ScrollFrame", nil, catalog, "UIPanelScrollFrameTemplate")
	scroll:SetSize(476, 486)
	scroll:SetPoint("TOPLEFT", catalog, "TOPLEFT", 0, 0)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(466, 486)
	local text = label(content, "", 0, 0, 466)
	text:SetWordWrap(true)
	scroll:SetScrollChild(content)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
	end)
	f.catalogText, f.catalogScroll = text, scroll
	function f.RefreshCatalog()
		text:SetText(ns.BuildSpellCatalog())
		content:SetHeight(math.max(486, text:GetStringHeight() + 12))
		scroll:UpdateScrollChildRect()
		scroll:SetVerticalScroll(0)
	end
	function f.SelectTab(tab)
		f.selectedTab = tab
		page:SetShown(tab == "settings")
		catalog:SetShown(tab == "spells")
		if tab == "spells" then
			for _, key in ipairs({ "alpha", "red", "green", "blue" }) do f.controls[key]:ClearFocus() end
			f.RefreshCatalog()
		end
		f.controls.settingsTab:SetText(tab == "settings" and "[Settings]" or "Settings")
		f.controls.spellsTab:SetText(tab == "spells" and "[Implemented spells]" or "Implemented spells")
	end
	f.controls = {}
	local refreshing = false
	local function command(text)
		ns.HandleCommand(text)
		f.Refresh()
	end
	local function check(key, title, y, read, write)
		local c = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
		c:SetSize(26, 26)
		c:SetPoint("TOPLEFT", page, "TOPLEFT", 18, y)
		label(page, title, 48, y - 6, 465)
		c:SetScript("OnClick", function(self) if not refreshing then write(self:GetChecked() and true or false); f.Refresh() end end)
		c.read = read
		f.controls[key] = c
	end
	check("enabled", "Enable helper (healing overlay and next-swing borders)", -62, function() return ns.db.enabled end,
		function(v) command("enable " .. (v and "on" or "off")) end)
	check("approximate", "Approximate tooltip prediction (needed on restricted Forever)", -92,
		function() return ns.db.approximatePrediction end, function(v) command("approximate " .. (v and "on" or "off")) end)
	label(page, "Approximate mode ignores healing absorbs; native overlap may double-count.", 48, -122, 465)
	check("native", "Inherit EllesmereUI prediction texture and color", -146,
		function() return ns.db.shareNativeStyle end, function(v)
			if v then command("color native") else
				local c = ns.db.overlayColor
				command(string.format("color %g %g %g", c[1], c[2], c[3]))
			end
		end)
	local function edit(key, x, y, width)
		local e = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
		e:SetSize(width or 65, 24)
		e:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
		e:SetAutoFocus(false)
		e:SetMaxLetters(12)
		e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
		f.controls[key] = e
		return e
	end
	label(page, "Opacity (0-1)", 24, -188, 120)
	edit("alpha", 150, -183)
	label(page, "Custom RGB (0-1 each)", 24, -221, 180)
	edit("red", 210, -216)
	edit("green", 290, -216)
	edit("blue", 370, -216)
	local message = label(page, "", 24, -275)
	local function button(key, title, x, y, width, action)
		local parent = (key == "settingsTab" or key == "spellsTab" or key == "close") and f or page
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(width, 24)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		b:SetText(title)
		b:SetScript("OnClick", action)
		f.controls[key] = b
	end
	button("apply", "Apply appearance", 24, -246, 160, function()
		local c = f.controls
		local a, r, g, b = tonumber(c.alpha:GetText()), tonumber(c.red:GetText()), tonumber(c.green:GetText()), tonumber(c.blue:GetText())
		for _, v in ipairs({a or -1, r or -1, g or -1, b or -1}) do
			if not ns.isFinite(v) or v > 1 then message:SetText("Enter numbers from 0 to 1; nothing changed."); return end
		end
		ns.HandleCommand("alpha " .. a)
		if not ns.db.shareNativeStyle then ns.HandleCommand(string.format("color %g %g %g", r, g, b)) end
		for _, key in ipairs({"alpha", "red", "green", "blue"}) do c[key]:ClearFocus() end
		message:SetText("Appearance saved. RGB applies only when native style is unchecked.")
		f.Refresh()
	end)
	check("minimap", "Show minimap button (drag to reposition)", -303,
		function() return not ns.db.minimapHidden end, function(v) command("minimap " .. (v and "on" or "off")) end)
	check("exclude", "Advanced: native incoming heals exclude HoTs (verified clients only)", -337,
		function() return ns.db.assumeApiExcludesHoTs end, function(v) command("excludehots " .. (v and "on" or "off")) end)
	label(page, "Leave off unless verified. Does not unlock restricted values or fix overlap.", 48, -367, 465)
	check("debug", "Enable debug chat logging", -395, function() return ns.db.debug end,
		function(v) command("debug " .. (v and "on" or "off")) end)
	button("preview", "Preview +1000", 24, -435, 145, function() command("test 1000") end)
	button("stop", "Stop preview", 182, -435, 145, function() command("test off") end)
	button("diagnostics", "Copy diagnostics", 340, -435, 175, function() ns.OpenDebugWindow() end)
	local status = label(page, "", 24, -470)
	label(page, "Preview is session-only; Stop preview to display real healing again.\nManual rank/tick calibration: /euihot help. Changes save immediately.", 24, -495)
	check("queue", "Highlight genuinely queued Maul / Heroic Strike / Cleave", -532,
		function() return ns.db.queuedSwingEnabled end, function(v) command("queue " .. (v and "on" or "off")) end)
	button("queueAppearance", "Next-swing appearance...", 24, -572, 225, function() ns.OpenQueueAppearance() end)
	button("close", "Close", 420, -606, 95, function() f:Hide() end)
	button("settingsTab", "Settings", 18, -62, 130, function() f.SelectTab("settings") end)
	button("spellsTab", "Implemented spells", 160, -62, 185, function() f.SelectTab("spells") end)
	f.Refresh = function()
		refreshing = true
		for _, c in pairs(f.controls) do if c.read then c:SetChecked(c.read()) end end
		f.controls.alpha:SetText(tostring(ns.db.alpha))
		local rgb = ns.db.overlayColor
		for i, key in ipairs({"red", "green", "blue"}) do f.controls[key]:SetText(tostring(rgb[i])) end
		status:SetText("v" .. ns.version .. (ns.session.fake and " | PREVIEW ACTIVE (not real healing)" or " | Real healing mode"))
		refreshing = false
	end
	f:SetScript("OnShow", function() f.Refresh(); f.SelectTab(f.selectedTab or "settings") end)
	f:SetScript("OnHide", function()
		for _, key in ipairs({"alpha", "red", "green", "blue"}) do f.controls[key]:ClearFocus() end
	end)
	if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = WINDOW end
	f.SelectTab("settings")
	f:Hide()
	return f
end

function ns.OpenOptions()
	local f = ensureWindow()
	if not f then ns.print("settings unavailable: this client cannot create frames."); return end
	f.Refresh()
	f.SelectTab(f.selectedTab or "settings")
	f:Show()
	return f
end
