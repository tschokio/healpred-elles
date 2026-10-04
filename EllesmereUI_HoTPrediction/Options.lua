-- Addon-owned configuration UI. No libraries, native frame edits or idle timers.
-- The only OnUpdate exists while the user drags the minimap button.
local addonName, ns = ...
local WINDOW = "EllesmereUI_HoTPredictionOptions"
-- The appearance editor is a child of the main settings window in spirit, but a
-- separate root frame. Both used DIALOG, so the main window's deeper
-- descendants (e.g. its +10 preview border) sorted above the editor and
-- interleaved into it. A higher stratum than DIALOG, still below TOOLTIP,
-- lifts the whole editor (controls and preview inherit at creation).
local APPEARANCE_STRATA = "FULLSCREEN_DIALOG"

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

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function panel(parent, x, y, width, height)
	local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	p:SetSize(width, height)
	p:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	p:SetBackdropColor(0.055, 0.075, 0.095, 1)
	p:SetBackdropBorderColor(0.12, 0.18, 0.22, 1)
	return p
end

-- Decorative background painted into the parent's own BACKGROUND draw layer.
-- A child frame defaults to parent frame level + 1 and would therefore cover
-- the parent's OVERLAY FontStrings (descriptive labels), while textures share
-- the parent's frame level and always render beneath its text. Textures also
-- never intercept mouse input, unlike a mouse-enabled frame.
local function background(parent, x, y, width, height)
	local border = parent:CreateTexture(nil, "BACKGROUND")
	border:SetTexture(WHITE)
	border:SetVertexColor(0.12, 0.18, 0.22, 1)
	border:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 1, y + 1)
	border:SetSize(width + 2, height + 2)
	local fill = parent:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(WHITE)
	fill:SetVertexColor(0.055, 0.075, 0.095, 1)
	fill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fill:SetSize(width, height)
	parent.background = fill
	return fill
end

local function windowStyle(f, title, subtitle, width)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(0.025, 0.035, 0.048, 0.99)
	f:SetBackdropBorderColor(0.18, 0.38, 0.4, 1)
	local heading = label(f, title, 24, -18, width - 48)
	heading:SetFont("Fonts\\FRIZQT__.TTF", 18, "")
	heading:SetTextColor(0.8, 1, 0.96, 1)
	local hint = label(f, subtitle, 24, -44, width - 48)
	hint:SetTextColor(0.55, 0.66, 0.72, 1)
end

local function flatButton(b)
	-- Addon-owned, non-secure widget; keep its template's keyboard/click behavior.
	if b.SetNormalTexture then b:SetNormalTexture(WHITE); b:GetNormalTexture():SetVertexColor(0.1, 0.19, 0.23, 1) end
	if b.SetPushedTexture then b:SetPushedTexture(WHITE); b:GetPushedTexture():SetVertexColor(0.08, 0.32, 0.34, 1) end
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end

function ns.OpenSpellEditor()
	local f = ns.spellEditorWindow
	if not f then
		f = CreateFrame("Frame", "EllesmereUI_HoTPredictionSpellEditor", UIParent, "BackdropTemplate")
		ns.spellEditorWindow = f
		f:SetSize(510, 410); f:SetPoint("CENTER"); f:SetFrameStrata(APPEARANCE_STRATA)
		f:EnableMouse(true)
		windowStyle(f, "Manage your spells", "Exact spell IDs; changes save immediately.", 510)
		f.mode = "queue"
		f.controls = {}
		f.fieldLabels = {}
		local function input(key, title, y, width)
			f.fieldLabels[key] = label(f, title, 24, y - 5, 210)
			local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
			e:SetSize(width or 240, 24); e:SetPoint("TOPLEFT", f, "TOPLEFT", 240, y)
			e:SetAutoFocus(false); e:SetMaxLetters(key == "name" and 80 or 12)
			e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
			f.controls[key] = e
		end
		input("id", "Spell ID (exact rank / aura)", -120)
		input("name", "Name (optional)", -156)
		input("interval", "HoT tick interval (seconds)", -192)
		input("amount", "HoT total healing per tick", -228)
		f.hint = label(f, "", 24, -268, 462)
		f.message = label(f, "", 24, -318, 462)
		local function button(key, title, x, y, width, fn)
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			b:SetSize(width, 24); b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
			b:SetText(title); flatButton(b); b:SetScript("OnClick", fn); f.controls[key] = b
		end
		local function mode(value)
			f.mode = value
			f.controls.queue:SetText(value == "queue" and "[Action highlight]" or "Action highlight")
			f.controls.hot:SetText(value == "hot" and "[Player HoT]" or "Player HoT")
			f.controls.interval:SetShown(value == "hot"); f.controls.amount:SetShown(value == "hot")
			for _, key in ipairs({"interval", "amount"}) do
				if value == "hot" then f.fieldLabels[key]:Show() else f.fieldLabels[key]:Hide() end
			end
			f.controls.interval:ClearFocus(); f.controls.amount:ClearFocus()
			f.hint:SetText(value == "queue" and "Highlights only readable current-action state. No press-based guesses. Auto Attack, Auto Shot and Shoot are excluded."
				or "Use the applied aura ID, not a summon or direct heal. Requires your own readable player aura. Amount is the full tick, including overheal.")
			f.message:SetText("")
		end
		button("queue", "Action highlight", 24, -80, 220, function() mode("queue") end)
		button("hot", "Player HoT", 260, -80, 220, function() mode("hot") end)
		local function apply(op)
			local id = tonumber(f.controls.id:GetText())
			local name = f.controls.name:GetText()
			if not ns.isPositiveInt(id) or id > 100000000 then f.message:SetText("Enter a positive spell ID up to 100000000."); return end
			if #name > 80 or name:find("[|\r\n]") then f.message:SetText("Name must not contain formatting codes or line breaks."); return end
			if f.mode == "queue" then
				local ok, message = ns.queuedSwing.EditSpell(op, id, name)
				f.message:SetText(message)
				if not ok then return end
			else
				local interval, amount = tonumber(f.controls.interval:GetText()), tonumber(f.controls.amount:GetText())
				if op == "add" then
					if not ns.isFinite(interval) or interval <= 0 or interval > 300
						or not ns.isFinite(amount) or amount <= 0 or amount > ns.AMOUNT_OVERRIDE_MAX then
						f.message:SetText("Enter a tick interval > 0 to 300 and positive per-tick healing; nothing changed."); return
					end
				end
				ns.HandleCommand("spell " .. op .. " " .. id .. " " .. name)
				if op == "add" then
					ns.HandleCommand("interval " .. id .. " " .. interval)
					ns.HandleCommand("amount " .. id .. " " .. amount)
				end
				f.message:SetText(op .. " saved for spell " .. id .. ".")
			end
			for _, key in ipairs({"id", "name", "interval", "amount"}) do f.controls[key]:ClearFocus() end
			if ns.optionsWindow then ns.optionsWindow.RefreshCatalog() end
		end
		button("add", "Add / update", 24, -366, 126, function() apply("add") end)
		button("remove", "Remove", 160, -366, 100, function() apply("remove") end)
		button("reset", "Reset ID", 270, -366, 100, function() apply("reset") end)
		button("close", "Close", 380, -366, 100, function() f:Hide() end)
		f:SetScript("OnHide", function()
			for _, key in ipairs({"id", "name", "interval", "amount"}) do f.controls[key]:ClearFocus() end
		end)
		if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "EllesmereUI_HoTPredictionSpellEditor" end
		mode("queue")
	end
	f:Show()
	return f
end

local function queuePreview(parent, x, y, width, height)
	local p = panel(parent, x, y, width, height)
	label(p, "ACTION BUTTON PREVIEW", 16, -18, width - 32):SetTextColor(0.35, 0.88, 0.8, 1)
	label(p, "Click the icon to queue / release the sample.", 16, -44, width - 32)
	local b = CreateFrame("Button", nil, p, "BackdropTemplate")
	b:SetSize(48, 48)
	b:SetPoint("TOP", p, "TOP", 0, -118)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b:SetBackdropColor(0.015, 0.02, 0.025, 1)
	b:SetBackdropBorderColor(0.3, 0.36, 0.4, 1)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Ability_Druid_Maul")
	safe(icon, "SetAllPoints", b)
	safe(icon, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local border = CreateFrame("Frame", nil, b, "BackdropTemplate")
	border:EnableMouse(false)
	border:SetFrameLevel(b:GetFrameLevel() + 10)
	local state = label(p, "", 16, -205, width - 32)
	local details = label(p, "", 16, -238, width - 32)
	label(p, "Sample only. No real casts or queues.\n48px icon; actual size follows EllesmereUI.", 16, -278, width - 32):SetTextColor(0.55, 0.66, 0.72, 1)
	p.button, p.border, p.queued = b, border, true
	p.abilities = {}
	for i, ability in ipairs({
		{ "Maul", "Ability_Druid_Maul" },
		{ "Strike", "Ability_Rogue_Ambush" },
		{ "Cleave", "Ability_Warrior_Cleave" },
		{ "Raptor", "Ability_MeleeDamage" },
	}) do
		local select = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		local size = (width - 32) / 4
		select:SetSize(size - 4, 22)
		select:SetPoint("TOPLEFT", p, "TOPLEFT", 16 + (i - 1) * size, -78)
		select:SetText(ability[1])
		flatButton(select)
		select:SetScript("OnClick", function() icon:SetTexture("Interface\\Icons\\" .. ability[2]) end)
		p.abilities[i] = select
	end
	function p.Update(thickness, padding, alpha, r, g, blue)
		if not ns.queuedSwing.ValidAppearance(thickness, padding, alpha, r, g, blue) then return false end
		ns.queuedSwing.LayoutBorder(border, b, thickness, padding)
		border:SetBackdropBorderColor(r, g, blue, alpha)
		border:SetShown(p.queued)
		state:SetText(p.queued and "QUEUED - border active" or "IDLE - border hidden")
		state:SetTextColor(p.queued and 0.35 or 0.55, p.queued and 0.88 or 0.66, 0.8, 1)
		details:SetText(string.format("Thickness: %gpx\nSpacing: %gpx | Opacity: %d%%", thickness, padding, math.floor(alpha * 100 + 0.5)))
		return true
	end
	function p.Saved()
		local d, c = ns.db, ns.db.queuedSwingColor
		p.Update(d.queuedSwingThickness, d.queuedSwingPadding, d.queuedSwingAlpha, c[1], c[2], c[3])
	end
	b:SetScript("OnClick", function()
		p.queued = not p.queued
		border:SetShown(p.queued)
		state:SetText(p.queued and "QUEUED - border active" or "IDLE - border hidden")
		state:SetTextColor(p.queued and 0.35 or 0.55, p.queued and 0.88 or 0.66, 0.8, 1)
	end)
	p.Saved()
	return p
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
		f:SetSize(770, 420)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		f:SetFrameStrata(APPEARANCE_STRATA)
		f:SetClampedToScreen(true)
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", function(self) self:StartMoving() end)
		f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		windowStyle(f, "Next-swing appearance", "Style your queued attack highlight. Preview edits before saving.", 770)
		background(f, 12, -66, 484, 274)
		f.preview = queuePreview(f, 510, -66, 244, 338)
		f.controls = {}
		local refreshing = false
		local draft = label(f, "Editing is preview-only until you click Apply.", 24, -304, 460)
		draft:SetTextColor(0.55, 0.66, 0.72, 1)
		function f.UpdatePreview()
			if refreshing then return end
			local c = f.controls
			local valid = f.preview.Update(tonumber(c.thickness:GetText()), tonumber(c.padding:GetText()),
				tonumber(c.alpha:GetText()), tonumber(c.red:GetText()), tonumber(c.green:GetText()), tonumber(c.blue:GetText()))
			draft:SetText(valid and "Preview only. Click Apply to save these values." or "Invalid draft - showing the last valid preview.")
		end
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
			b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -366)
			b:SetText(text)
			b:SetScript("OnClick", action)
			flatButton(b)
			f.controls[key] = b
		end
		local function clearFocus()
			for _, key in ipairs({ "thickness", "padding", "alpha", "red", "green", "blue" }) do
				f.controls[key]:ClearFocus()
			end
		end
		f.Refresh = function()
			refreshing = true
			local c, db = f.controls, ns.db
			c.thickness:SetText(tostring(db.queuedSwingThickness))
			c.padding:SetText(tostring(db.queuedSwingPadding))
			c.alpha:SetText(tostring(db.queuedSwingAlpha))
			for i, key in ipairs({ "red", "green", "blue" }) do c[key]:SetText(tostring(db.queuedSwingColor[i])) end
			refreshing = false
			f.UpdatePreview()
		end
		button("apply", "Apply appearance", 24, 160, function()
			local c = f.controls
			local success = ns.queuedSwing.SetAppearance(tonumber(c.thickness:GetText()), tonumber(c.padding:GetText()),
				tonumber(c.alpha:GetText()), tonumber(c.red:GetText()), tonumber(c.green:GetText()), tonumber(c.blue:GetText()))
			if not success then message:SetText("Enter numbers within the listed ranges; nothing changed."); return end
			if ns.optionsWindow then ns.optionsWindow.preview.Saved() end
			clearFocus()
			message:SetText(ns.api.InCombat() and "Saved. Size/thickness will apply after combat." or "Appearance saved.")
			f.Refresh()
		end)
		button("defaults", "Restore defaults", 198, 150, function()
			local d = ns.DEFAULTS
			ns.queuedSwing.SetAppearance(d.queuedSwingThickness, d.queuedSwingPadding, d.queuedSwingAlpha,
				d.queuedSwingColor[1], d.queuedSwingColor[2], d.queuedSwingColor[3])
			if ns.optionsWindow then ns.optionsWindow.preview.Saved() end
			clearFocus()
			f.Refresh()
			message:SetText(ns.api.InCombat() and "Defaults saved. Size applies after combat." or "Default cyan border restored.")
		end)
		button("close", "Close", 370, 110, function() f:Hide() end)
		for _, key in ipairs({ "thickness", "padding", "alpha", "red", "green", "blue" }) do
			f.controls[key]:SetScript("OnTextChanged", f.UpdatePreview)
		end
		f:SetScript("OnHide", clearFocus)
		f:SetScript("OnShow", function() f.Refresh(); message:SetText("") end)
		if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = f:GetName() end
		f:Hide()
	end
	-- Keep the root's ordering consistent when this lazy window is reused.
	f:SetFrameStrata(APPEARANCE_STRATA)
	f.Refresh()
	f:Show()
	return f
end

local function ensureWindow()
	if ns.optionsWindow then return ns.optionsWindow end
	if not CreateFrame then return nil end
	local f = CreateFrame("Frame", WINDOW, UIParent, "BackdropTemplate")
	ns.optionsWindow = f
	f:SetSize(800, 650)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	windowStyle(f, "EllesmereUI helper", "Healing predictions & queued attacks - your controls, in one place.", 800)
	f.preview = queuePreview(f, 552, -100, 224, 486)
	local page = CreateFrame("Frame", nil, f)
	page:SetSize(540, 610)
	page:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -34)
	f.settingsPage = page
	background(page, 12, -54, 516, 510)
	local catalog = CreateFrame("Frame", nil, f)
	catalog:SetSize(510, 492)
	catalog:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -100)
	f.spellsPage = catalog
	background(catalog, -3, 4, 516, 492)
	local catalogHeading = label(catalog, "503 spellbook entries reviewed | select a class", 8, -5, 482)
	catalogHeading:SetTextColor(0.55, 0.75, 0.78, 1)
	local scroll = CreateFrame("ScrollFrame", nil, catalog, "UIPanelScrollFrameTemplate")
	scroll:SetSize(476, 412)
	scroll:SetPoint("TOPLEFT", catalog, "TOPLEFT", 0, -74)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(466, 412)
	scroll:SetScrollChild(content)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
	end)
	f.catalogScroll, f.catalogRows, f.catalogExpanded = scroll, {}, {}
	f.catalogFilter = "ALL"
	function f.RefreshCatalog(keepScroll)
		f.catalogSnapshot = ns.BuildSpellCatalog()
		local oldScroll = scroll:GetVerticalScroll()
		local index, y = 0, 0
		local function card()
			index = index + 1
			local row = f.catalogRows[index]
			if not row then
				row = panel(content, 0, 0, 466, 100)
				row.icon = row:CreateTexture(nil, "ARTWORK")
				row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -10)
				row.icon:SetSize(32, 32)
				row.title = label(row, "", 54, -10, 306)
				row.status = label(row, "", 54, -30, 394)
				row.note = label(row, "", 10, -56, 442)
				row.ids = label(row, "", 10, -90, 442)
				row.details = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
				row.details:SetSize(84, 22)
				row.details:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -10)
				flatButton(row.details)
				row.details:SetScript("OnClick", function()
					f.catalogExpanded[row.key] = not f.catalogExpanded[row.key]
					f.RefreshCatalog(true)
				end)
				f.catalogRows[index] = row
			end
			row:ClearAllPoints(); row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			row:Show()
			return row
		end
		for _, group in ipairs(ns.GetSpellCatalog()) do
			if (f.catalogFilter == "ALL" or f.catalogFilter == group.key) and #group.rows > 0 then
				local heading = card()
					heading.key = "class:" .. group.key
					heading.entry = nil
					heading.icon:SetTexture(group.key == "CUSTOM" and "Interface\\Icons\\INV_Misc_Book_11" or "Interface\\Icons\\ClassIcon_" .. group.key:lower())
					heading.title:ClearAllPoints(); heading.title:SetPoint("TOPLEFT", heading, "TOPLEFT", 54, -10)
					heading.status:ClearAllPoints(); heading.status:SetPoint("TOPLEFT", heading, "TOPLEFT", 54, -30)
				heading.title:SetText(group.name)
				heading.title:SetTextColor(group.color[1], group.color[2], group.color[3], 1)
				heading.status:SetText(group.count and (group.count .. " entries reviewed | support & limitations below") or "Shared actions and user-added spell candidates")
				heading.status:SetTextColor(0.55, 0.66, 0.72, 1)
				heading.note:SetText(""); heading.ids:SetText(""); heading.details:Hide()
				heading:SetHeight(52); y = y + 60
				for _, entry in ipairs(group.rows) do
					local row = card()
					row.key, row.entry = entry.key, entry
					local path = "Interface\\Icons\\" .. entry.icon
					local getTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
					if type(getTexture) == "function" and entry.ids[1] then
						local ok, value = pcall(getTexture, entry.ids[1])
						if ok and not ns.isSecret(value) and (type(value) == "string" or type(value) == "number") then path = value end
					end
					row.icon:SetTexture(path)
					row.title:SetText(entry.name); row.title:SetTextColor(0.92, 0.95, 0.97, 1)
					local top = math.max(32, row.title:GetStringHeight() + 16)
					row.status:ClearAllPoints(); row.status:SetPoint("TOPLEFT", row, "TOPLEFT", 54, -top)
					row.status:SetText(entry.status .. (#entry.ids == 0 and #entry.disabled > 0 and " - disabled" or ""))
					row.status:SetTextColor(entry.deferred and 0.95 or 0.35, entry.deferred and 0.72 or 0.88, entry.deferred and 0.4 or 0.8, 1)
					local noteY = top + row.status:GetStringHeight() + 12
					row.note:ClearAllPoints(); row.note:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -noteY)
					row.note:SetText(entry.note); row.note:SetTextColor(0.65, 0.72, 0.76, 1)
					local height = noteY + row.note:GetStringHeight() + 12
					local hasIDs = #entry.ids > 0 or #entry.disabled > 0
					row.details:SetShown(hasIDs)
					row.details:SetText(f.catalogExpanded[entry.key] and "Hide IDs" or "Rank IDs")
					if f.catalogExpanded[entry.key] and hasIDs then
						local ids = #entry.ids > 0 and ("IDs: " .. ns.CatalogIDs(entry.ids)) or ""
						if #entry.disabled > 0 then ids = ids .. "\nDisabled by your settings: " .. ns.CatalogIDs(entry.disabled) end
						row.ids:ClearAllPoints(); row.ids:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -height)
						row.ids:SetText(ids); row.ids:SetTextColor(0.55, 0.75, 0.78, 1)
						height = height + row.ids:GetStringHeight() + 12
					else row.ids:SetText("") end
					row:SetHeight(height); y = y + height + 8
				end
			end
		end
		for i = index + 1, #f.catalogRows do f.catalogRows[i]:Hide() end
		content:SetHeight(math.max(412, y))
		scroll:UpdateScrollChildRect()
		scroll:SetVerticalScroll(keepScroll and math.min(oldScroll, scroll:GetVerticalScrollRange()) or 0)
	end
	f.catalogClassButtons = {}
	local function classButton(key, name, index)
		local b = CreateFrame("Button", nil, catalog, "UIPanelButtonTemplate")
		b:SetSize(key == "ALL" and 52 or 40, 38)
		b:SetPoint("TOPLEFT", catalog, "TOPLEFT", index == 0 and 8 or 64 + (index - 1) * 44, -28)
		flatButton(b)
		if key == "ALL" then b:SetText("All") else
			local icon = b:CreateTexture(nil, "ARTWORK")
			icon:SetTexture("Interface\\Icons\\ClassIcon_" .. key:lower())
			icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -3); icon:SetSize(30, 30)
		end
		b:SetScript("OnClick", function()
			f.catalogFilter = key
			catalogHeading:SetText(name .. " | click Rank IDs for exact spells")
			f.RefreshCatalog()
		end)
		b:SetScript("OnEnter", function(self)
			if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(name); GameTooltip:Show() end
		end)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		f.catalogClassButtons[key] = b
	end
	classButton("ALL", "All classes", 0)
	for i, class in ipairs(ns.catalogClasses) do if class.key ~= "CUSTOM" then classButton(class.key, class.name, i) end end

	f.controls = {}
	local notesPage = CreateFrame("Frame", nil, f)
	notesPage:SetSize(510, 492)
	notesPage:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -100)
	f.notesPage = notesPage
	background(notesPage, -3, 4, 516, 492)
	local notesHeading = label(notesPage, "Notes | saved as you type | editable out of combat", 8, -5, 482)
	notesHeading:SetTextColor(0.55, 0.75, 0.78, 1)
	local notesEditor = CreateFrame("EditBox", nil, notesPage, "BackdropTemplate")
	notesEditor:SetMultiLine(true)
	notesEditor:SetAutoFocus(false)
	notesEditor:SetSize(486, 186)
	notesEditor:SetPoint("TOPLEFT", notesPage, "TOPLEFT", 10, -30)
	notesEditor:SetTextInsets(8, 8, 8, 8)
	notesEditor:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	notesEditor:SetBackdropColor(0.02, 0.03, 0.04, 1)
	notesEditor:SetBackdropBorderColor(0.2, 0.3, 0.34, 0.9)
	notesEditor:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	notesEditor:SetScript("OnTextChanged", function(self) ns.notes.OnEditorChanged(self) end)
	f.notesEditor = notesEditor
	ns.notes.tabEditor = notesEditor
	f.notesHint = label(notesPage, "", 10, -222, 486)
	ns.notes.tabHint = f.notesHint

	local function noteField(key, x, y, width)
		local e = CreateFrame("EditBox", nil, notesPage, "InputBoxTemplate")
		e:SetSize(width or 52, 22)
		e:SetPoint("TOPLEFT", notesPage, "TOPLEFT", x, y)
		e:SetAutoFocus(false)
		e:SetMaxLetters(10)
		e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		f.controls[key] = e
		return e
	end
	label(notesPage, "Window width x height (180-900 / 80-800)", 10, -254, 260)
	noteField("notesWidth", 280, -249, 58)
	label(notesPage, "x", 344, -254, 12)
	noteField("notesHeight", 360, -249, 58)
	label(notesPage, "Font size (8-32)", 10, -284, 150)
	noteField("notesFont", 150, -279, 58)
	label(notesPage, "Text RGB (0-1)", 230, -284, 120)
	noteField("notesTextR", 340, -279, 46)
	noteField("notesTextG", 392, -279, 46)
	noteField("notesTextB", 444, -279, 46)
	label(notesPage, "Background RGB + opacity (0-1)", 10, -314, 240)
	noteField("notesBgR", 260, -309, 46)
	noteField("notesBgG", 312, -309, 46)
	noteField("notesBgB", 364, -309, 46)
	noteField("notesBgA", 416, -309, 46)
	local notesMessage = label(notesPage, "", 10, -400, 486)
	local function notesButton(key, title, x, y, width, action)
		local b = CreateFrame("Button", nil, notesPage, "UIPanelButtonTemplate")
		b:SetSize(width, 24)
		b:SetPoint("TOPLEFT", notesPage, "TOPLEFT", x, y)
		b:SetText(title)
		b:SetScript("OnClick", action)
		flatButton(b)
		f.controls[key] = b
		return b
	end
	notesButton("notesApply", "Apply style", 10, -346, 120, function()
		local c = f.controls
		local ok, message = ns.notes.SetStyle({
			width = tonumber(c.notesWidth:GetText()),
			height = tonumber(c.notesHeight:GetText()),
			fontSize = tonumber(c.notesFont:GetText()),
			textColor = { tonumber(c.notesTextR:GetText()), tonumber(c.notesTextG:GetText()), tonumber(c.notesTextB:GetText()) },
			background = { tonumber(c.notesBgR:GetText()), tonumber(c.notesBgG:GetText()), tonumber(c.notesBgB:GetText()), tonumber(c.notesBgA:GetText()) },
		})
		if not ok then notesMessage:SetText(message); return end
		for _, key in ipairs({ "notesWidth", "notesHeight", "notesFont", "notesTextR", "notesTextG", "notesTextB", "notesBgR", "notesBgG", "notesBgB", "notesBgA" }) do c[key]:ClearFocus() end
		notesMessage:SetText(ns.api.InCombat() and "Style saved. The floating window is read-only in combat." or "Notes style saved.")
		f.RefreshNotes()
	end)
	notesButton("notesReset", "Reset style", 140, -346, 120, function()
		local d = ns.DEFAULTS.notes
		ns.notes.SetStyle({ width = d.width, height = d.height, fontSize = d.fontSize,
			textColor = { d.textColor[1], d.textColor[2], d.textColor[3] },
			background = { d.background[1], d.background[2], d.background[3], d.background[4] } })
		notesMessage:SetText("Default notes style restored.")
		f.RefreshNotes()
	end)
	notesButton("notesShow", "Show floating notes", 10, -378, 170, function()
		ns.notes.Open()
		notesMessage:SetText("Floating notes opened. Drag the title bar to move; Collapse rolls it up.")
	end)
	notesButton("notesCollapse", "Collapse / expand", 190, -378, 150, function()
		ns.notes.SetCollapsed(not ns.notes.IsCollapsed())
		notesMessage:SetText(ns.notes.IsCollapsed() and "Notes collapsed." or "Notes expanded.")
	end)
	notesButton("notesClose", "Close", 350, -378, 90, function()
		ns.notes.Close()
		notesMessage:SetText("Floating notes closed.")
	end)
	function f.RefreshNotes()
		local c = f.controls
		local s = ns.notes.Style()
		c.notesWidth:SetText(tostring(s.width)); c.notesHeight:SetText(tostring(s.height)); c.notesFont:SetText(tostring(s.fontSize))
		for i, key in ipairs({ "notesTextR", "notesTextG", "notesTextB" }) do c[key]:SetText(tostring(s.textColor[i])) end
		for i, key in ipairs({ "notesBgR", "notesBgG", "notesBgB", "notesBgA" }) do c[key]:SetText(tostring(s.background[i])) end
		ns.notes.RefreshText()
		ns.notes.RefreshEditable()
	end

	function f.SelectTab(tab)
		f.selectedTab = tab
		page:SetShown(tab == "settings")
		catalog:SetShown(tab == "spells")
		notesPage:SetShown(tab == "notes")
		if tab == "spells" then
			for _, key in ipairs({ "alpha", "red", "green", "blue" }) do f.controls[key]:ClearFocus() end
			f.RefreshCatalog()
		elseif tab == "notes" then
			f.RefreshNotes()
		end
		f.controls.settingsTab:SetText(tab == "settings" and "[Settings]" or "Settings")
		f.controls.spellsTab:SetText(tab == "spells" and "[Implemented spells]" or "Implemented spells")
		f.controls.notesTab:SetText(tab == "notes" and "[Notes]" or "Notes")
	end
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
		local parent = (key == "settingsTab" or key == "notesTab" or key == "spellsTab" or key == "manageTab" or key == "close") and f or page
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(width, 24)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		b:SetText(title)
		b:SetScript("OnClick", action)
		flatButton(b)
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
	check("queue", "Highlight genuinely queued next-swing attacks (all supported classes)", -532,
		function() return ns.db.queuedSwingEnabled end, function(v) command("queue " .. (v and "on" or "off")) end)
	button("queueAppearance", "Next-swing appearance...", 24, -572, 225, function() ns.OpenQueueAppearance() end)
	button("manageSpells", "Manage spells...", 270, -572, 225, function() ns.OpenSpellEditor() end)
	button("close", "Close", 420, -606, 95, function() f:Hide() end)
	button("settingsTab", "Settings", 18, -62, 118, function() f.SelectTab("settings") end)
	button("notesTab", "Notes", 143, -62, 96, function() f.SelectTab("notes") end)
	button("spellsTab", "Implemented spells", 246, -62, 176, function() f.SelectTab("spells") end)
	button("manageTab", "Manage spells...", 429, -62, 160, function() ns.OpenSpellEditor() end)
	f.Refresh = function()
		refreshing = true
		for _, c in pairs(f.controls) do if c.read then c:SetChecked(c.read()) end end
		f.controls.alpha:SetText(tostring(ns.db.alpha))
		local rgb = ns.db.overlayColor
		for i, key in ipairs({"red", "green", "blue"}) do f.controls[key]:SetText(tostring(rgb[i])) end
		status:SetText("v" .. ns.version .. (ns.session.fake and " | PREVIEW ACTIVE (not real healing)" or " | Real healing mode"))
		f.preview.Saved()
		if f.RefreshNotes then f.RefreshNotes() end
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
