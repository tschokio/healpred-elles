local function click(control, checked)
	control:SetChecked(checked)
	control:GetScript("OnClick")(control)
end

local function style(overrides)
	local values = {
		duration = 6, maxRows = 6, fontSize = 13, iconSize = 24, width = 320,
		opacity = 1, backgroundAlpha = 0.78, qualityColors = true,
	}
	for key, value in pairs(overrides or {}) do values[key] = value end
	return values
end

T.register("loot window: opt-in events record only local player loot and render item details", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	assert_true(loot ~= nil)
	assert_false(loot.Enabled(), "loot tracking is off by default")
	for _, event in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY", "CHAT_MSG_COMBAT_FACTION_CHANGE" }) do
		assert_false(loot.eventFrame._events[event], event .. " is not registered while disabled")
	end
	_G.UnitName = function() return "Tester", "Realm" end
	_G.UnitGUID = function() return "Player-123" end
	_G.GetItemInfoInstant = function(itemID) return itemID, 0, 0, "", "Interface\\Icons\\INV_Misc_Cloth_01" end
	_G.GetItemInfo = function()
		return "Linen Cloth", "|Hitem:12345|h[Linen Cloth]|h", 2, 1, 0,
			"Trade Goods", "Cloth", 20, "", "Interface\\Icons\\INV_Misc_Cloth_01", 120
	end
	Mocks.now = 10
	loot.SetEnabled(true)
	assert_true(loot.Enabled())
	assert_true(loot.eventFrame._events.CHAT_MSG_LOOT)
	local link = "|cff1eff00|Hitem:12345::::::::70:257::::::|h[Linen Cloth]|h|rx3."
	assert_false(loot.HandleEvent("CHAT_MSG_LOOT", link, "AnotherPlayer"), "other players' drops are ignored")
	assert_eq(#loot.Entries(), 0)
	local payload = { "You receive loot: " .. link, "OtherPlayer" }
	payload[12] = "Player-123"
	local unpackValues = unpack or table.unpack
	loot.eventFrame:GetScript("OnEvent")(loot.eventFrame, "CHAT_MSG_LOOT", unpackValues(payload, 1, 12))
	assert_eq(#loot.Entries(), 1, "event forwarding uses the chat GUID to identify the local looter")
	local item = loot.Entries()[1]
	assert_eq(item.kind, "item")
	assert_eq(item.text, "Linen Cloth")
	assert_eq(item.link, "item:12345::::::::70:257::::::")
	assert_eq(item.icon, "Interface\\Icons\\INV_Misc_Cloth_01")
	assert_eq(item.quantity, 3)
	assert_eq(item.value, 360, "item value includes the looted quantity")
	assert_eq(item.valueLabel, "Vendor")
	assert_eq(item.vendorValue, 360, "the total vendor sell worth is retained separately")
	assert_eq(item.quality, 2, "item quality comes from item data")
	assert_eq(loot.window.rows[1].quality:GetText(), "UNCOMMON", "the item quality is stated explicitly")
	assert_eq(loot.window.rows[1].amount:GetText(), "+3", "the looted stack amount is displayed explicitly")
	assert_eq(loot.window.rows[1].value:GetText(), "Vendor: 3s 60c", "vendor worth is clearly visible beside quantity")
	local tooltip = {}
	function tooltip:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
	function tooltip:SetHyperlink(value) self.link = value end
	function tooltip:Show() self.shown = true end
	function tooltip:Hide() self.shown = false end
	_G.GameTooltip = tooltip
	local itemRow = loot.window.rows[1]
	itemRow:GetScript("OnEnter")(itemRow)
	assert_eq(tooltip.owner, itemRow)
	assert_eq(tooltip.anchor, "ANCHOR_RIGHT")
	assert_eq(tooltip.link, "item:12345::::::::70:257::::::", "hover shows the item tooltip from its stored item string")
	assert_true(tooltip.shown)
	itemRow:GetScript("OnLeave")(itemRow)
	assert_false(tooltip.shown, "the item tooltip closes when the pointer leaves the loot row")
	loot.SetSkin("minimal")
	assert_eq(loot.window.rows[1].quality:GetText(), "UNCOMMON", "quality text stays visible with the transparent Minimal skin")
	local _, _, _, qualityAlpha = loot.window.rows[1].quality:GetTextColor()
	assert_eq(qualityAlpha, 1, "the Minimal skin does not fade out the quality label")
	assert_near(item.color[1], 30 / 255, 1e-6)
	assert_near(item.color[2], 1, 1e-6)
	assert_true(loot.window:IsShown())
	assert_eq(loot.window.title, nil, "popup does not add a generic title")
	assert_eq(loot.window:GetScript("OnUpdate") ~= nil, true, "timed rows expire without an idle update")
end)

T.register("loot window: full style preview shows qualities, respects styling and restores live loot", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	local legacy = { schema = 3, lootWindow = { backgroundAlpha = 0.78, width = 333 } }
	e.ns.MigrateDatabase(legacy)
	assert_eq(legacy.schema, 4)
	assert_eq(legacy.lootWindow.skin, "glass")
	assert_eq(legacy.lootWindow.backgroundAlpha, 0.24, "legacy opacity defaults become transparent glass")
	assert_eq(legacy.lootWindow.width, 333, "migration preserves custom dimensions")
	_G.UnitName = function() return "Tester", "Realm" end
	Mocks.now = 10
	loot.SetEnabled(true)
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 1 gold.", "Tester")
	local savedStyle = loot.Style()
	savedStyle.maxRows = 2
	savedStyle.width = 333
	loot.SetStyle(savedStyle)
	loot.Preview()
	assert_true(loot.Entries()[1].isPreview)
	assert_eq(#loot.Entries(), 9, "the preview expands past maxRows to show every sample")
	assert_eq(loot.Entries()[1].quality, 0)
	assert_eq(loot.Entries()[5].quality, 4)
	assert_eq(loot.Entries()[6].quality, 5)
	assert_eq(loot.Entries()[7].kind, "currency")
	assert_eq(loot.Entries()[8].kind, "money")
	assert_eq(loot.Entries()[9].kind, "reputation")
	assert_eq(loot.window.rows[1].quality:GetText(), "POOR")
	assert_eq(loot.window.rows[9]:IsShown(), true, "the complete preview feed is visible")
	assert_eq(loot.window:GetWidth(), 333, "the preview uses the saved width")
	Mocks.now = 13
	loot.window:GetScript("OnUpdate")(loot.window, 3)
	assert_eq(#loot.Entries(), 9, "the preview stays active while adjusting the appearance")
	local appearance = loot.Style()
	appearance.width, appearance.frameStrata = 480, "HIGH"
	loot.SetStyle(appearance)
	assert_eq(loot.window:GetWidth(), 480, "style changes are previewed immediately")
	assert_eq(loot.window:GetFrameStrata(), "HIGH", "strata changes are previewed immediately")
	assert_false(loot.Preview(), "clicking preview again exits it")
	assert_eq(#loot.Entries(), 1)
	assert_eq(loot.Entries()[1].kind, "money", "the preview restores actual loot rather than discarding it")
end)

T.register("loot window: money, currency, reputation filters and duration behave safely", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	_G.UnitName = function() return "Tester", "Realm" end
	_G.C_CurrencyInfo = { GetCurrencyInfo = function() return { iconFileID = 9876 } end }
	Mocks.now = 20
	loot.SetEnabled(true)
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 1 gold, 25 silver, 30 copper.", "Tester")
	loot.HandleEvent("CHAT_MSG_CURRENCY", "You receive currency: |cffffffff|Hcurrency:42|h[Honor]|h|rx12", "Tester")
	loot.HandleEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your reputation with Example increased by 25.", "Tester")
	local rows = loot.Entries()
	assert_eq(#rows, 3)
	assert_eq(rows[1].kind, "reputation")
	assert_eq(rows[1].text, "Example")
	assert_eq(rows[1].amountText, "+25 rep")
	assert_eq(rows[2].kind, "currency")
	assert_eq(rows[2].text, "Honor")
	assert_eq(rows[2].amountText, "+12")
	assert_eq(rows[2].icon, 9876, "currency hyperlinks resolve their icon when available")
	assert_true(rows[2].text:find("Honor", 1, true) ~= nil, "currency links display their readable name")
	assert_eq(rows[3].kind, "money")
	assert_eq(rows[3].text, "Money")
	assert_eq(rows[3].amountText, "+1g 25s 30c")
	assert_eq(rows[3].icon, "Interface\\Icons\\INV_Misc_Coin_03", "money rows choose a coin icon matching the denomination")
	assert_eq(loot.window.rows[1].amount:GetText(), "+25 rep", "reputation gain is displayed as a right-side amount")
	assert_eq(loot.window.rows[2].amount:GetText(), "+12", "currency quantity is displayed beside its name")
	assert_eq(loot.window.rows[3].amount:GetText(), "+1g 25s 30c", "money uses compact gold/silver/copper totals")
	loot.SetCategory("money", false)
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 9 gold.", "Tester")
	assert_eq(#loot.Entries(), 3, "disabled categories do not create rows")
	loot.SetStyle(style({ maxRows = 2 }))
	assert_eq(#loot.Entries(), 2, "the row limit also trims an open feed")
	loot.Clear()
	loot.SetCategory("money", true)
	loot.SetStyle(style({ duration = 0 }))
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 1 gold.", "Tester")
	Mocks.now = 100
	if loot.window:GetScript("OnUpdate") then loot.window:GetScript("OnUpdate")(loot.window, 1) end
	assert_eq(#loot.Entries(), 1, "zero seconds keeps rows until cleared or replaced")
	loot.Clear()
	loot.SetStyle(style({ duration = 2 }))
	Mocks.now = 101
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 1 gold.", "Tester")
	Mocks.now = 104
	loot.window:GetScript("OnUpdate")(loot.window, 3)
	assert_eq(#loot.Entries(), 0)
	assert_false(loot.window:IsShown())
	loot.SetEnabled(false)
	assert_false(loot.eventFrame._events.CHAT_MSG_MONEY)
end)

T.register("loot window: repeated gains aggregate until the popup duration expires", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	_G.UnitName = function() return "Tester", "Realm" end
	_G.GetItemInfoInstant = function(itemID) return itemID, 0, 0, "", "Interface\\Icons\\INV_Misc_Cloth_01" end
	_G.GetItemInfo = function()
		return "Linen Cloth", "|Hitem:12345::::::::70:257::::::|h[Linen Cloth]|h", 2, 1, 0,
			"Trade Goods", "Cloth", 20, "", "Interface\\Icons\\INV_Misc_Cloth_01", 120
	end
	local previousTSMAPI = _G.TSM_API
	_G.TSM_API = { GetCustomPriceValue = function() return 1000 end }
	Mocks.now = 10
	loot.SetStyle(style({ duration = 8, maxRows = 12 }))
	loot.SetEnabled(true)
	local linen = "|cff1eff00|Hitem:12345::::::::70:257::::::|h[Linen Cloth]|h|r"
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 10 silver.", "Tester")
	loot.HandleEvent("CHAT_MSG_LOOT", "You receive loot: " .. linen .. "x1.", "Tester")
	loot.HandleEvent("CHAT_MSG_CURRENCY", "You receive currency: |cffffffff|Hcurrency:42|h[Honor]|h|rx12", "Tester")
	loot.HandleEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your reputation with Example increased by 25.", "Tester")
	Mocks.now = 13
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 5 silver.", "Tester")
	loot.HandleEvent("CHAT_MSG_LOOT", "You receive loot: " .. linen .. "x2.", "Tester")
	loot.HandleEvent("CHAT_MSG_CURRENCY", "You receive currency: |cffffffff|Hcurrency:42|h[Honor]|h|rx3", "Tester")
	loot.HandleEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your reputation with Example increased by 5.", "Tester")
	local rows = loot.Entries()
	assert_eq(#rows, 4, "each repeated source updates its existing row")
	local byKind = {}
	for _, row in ipairs(rows) do byKind[row.kind] = row end
	assert_eq(byKind.money.amountText, "+15s", "money is summed in copper across events")
	assert_eq(byKind.item.quantity, 3, "matching item stacks are combined")
	assert_eq(byKind.item.value, 3000, "market estimate is recalculated for the combined quantity")
	assert_eq(byKind.item.valueLabel, "AH")
	assert_eq(byKind.item.vendorValue, 360, "combined quantity retains its total vendor worth")
	local itemRow
	for index, row in ipairs(rows) do if row.kind == "item" then itemRow = loot.window.rows[index]; break end end
	assert_eq(itemRow.value:GetText(), "Vendor: 3s 60c", "the visible card prioritizes explicit vendor worth")
	local tooltip = {}
	function tooltip:SetOwner() end
	function tooltip:SetHyperlink() end
	function tooltip:AddLine(text) self.marketLine = text end
	function tooltip:Show() self.shown = true end
	_G.GameTooltip = tooltip
	itemRow:GetScript("OnEnter")(itemRow)
	assert_eq(tooltip.marketLine, "Auction estimate: 30s", "the optional market estimate remains available on hover")
	_G.TSM_API = previousTSMAPI
	assert_eq(byKind.currency.amountText, "+15", "the same currency is summed")
	assert_eq(byKind.reputation.amountText, "+30 rep", "reputation gains for the same faction are summed")
	assert_eq(byKind.money.expires, 21, "a repeated gain refreshes the row's display timer")
	Mocks.now = 22
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 5 silver.", "Tester")
	assert_eq(#loot.Entries(), 1, "gains after the display window start a fresh row")
	assert_eq(loot.Entries()[1].amountText, "+5s", "expired amounts are not included in later totals")
end)

T.register("loot window: saved drag position, skin appearance and settings page", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	local f = e.ns.OpenOptions("loot")
	assert_eq(f.selectedTab, "loot")
	assert_true(f.lootPage:IsShown())
	assert_eq(f.pageTitle:GetText(), "Loot window")
	local savedStyle = loot.Style()
	savedStyle.width = 333
	loot.SetStyle(savedStyle)
	f.RefreshLoot()
	assert_eq(f.controls.lootWidth:GetText(), "333", "refresh preserves a saved width between slider steps")
	click(f.controls.lootWindowEnabled, true)
	assert_true(loot.Enabled())
	assert_true(loot.eventFrame._events.CHAT_MSG_LOOT)
	loot.Preview()
	local frame = loot.window
	assert_true(frame:IsShown())
	frame.dragHandle:GetScript("OnDragStart")(frame.dragHandle)
	assert_true(frame._moving)
	frame.GetCenter = function() return 350, 450 end
	frame.dragHandle:GetScript("OnDragStop")(frame.dragHandle)
	assert_false(frame._moving)
	assert_eq(e.ns.db.lootWindow.x, 250)
	assert_eq(e.ns.db.lootWindow.y, 350)
	local initialPoint = { frame:GetPoint(1) }
	assert_eq(initialPoint[4], 0, "dragging persists position without resetting its live anchor")
	click(f.controls.lootQualityColors, false)
	assert_false(e.ns.db.lootWindow.qualityColors)
	f.controls.lootFontSize:SetText("17")
	f.controls.lootIconSize:SetText("30")
	f.controls.lootWidth:SetText("400")
	f.controls.lootWidthSlider:SetValue(500)
	assert_eq(f.controls.lootWidth:GetText(), "500", "the width slider stages a readable popup width")
	f.controls.lootWidth:SetText("400")
	f.controls.lootDuration:SetText("0")
	f.controls.lootMaxRows:SetText("8")
	f.controls.lootOpacity:SetText("0.8")
	f.controls.lootBackgroundAlpha:SetText("0.4")
	click(f.controls.lootApply)
	assert_eq(e.ns.db.lootWindow.fontSize, 17)
	assert_eq(e.ns.db.lootWindow.iconSize, 30)
	assert_eq(e.ns.db.lootWindow.width, 400)
	assert_eq(e.ns.db.lootWindow.duration, 0)
	assert_eq(e.ns.db.lootWindow.maxRows, 8)
	assert_eq(e.ns.db.lootWindow.backgroundAlpha, 0.4)
	click(f.controls.lootSizeCompact)
	assert_eq(f.controls.lootWidth:GetText(), "350")
	assert_eq(f.controls.lootFontSize:GetText(), "12")
	assert_eq(f.controls.lootIconSize:GetText(), "28")
	click(f.controls.lootSizeLarge)
	assert_eq(e.ns.db.lootWindow.width, 400, "size presets only stage settings until Apply")
	assert_eq(f.controls.lootWidth:GetText(), "560")
	assert_eq(f.controls.lootFontSize:GetText(), "18")
	assert_eq(f.controls.lootIconSize:GetText(), "56")
	click(f.controls.lootApply)
	assert_eq(e.ns.db.lootWindow.width, 560)
	assert_eq(e.ns.db.lootWindow.fontSize, 18)
	assert_eq(e.ns.db.lootWindow.iconSize, 56)
	click(f.controls.lootTextLayout)
	assert_true(f.lootTextLayoutPanel:IsShown())
	f.controls.lootLabelXOffset:SetValue(25)
	f.controls.lootLabelYOffset:SetValue(-10)
	f.controls.lootAmountXOffset:SetValue(-15)
	f.controls.lootAmountYOffset:SetValue(6)
	click(f.controls.lootFontFace)
	click(f.controls.lootFontOutline)
	assert_eq(f.controls.lootLabelXOffset:GetValue(), 25)
	assert_eq(f.controls.lootLabelYOffset:GetValue(), -10)
	assert_eq(f.controls.lootAmountXOffset:GetValue(), -15)
	assert_eq(f.controls.lootAmountYOffset:GetValue(), 6)
	assert_true(f.controls.lootFrameStrata:GetText():find("DIALOG", 1, true) ~= nil)
	click(f.controls.lootFrameStrata)
	assert_true(f.controls.lootFrameStrata:GetText():find("FULLSCREEN", 1, true) ~= nil)
	assert_eq(f.controls.lootLayoutMessage:GetText(), "Window strata selected; click Apply text style to save.")
	click(f.controls.lootLayoutApply)
	assert_eq(f.controls.lootLayoutMessage:GetText(), "Text layout, font, and strata saved.")
	assert_eq(e.ns.db.lootWindow.labelXOffset, 25)
	assert_eq(e.ns.db.lootWindow.labelYOffset, -10)
	assert_eq(e.ns.db.lootWindow.amountXOffset, -15)
	assert_eq(e.ns.db.lootWindow.amountYOffset, 6)
	assert_eq(e.ns.db.lootWindow.fontFace, "friz")
	assert_eq(e.ns.db.lootWindow.fontOutline, "outline")
	assert_eq(e.ns.db.lootWindow.frameStrata, "FULLSCREEN")
	assert_eq(frame:GetFrameStrata(), "FULLSCREEN")
	local namePoint, amountPoint = frame.rows[1].name._points[1], frame.rows[1].amount._points[1]
	assert_eq(namePoint[4], 35, "label X offsets move the name anchor relative to its default")
	assert_eq(namePoint[5], -3, "label Y offsets move the name anchor relative to its default")
	assert_eq(amountPoint[4], -17, "quantity X offsets move its right anchor")
	assert_eq(amountPoint[5], 13, "quantity Y offsets move its row position")
	local fontPath, _, fontFlags = frame.rows[1].name:GetFont()
	assert_eq(fontPath, "Fonts\\FRIZQT__.TTF")
	assert_eq(fontFlags, "OUTLINE")
	click(f.controls.lootLayoutClose)
	assert_false(f.lootTextLayoutPanel:IsShown())
	click(f.lootSkinButtons.glass)
	assert_eq(loot.Style().skin, "glass")
	click(f.lootSkinButtons.arcane)
	assert_eq(loot.Style().skin, "arcane")
	assert_true(frame._borderColor[3] > 0, "skin presets style the popup border independently")
	e.ns.lootWindow.ApplyStyle()
	assert_true(frame._backdropColor[4] < 0.8, "loot window keeps its own opacity over the shared skin")
	click(f.controls.lootClear)
	assert_false(frame:IsShown())
	click(f.controls.lootPreview)
	assert_true(frame:IsShown())
	click(f.controls.lootWindowTab)
	assert_eq(f.selectedTab, "loot")
	assert_true(f.controls.lootWindowEnabled:GetChecked())
end)

T.register("loot window: item value resolves when client item data arrives", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	_G.UnitName = function() return "Tester", "Realm" end
	_G.GetItemInfoInstant = function() return 2468, 0, 0, "", "Interface\\Icons\\INV_Misc_Gem_01" end
	_G.GetItemInfo = function() return nil end
	_G.C_Item = {
		RequestLoadItemDataByID = function(id) Mocks.requestedItem = id end,
	}
	loot.SetEnabled(true)
	local link = "|cff0070dd|Hitem:2468::::::::70::::|h[Blue Gem]|h|r"
	assert_true(loot.HandleEvent("CHAT_MSG_LOOT", "You receive loot: " .. link, "Tester"))
	assert_eq(loot.Entries()[1].value, nil)
	assert_eq(Mocks.requestedItem, 2468)
	_G.GetItemInfo = function()
		return "Blue Gem", link, 3, 1, 0, "Gem", "Gem", 20, "", "Interface\\Icons\\INV_Misc_Gem_01", 75
	end
	loot.eventFrame:GetScript("OnEvent")(loot.eventFrame, "GET_ITEM_INFO_RECEIVED", 2468, true)
	assert_eq(loot.Entries()[1].value, 75)
	assert_eq(loot.Entries()[1].valueLabel, "Vendor")
end)

T.register("loot window: appearance validation is atomic and saved position restores", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	local before = e.ns.db.lootWindow.width
	local ok = loot.SetStyle(style({ width = 1000 }))
	assert_false(ok)
	assert_eq(e.ns.db.lootWindow.width, before)
	local invalidPosition = loot.Style()
	invalidPosition.width, invalidPosition.labelXOffset = 500, 121
	assert_false(loot.SetStyle(invalidPosition), "invalid text offsets reject the entire style draft")
	assert_eq(e.ns.db.lootWindow.width, before, "invalid position does not partially save width")
	local invalidFont = loot.Style()
	invalidFont.fontFace = "unknown"
	assert_false(loot.SetStyle(invalidFont), "unknown font keys are rejected")
	local invalidStrata = loot.Style()
	invalidStrata.width, invalidStrata.frameStrata = 500, "NOT_A_STRATA"
	assert_false(loot.SetStyle(invalidStrata), "unsupported frame strata are rejected")
	assert_eq(e.ns.db.lootWindow.width, before, "invalid strata does not partially save other appearance values")
	loot.Preview()
	local frame = loot.window
	frame.GetCenter = function() return 300, 275 end
	loot.SavePosition()
	assert_eq(e.ns.db.lootWindow.x, 200)
	assert_eq(e.ns.db.lootWindow.y, 175)
	loot.window = nil -- simulate a fresh login creating the floating frame again
	loot.Preview()
	local restoredPoint = { loot.window:GetPoint(1) }
	assert_eq(restoredPoint[4], 200)
	assert_eq(restoredPoint[5], 175)
end)
