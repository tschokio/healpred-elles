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
	assert_eq(loot.window.rows[1].quantity:GetText(), "3", "stack amount appears on the item icon")
	assert_near(item.color[1], 30 / 255, 1e-6)
	assert_near(item.color[2], 1, 1e-6)
	assert_true(loot.window:IsShown())
	assert_eq(loot.window.title, nil, "popup does not add a generic title")
	assert_eq(loot.window:GetScript("OnUpdate") ~= nil, true, "timed rows expire without an idle update")
end)

T.register("loot window: labeled style preview preserves live entries and upgrades glass defaults", function()
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
	loot.Preview()
	assert_true(loot.Entries()[1].isPreview)
	Mocks.now = 13
	loot.window:GetScript("OnUpdate")(loot.window, 3)
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
	loot.HandleEvent("CHAT_MSG_MONEY", "You loot 2 gold, 3 silver.", "Tester")
	loot.HandleEvent("CHAT_MSG_CURRENCY", "You receive currency: |cffffffff|Hcurrency:42|h[Honor]|h|r", "Tester")
	loot.HandleEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", "Your reputation with Example increased by 25.", "Tester")
	local rows = loot.Entries()
	assert_eq(#rows, 3)
	assert_eq(rows[1].kind, "reputation")
	assert_eq(rows[2].kind, "currency")
	assert_eq(rows[2].icon, 9876, "currency hyperlinks resolve their icon when available")
	assert_true(rows[2].text:find("Honor", 1, true) ~= nil, "currency links display their readable name")
	assert_eq(rows[3].kind, "money")
	assert_eq(rows[3].icon, "Interface\\Icons\\INV_Misc_Coin_03", "money rows choose a coin icon matching the denomination")
	assert_true(rows[3].text:find("2 gold", 1, true) ~= nil)
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

T.register("loot window: saved drag position, skin appearance and settings page", function()
	local e = Mocks.NewEnv()
	local loot = e.ns.lootWindow
	local f = e.ns.OpenOptions("loot")
	assert_eq(f.selectedTab, "loot")
	assert_true(f.lootPage:IsShown())
	assert_eq(f.pageTitle:GetText(), "Loot window")
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
