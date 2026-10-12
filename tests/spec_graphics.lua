local defaults = {
	groundEffectDensity = 16, groundEffectFade = 70, groundEffectDist = 70,
	lodObjectFadeScale = 100, lodObjectCullSize = 15, terrainLodDist = 400,
	ResampleAlwaysSharpen = 0, reflectionMode = 0,
}
local function click(w) w:GetScript("OnClick")(w) end
local function env(modern)
	local e = Mocks.NewEnv()
	local values, writes = {}, {}
	for name, value in pairs(defaults) do values[name] = value end
	GetCVar, SetCVar, GetCVarDefault, C_CVar = nil, nil, nil, nil
	local api = {
		GetCVar = function(name) return values[name] ~= nil and tostring(values[name]) or nil end,
		GetCVarDefault = function(name) return defaults[name] ~= nil and tostring(defaults[name]) or nil end,
		SetCVar = function(name, value) values[name] = tonumber(value); writes[#writes + 1] = { name, value } end,
	}
	if modern then C_CVar = api else GetCVar, SetCVar, GetCVarDefault = api.GetCVar, api.SetCVar, api.GetCVarDefault end
	e.values, e.writes, e.cvars = values, writes, api
	return e
end

T.register("graphics: page navigation is clean and opening never writes CVars", function()
	local e = env()
	local f = e.ns.OpenOptions("graphics")
	assert_eq(f.selectedTab, "graphics"); assert_true(f.graphicsPage:IsShown())
	assert_false(f.preview:IsShown()); assert_false(f.helpPanel:IsShown()); assert_false(f.weaponPage:IsShown())
	assert_eq(#e.writes, 0)
	for _, entry in ipairs(e.ns.graphics.entries) do
		assert_eq(f.graphicsPage.rows[entry.name].input:GetText(), tostring(defaults[entry.name]))
	end
	f.controls.graphics_groundEffectDensity:SetFocus()
	click(f.controls.notesTab)
	assert_false(f.graphicsPage:IsShown()); assert_false(f.controls.graphics_groundEffectDensity:HasFocus())
	click(f.controls.graphicsTab)
	click(f.controls.graphicsExport); click(f.controls.graphicsSelectAll)
	assert_true(f.controls.graphicsExportText:HasFocus())
	click(f.controls.close); assert_false(f.controls.graphicsExportText:HasFocus())
	assert_nil(f.graphicsPage:GetScript("OnUpdate")); assert_eq(#e.writes, 0)
end)

T.register("graphics: sliders stage both directions and the exact supplied preset applies", function()
	local e = env(true)
	local f = e.ns.OpenOptions("graphics")
	click(f.controls.graphicsPreset); assert_eq(#e.writes, 0)
	click(f.controls.graphicsApply)
	for _, entry in ipairs(e.ns.graphics.entries) do assert_eq(e.values[entry.name], entry.preset) end
	for _, entry in ipairs(e.ns.graphics.entries) do
		local row = f.graphicsPage.rows[entry.name]
		if row.slider then
			row.slider:SetValue(entry.min); assert_eq(e.values[entry.name], entry.preset)
			click(f.controls.graphicsApply); assert_eq(e.values[entry.name], entry.min)
			row.slider:SetValue(entry.max); click(f.controls.graphicsApply); assert_eq(e.values[entry.name], entry.max)
		end
	end
	local toggle = f.graphicsPage.rows.ResampleAlwaysSharpen.toggle
	toggle:SetChecked(false); click(toggle); click(f.controls.graphicsApply)
	assert_eq(e.values.ResampleAlwaysSharpen, 0)
	f.controls.graphics_reflectionMode:SetText("4"); click(f.controls.graphicsApply)
	assert_eq(e.values.reflectionMode, 4)
	for value = 0, 4 do
		click(f.controls.graphicsReflection); click(f.controls.graphicsApply)
		assert_eq(e.values.reflectionMode, value)
	end
	click(f.controls.graphicsRestore)
	for name, value in pairs(defaults) do assert_eq(e.values[name], value) end
	assert_nil(e.ns.db.graphics)
end)

T.register("graphics: named presets stage safely and herb mode minimizes clutter without hiding small objects", function()
	local e = env()
	local f = e.ns.OpenOptions("graphics")
	for _, preset in ipairs({
		{ "graphicsPreset", "dense" },
		{ "graphicsBalancedPreset", "balanced" },
		{ "graphicsHerbPreset", "herbs" },
		{ "graphicsBeyondUltra", "beyondUltra" },
	}) do
		local writes = #e.writes
		click(f.controls[preset[1]])
		assert_eq(#e.writes, writes, "preset selection only stages drafts")
		for name, value in pairs(e.ns.graphics.presets[preset[2]]) do
			assert_eq(f.controls["graphics_" .. name]:GetText(), tostring(value))
		end
		if preset[2] == "herbs" then
			assert_true(f.graphicsPage.message:GetText():find("Some effects cannot be fully disabled", 1, true))
		end
		click(f.controls.graphicsApply)
		for name, value in pairs(e.ns.graphics.presets[preset[2]]) do assert_eq(e.values[name], value) end
	end
	assert_eq(e.ns.graphics.presets.herbs.groundEffectDensity, 16)
	assert_eq(e.ns.graphics.presets.herbs.lodObjectCullSize, 1, "small world objects remain visible")
	assert_eq(e.ns.graphics.presets.herbs.lodObjectFadeScale, 300, "distant world objects remain visible longer")
	assert_eq(e.ns.graphics.presets.beyondUltra.groundEffectDist, 500)
	assert_eq(e.ns.graphics.presets.beyondUltra.terrainLodDist, 2000)
	assert_eq(e.ns.graphics.presets.beyondUltra.reflectionMode, 4, "the client-posted fifth reflection mode is staged")
end)

T.register("graphics: validation is atomic and unrelated CVars are never accepted", function()
	local e = env()
	local G = e.ns.graphics
	for _, bad in ipairs({ -1, 257, 1.5, "bad", "1; /run evil()", math.huge, 0/0, Mocks.MakeSecret() }) do
		local ok = G.Apply({ groundEffectDensity = bad, groundEffectDist = 500 })
		assert_false(ok); assert_eq(#e.writes, 0)
	end
	assert_false(G.Apply({ Sound_EnableAllSound = 0 })); assert_eq(#e.writes, 0)
	Mocks.inCombat = true
	assert_false(G.Apply({ groundEffectDensity = 256 })); assert_eq(#e.writes, 0)
	Mocks.inCombat = false
end)

T.register("graphics: unsupported APIs and CVars are omitted and cannot crash or be written", function()
	local e = env()
	e.values.reflectionMode = nil
	local f = e.ns.OpenOptions("graphics")
	assert_eq(f.controls.graphics_reflectionMode:GetText(), "N/A")
	assert_false(f.controls.graphicsReflection:IsEnabled())
	assert_false(e.ns.graphics.Apply({ groundEffectDensity = 256, reflectionMode = 3 }))
	assert_eq(#e.writes, 0)
	local text, count = e.ns.graphics.Export()
	assert_eq(count, 7); assert_false(text:find("reflectionMode", 1, true))
	GetCVar = function() error("unknown cvar") end
	assert_nil(e.ns.graphics.Read("groundEffectDensity"))
	GetCVar = function() return Mocks.MakeSecret() end
	assert_nil(e.ns.graphics.Read("groundEffectDensity"))
	GetCVar, SetCVar, GetCVarDefault = nil, nil, nil
	f.graphicsPage.Refresh()
	assert_false(e.ns.graphics.Apply({ groundEffectDensity = 256 }))
	text, count = e.ns.graphics.Export(); assert_eq(text, ""); assert_eq(count, 0)
end)

T.register("graphics: client clamps and false or erroring setters roll back with honest status", function()
	for _, mode in ipairs({ "clamp", "false", "error", "ignore" }) do
		local e = env()
		local set = SetCVar
		SetCVar = function(name, value)
			if name == "groundEffectDist" and tonumber(value) == 500 then
				if mode == "error" then error("blocked") end
				if mode == "false" then return false end
				if mode == "clamp" then set(name, "400") end
				return
			end
			return set(name, value)
		end
		local ok, message = e.ns.graphics.Apply({ groundEffectDensity = 256, groundEffectDist = 500 })
		assert_false(ok); assert_true(message:find("Previous values restored", 1, true))
		if mode == "clamp" then assert_true(message:find("read back 400", 1, true)) end
		if mode == "false" then assert_true(message:find("setter reported failure", 1, true)) end
		assert_eq(e.values.groundEffectDensity, 16); assert_eq(e.values.groundEffectDist, 70)
	end
	local e = env()
	SetCVar = function(name, value) e.values[name] = tonumber(value) == 256 and 200 or 100 end
	local ok, message = e.ns.graphics.Apply({ groundEffectDensity = 256 })
	assert_false(ok); assert_true(message:find("Rollback incomplete", 1, true))
end)

T.register("graphics: rejected preset keeps its staged values and names the incompatible CVar", function()
	local e = env()
	local f = e.ns.OpenOptions("graphics")
	local set = SetCVar
	SetCVar = function(name, value)
		if name == "groundEffectDist" and tonumber(value) == 600 then return false end
		return set(name, value)
	end
	click(f.controls.graphicsPreset)
	click(f.controls.graphicsApply)
	assert_eq(e.values.groundEffectDensity, defaults.groundEffectDensity, "failed preset rolls back earlier writes")
	assert_eq(f.controls.graphics_groundEffectDist:GetText(), "600", "failed draft remains visible for adjustment")
	assert_true(f.graphicsPage.message:GetText():find("groundEffectDist", 1, true))
	assert_true(f.graphicsPage.message:GetText():find("Draft kept", 1, true))
	click(f.controls.graphicsRefresh)
	assert_eq(f.controls.graphics_groundEffectDist:GetText(), tostring(defaults.groundEffectDist), "Read current explicitly discards the failed draft")
end)

T.register("graphics: export is current-only copyable text and editing it never executes commands", function()
	local e = env()
	local f = e.ns.OpenOptions("graphics")
	click(f.controls.graphicsPreset); click(f.controls.graphicsExport)
	local share = f.controls.graphicsExportText
	assert_true(share:GetText():find("/console groundEffectDensity 16", 1, true))
	click(f.controls.graphicsApply); click(f.controls.graphicsExport)
	for _, entry in ipairs(e.ns.graphics.entries) do
		assert_true(share:GetText():find("/console " .. entry.name .. " " .. entry.preset, 1, true))
	end
	click(f.controls.graphicsSelectAll); assert_eq(share:GetSelectedText(), share:GetText())
	local writes = #e.writes
	share:SetText("/run evil()\n/console unknown 1"); assert_eq(#e.writes, writes)
	e.values.groundEffectDensity = 128
	e.ns.OpenOptions("graphics"); assert_eq(f.controls.graphics_groundEffectDensity:GetText(), "128")
	assert_eq(share:GetText(), "/run evil()\n/console unknown 1", "refresh never destroys copy selection text")
end)

T.register("graphics: defaults are client supplied and stage without writing or inventing missing values", function()
	local e = env(true)
	local f = e.ns.OpenOptions("graphics")
	click(f.controls.graphicsPreset)
	C_CVar.GetCVarDefault = function(name) return name ~= "groundEffectFade" and tostring(defaults[name]) or nil end
	click(f.controls.graphicsDefaults)
	assert_eq(#e.writes, 0)
	assert_eq(f.controls.graphics_groundEffectFade:GetText(), "600")
	assert_eq(f.controls.graphics_groundEffectDensity:GetText(), "16")
	assert_true(f.graphicsPage.message:GetText():find("1 defaults unavailable", 1, true))
	click(f.controls.graphicsApply); assert_eq(e.values.groundEffectFade, 600)
	click(f.controls.graphicsRefresh); assert_eq(f.controls.graphics_groundEffectFade:GetText(), "600")
	-- Existing values outside practical bounds must not block unrelated edits.
	e.values.lodObjectFadeScale = 400.5
	f.graphicsPage.Refresh(); f.controls.graphics_groundEffectDensity:SetText("128")
	click(f.controls.graphicsApply)
	assert_eq(e.values.groundEffectDensity, 128); assert_eq(e.values.lodObjectFadeScale, 400.5)
end)

T.register("graphics: controls fit the full-width page without overlapping and preserve original zero", function()
	local e = env()
	local f = e.ns.OpenOptions("graphics")
	local page = Mocks.FrameRect(f.graphicsPage)
	local widgets = {}
	for _, row in pairs(f.graphicsPage.rows) do
		widgets[#widgets + 1] = row.input
		widgets[#widgets + 1] = row.slider or row.toggle or row.mode
	end
	for _, key in ipairs({ "graphicsPreset", "graphicsBalancedPreset", "graphicsHerbPreset", "graphicsBeyondUltra", "graphicsDefaults", "graphicsRefresh", "graphicsApply", "graphicsRestore", "graphicsExport", "graphicsSelectAll" }) do
		widgets[#widgets + 1] = f.controls[key]
	end
	for i, widget in ipairs(widgets) do
		local r = Mocks.FrameRect(widget)
		assert_true(r.left >= page.left and r.right <= page.right and r.top <= page.top and r.bottom >= page.bottom)
		for j = i + 1, #widgets do assert_false(Mocks.RectsOverlap(r, Mocks.FrameRect(widgets[j]))) end
	end
	assert_true(e.ns.graphics.Apply({ reflectionMode = 3 }))
	assert_true(e.ns.graphics.Apply({ reflectionMode = 2 }))
	assert_eq(e.ns.graphics.original.reflectionMode, 0)
	assert_true(e.ns.graphics.Restore()); assert_eq(e.values.reflectionMode, 0)
	f.controls.graphics_groundEffectDensity:SetText("200")
	assert_eq(f.graphicsPage.rows.groundEffectDensity.slider:GetValue(), 200)
	f.controls.graphics_ResampleAlwaysSharpen:SetText("1")
	assert_true(f.graphicsPage.rows.ResampleAlwaysSharpen.toggle:GetChecked())
	f.controls.graphics_reflectionMode:SetText("2")
	assert_eq(f.controls.graphicsReflection:GetText(), "Mode 2")
	GetCVar, SetCVar, GetCVarDefault, C_CVar = nil, nil, nil, nil
end)
