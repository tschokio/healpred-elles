-- Work around EllesmereUI Action Bars' pushed-state polling for German umlauts.
-- IsKeyDown() can fail to recognize the non-ASCII key token returned by
-- GetBindingKey(), so the pressed texture is hidden before the key is released.
-- Track the action-button down/up callbacks instead; this does not change the
-- binding or action dispatch itself.
local function bindingHasUmlaut(command)
	if type(command) ~= "string" or type(GetBindingKey) ~= "function" then return false end
	local first, second = GetBindingKey(command)
	local umlauts = { "ä", "ö", "ü", "Ä", "Ö", "Ü" }
	for _, key in ipairs({ first, second }) do
		if type(key) == "string" then
			for _, umlaut in ipairs(umlauts) do
				if key:sub(-#umlaut) == umlaut then return true end
			end
		end
	end
	return false
end

local held = setmetatable({}, { __mode = "k" })
local hookedTextures = setmetatable({}, { __mode = "k" })

local function beginPress(button, command)
	if not button or not bindingHasUmlaut(command) then return end
	local texture = button.PushedTexture
	if not texture then return end

	held[button] = true
	if not hookedTextures[texture] and type(texture.HookScript) == "function" then
		hookedTextures[texture] = true
		texture:HookScript("OnHide", function(self)
			-- EllesmereUI's IsKeyDown poll may hide the texture while the key is
			-- still held. Re-show it until the corresponding native key-up arrives.
			if held[button] and button.PushedTexture == self then self:Show() end
		end)
	end
	texture:Show()
end

local function endPress(button)
	if not button or not held[button] then return end
	held[button] = nil
	local texture = button.PushedTexture
	if texture then texture:Hide() end
end

local multiBars = {
	MultiBarBottomLeft = 1,
	MultiBarBottomRight = 2,
	MultiBarRight = 3,
	MultiBarLeft = 4,
	MultiBar5 = 5,
	MultiBar6 = 6,
	MultiBar7 = 7,
}

local function hookActionBarCallbacks()
	if type(hooksecurefunc) ~= "function" then return end
	if type(ActionButtonDown) == "function" and type(ActionButtonUp) == "function" then
		hooksecurefunc("ActionButtonDown", function(id)
			local button = _G["ActionButton" .. tostring(id)]
			beginPress(button, "ACTIONBUTTON" .. tostring(id))
		end)
		hooksecurefunc("ActionButtonUp", function(id)
			endPress(_G["ActionButton" .. tostring(id)])
		end)
	end

	if type(MultiActionButtonDown) == "function" and type(MultiActionButtonUp) == "function" then
		hooksecurefunc("MultiActionButtonDown", function(barName, id)
			local barIndex = multiBars[barName]
			if not barIndex then return end
			local buttonName = tostring(barName) .. "Button" .. tostring(id)
			local command = "MULTIACTIONBAR" .. barIndex .. "BUTTON" .. tostring(id)
			beginPress(_G[buttonName], command)
		end)
		hooksecurefunc("MultiActionButtonUp", function(barName, id)
			local barIndex = multiBars[barName]
			if not barIndex then return end
			endPress(_G[tostring(barName) .. "Button" .. tostring(id)])
		end)
	end
end

-- OptionalDeps ensures EllesmereUIActionBars loads first when it is installed.
-- Only install the visual shim when that addon is actually enabled.
local isLoaded = IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)
if type(isLoaded) == "function" then
	local ok, loaded = pcall(isLoaded, "EllesmereUIActionBars")
	if ok and loaded then hookActionBarCallbacks() end
end
