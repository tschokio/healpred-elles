-- WoW Forever camping references on item and placed-world-object tooltips.
local _, ns = ...

local function safeNumber(value)
	if type(ns) == "table" and type(ns.isSecret) == "function" then
		local ok, secret = pcall(ns.isSecret, value)
		if not ok or secret then return nil end
	end
	if type(ns) == "table" and type(ns.toNumber) == "function" then
		local ok, number = pcall(ns.toNumber, value)
		if ok and type(number) == "number" and number == number and number ~= math.huge and number ~= -math.huge then return number end
		return nil
	end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
	return value
end

local function scaled(brackets)
	return { kind = "scaled", brackets = brackets }
end
local AP = scaled({{1,11,12},{12,21,20},{22,31,32},{32,41,49},{42,51,67},{52,60,90}})
local ITEMS = {
	[279960]={name="Lodestone",perk=AP,exclusive="Blessing of Might",spell=1307254},
	[279948]={name="Rock Garden",perk=AP,exclusive="Blessing of Might",utility="Spawns a common mining node over time"},
	[279952]={name="Molten Foundry",perk=AP,exclusive="Blessing of Might",utility="Enables recipes requiring a Molten Foundry"},
	[279956]={name="Mana Well",perk=scaled({{1,23,10},{24,33,15},{34,43,20},{44,53,24},{54,60,29}}),unit="Mana/5 sec",exclusive="Blessing of Wisdom",spell=1307259},
	[279970]={name="Fermenter",perk=scaled({{1,23,10},{24,33,15},{34,43,20},{44,53,24},{54,60,29}}),unit="Mana/5 sec",exclusive="Blessing of Wisdom",utility="Creates certain reagents"},
	[279990]={name="Alchemy Laboratory",perk=scaled({{1,23,10},{24,33,15},{34,43,20},{44,53,24},{54,60,29}}),unit="Mana/5 sec",exclusive="Blessing of Wisdom",utility="Enables recipes requiring an Alchemy Laboratory"},
	[279944]={name="Sharpening Wheel",perk=scaled({{1,23,6},{24,37,11},{38,51,20},{52,60,34}}),unit="Strength",exclusive="Strength of Earth Totem",spell=1307392},
	[279988]={name="Anvil",perk=scaled({{1,23,6},{24,37,11},{38,51,20},{52,60,34}}),unit="Strength",exclusive="Strength of Earth Totem",utility="Provides a usable anvil"},
	[279955]={name="Master Forge",perk=scaled({{1,23,6},{24,37,11},{38,51,20},{52,60,34}}),unit="Strength",exclusive="Strength of Earth Totem",utility="Enables recipes requiring a Master Forge"},
	[279962]={name="Incense Candle",perk=scaled({{1,13,2},{14,27,6},{28,41,12},{42,55,18},{56,60,25}}),unit="Intellect",exclusive="Arcane Intellect",spell=1307251},
	[279964]={name="Greenhouse",perk=scaled({{1,13,2},{14,27,6},{28,41,12},{42,55,18},{56,60,25}}),unit="Intellect",exclusive="Arcane Intellect",utility="Grows herbs over time from planted seeds"},
	[279947]={name="Seed Hybridizer",perk=scaled({{1,13,2},{14,27,6},{28,41,12},{42,55,18},{56,60,25}}),unit="Intellect",exclusive="Arcane Intellect",utility="Multiplies or combines seeds into rarer tiers"},
	[279972]={name="Faction Banner",perk=scaled({{1,39,14},{40,49,19},{50,59,27},{60,60,32}}),unit="Spirit",exclusive="Divine Spirit",spell=1307240,utility="Buff is Horde-only"},
	[279943]={name="Spinning Wheel",perk=scaled({{1,39,14},{40,49,19},{50,59,27},{60,60,32}}),unit="Spirit",exclusive="Divine Spirit",utility="Creates certain reagents; inherited banner buff is Horde-only"},
	[279959]={name="Loom",perk=scaled({{1,39,14},{40,49,19},{50,59,27},{60,60,32}}),unit="Spirit",exclusive="Divine Spirit",utility="Enables recipes requiring a Loom; inherited banner buff is Horde-only"},
	[279968]={name="First Aid Kit",perk=scaled({{1,11,3},{12,23,8},{24,35,21},{36,47,34},{48,59,45},{60,60,56}}),unit="Stamina",exclusive="Power Word: Fortitude",spell=1307244},
	[279940]={name="Toxin Study",perk=scaled({{1,11,3},{12,23,8},{24,35,21},{36,47,34},{48,59,45},{60,60,56}}),unit="Stamina",exclusive="Power Word: Fortitude",utility="Supports healing potions and anti-venom"},
	[279951]={name="Plague Doctor's Laboratory",perk=scaled({{1,11,3},{12,23,8},{24,35,21},{36,47,34},{48,59,45},{60,60,56}}),unit="Stamina",exclusive="Power Word: Fortitude",utility="Supports healing potions and poultices"},
	[279976]={name="Enchanted Lute",perk="lute",exclusive="Mark of the Wild",spell=1307234},
	[279985]={name="Arcane Salvager",perk="lute",exclusive="Mark of the Wild",utility="Enables more efficient disenchanting"},
	[279987]={name="Arcane Forge",perk="lute",exclusive="Mark of the Wild",utility="Enables recipes requiring an Arcane Forge"},
	[279979]={name="Camp Chair",perk="critical",exclusive="Moonkin Aura"},
	[279969]={name="Field Guide",perk="critical",exclusive="Moonkin Aura",utility="Grants Track Beasts"},
	[279938]={name="Trapper's Workbench",perk="critical",exclusive="Moonkin Aura",utility="Contains one trap"},
	[279967]={name="Fish Bowl",perk="fishing",exclusive="Blessing of Kings"},
	[279965]={name="Fishing Rack",perk="fishing",exclusive="Blessing of Kings",utility="Catch uncommon fish for 1 hour; provides Fishing Skill lures"},
	[279966]={name="Fishing Hut",perk="fishing",exclusive="Blessing of Kings",utility="Catch rare fish for 1 hour; provides Fishing Skill lures"},
	[279978]={name="Camp Tent",perk="rested"},
	[279941]={name="Tanning Rack",perk="rested",utility="Creates certain reagents"},
	[279945]={name="Sewing Machine",perk="rested",utility="Enables recipes requiring a Sewing Machine"},
	[279950]={name="Reagent Bot",utility="Allows purchasing reagents"},
	[279949]={name="Repair Bot",utility="Allows purchasing reagents and repairing gear"},
	[279989]={name="Anarchist's Workbench",utility="Enables recipes requiring an Anarchist's Workbench"},
	[279981]={name="Basic Campfire Kit",kind="kit",slots=3},
	[279961]={name="Journeyman Campfire Kit",kind="kit",slots=5},
	[279974]={name="Expert Campfire Kit",kind="kit",slots=10},
	[279957]={name="Cookie's Feast",utility="Provides Stamina-boosting food; amount unverified"},
	[279982]={name="Iron Oven",utility="Required for advanced cooking recipes"},
}

local function linesFor(id, level)
	id = safeNumber(id)
	if not id then return nil end
	local item = ITEMS[id]
	if not item then return nil end
	level = safeNumber(level)
	if not level or level % 1 ~= 0 or level < 1 or level > 60 then level = nil end
	local out = {"|cff66ccffDoHelper camping reference — " .. item.name .. "|r"}
	if item.kind == "kit" then
		out[#out+1] = "Cooking; up to " .. item.slots .. " additional camp features."
		out[#out+1] = "Camp kit cooldown: 5 min; features share a 1 hour cooldown."
		out[#out+1] = "Sit or craft near the camp for 1 min to receive other feature benefits."
	elseif item.perk == "lute" then
		if level then
			local lo = level < 10 and 1 or math.floor(level/10)*10
			local arm={ [1]=28,[10]=71,[20]=114,[30]=163,[40]=211,[50]=260,[60]=308 }
			local stats={ [1]=0,[10]=2,[20]=4,[30]=7,[40]=9,[50]=12,[60]=13 }
			if lo == 1 then out[#out+1] = string.format("At your level (%d): +%d Armor; no all-stats bonus.",level,arm[lo])
			else out[#out+1] = string.format("At your level (%d): +%d Armor, +%d all stats.",level,arm[lo] or 308,stats[lo] or 13) end
		else
			out[#out+1] = "Level-60 reference: +308 Armor, +13 all stats. (At level 1–9, all stats bonus is none.)"
		end
		if not level then out[#out+1] = "Level-60 reference: also increases all resistances; amount unverified."
		elseif level >= 30 then out[#out+1] = string.format("At your level (%d): also increases all resistances; amount unverified.",level) end
	elseif item.perk == "critical" then
		out[#out+1] = "+2% critical strike chance with all spells and attacks."
	elseif item.perk == "fishing" then
		out[#out+1] = "+8% stats."
	elseif item.perk == "rested" then
		out[#out+1] = "Increases Rested XP up to 5% of a level; no effect if already above that cap."
	elseif item.perk then
		local value
		if level then for _, b in ipairs(item.perk.brackets) do if level >= b[1] and level <= b[2] then value = b[3]; break end end end
		if value then out[#out+1] = string.format("At your level (%d): +%d %s.",level,value,item.unit or "melee Attack Power")
		else
			local last=item.perk.brackets[#item.perk.brackets]
			out[#out+1] = string.format("Level-60 reference: +%d %s; current-level amount unavailable.",last[3],item.unit or "melee Attack Power")
		end
	end
	if item.exclusive then out[#out+1] = "Exclusive with " .. item.exclusive .. "." end
	if item.utility then out[#out+1] = item.utility .. "." end
	if item.perk then out[#out+1] = "Requires a nearby campfire; sit or craft near camp for 1 min. Features share a 1 hour cooldown." end
	if item.kind ~= "kit" then out[#out+1] = "Baseline reference; talents/Legacy may differ. Does not indicate an active buff." end
	return out
end

local allowedNames = {GameTooltip=true, ItemRefTooltip=true, ShoppingTooltip1=true, ShoppingTooltip2=true, ShoppingTooltip3=true}
local states = setmetatable({}, {__mode="k"})
local hooked = setmetatable({}, {__mode="k"})
local processorRegistered = false
local objectProcessorRegistered = false
local worldHooked = setmetatable({}, {__mode="k"})
local worldCue = setmetatable({}, {__mode="k"})
local worldNames = {}
for id,item in pairs(ITEMS) do
	if item.kind ~= "kit" then worldNames[item.name:lower()] = id end
end
-- Verified Camp Tent summon object (spell 1307230).
local OBJECT_IDS = {[528996]=279978}
local function isAllowed(tip)
	if type(tip) ~= "table" and type(tip) ~= "userdata" then return false end
	if type(ns)=="table" and type(ns.isSecret)=="function" then
		local ok,secret=pcall(ns.isSecret,tip)
		if not ok or secret then return false end
	end
	for name in pairs(allowedNames) do
		local ok,match=pcall(function() return _G[name] == tip end)
		if ok and match then return true end
	end
	return false
end
local function field(obj,key)
		if type(ns)=="table" and type(ns.isSecret)=="function" then
			local secretOk,secret=pcall(ns.isSecret,obj)
			if not secretOk or secret then return nil end
		end
		if obj == nil then return nil end
		local ok,v=pcall(function() return obj[key] end)
		if not ok then return nil end
		if type(ns)=="table" and type(ns.isSecret)=="function" then
			local secretOk,secret=pcall(ns.isSecret,v)
			if not secretOk or secret then return nil end
		end
		return v
end
local function plainName(value)
	if type(ns)=="table" and type(ns.isSecret)=="function" then
		local ok,secret=pcall(ns.isSecret,value); if not ok or secret then return nil end
	end
	if type(value)~="string" then return nil end
	value=value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
	if value=="" then return nil end
	return value
end
local function worldObjectId(data,tip)
	if ns.isSecret(data) then return nil end
	local id=safeNumber(field(data,"id"))
	local mapped=id and OBJECT_IDS[id]
	if mapped then return mapped end
	local lines=field(data,"lines")
	if type(lines)=="table" then
		-- Only the native title is identity, never body text or an owner's name.
		local name=plainName(field(field(lines,1),"leftText"))
		return name and worldNames[name:lower()] or nil
	end
	-- Modern data is authoritative even when its title is inaccessible.
	if data ~= nil then return nil end
	if tip then
		local text=_G.GameTooltipTextLeft1
		local getText=field(text,"GetText")
		if type(getText)=="function" then
			local ok,name=pcall(getText,text)
			if ok then name=plainName(name); if name then return worldNames[name:lower()] end end
		end
	end
	return nil
end
local function readItemId(tip, data)
	-- Modern TooltipData uses id, not itemID. A supplied identity is authoritative.
	-- Never resolve an inaccessible appended item using the primary item's link.
	if ns.isSecret(data) then return nil end
	if data ~= nil then
		return safeNumber(field(data,"id")) or safeNumber(field(data,"itemID")) or safeNumber(field(data,"itemId"))
	end
	local getItem = field(tip,"GetItem")
	if type(getItem) == "function" then
		local ok, _, link=pcall(getItem,tip)
		if ok and not ns.isSecret(link) and type(link)=="string" then
			local raw=link:match("item:(%d+)")
			local parsed=raw and safeNumber(tonumber(raw))
			if parsed then return parsed end
		end
	end
	return nil
end
local function currentLevel()
	if type(UnitLevel)~="function" then return nil end
	local ok,raw=pcall(UnitLevel,"player")
	local n=ok and safeNumber(raw)
	if not n or n%1~=0 or n<1 or n>60 then return nil end
	return n
end
local function decorate(tip,data)
	if not isAllowed(tip) then return end
	-- Postcalls may run while the visible tooltip is still being built, before Show.
	local id=readItemId(tip,data)
	local lines=id and linesFor(id,currentLevel())
	if not lines then states[tip]=nil; return end
	local state=states[tip]
	if state and state.id==id and state.done then return end
	if type(tip.AddLine)~="function" then return end
	local ok=pcall(function() for _,line in ipairs(lines) do tip:AddLine(line,1,1,1,true) end end)
	if ok then states[tip]={id=id,done=true} end
end

local function worldInfo(tip,primary)
	local getInfo=field(tip,primary and "GetPrimaryTooltipInfo" or "GetProcessingTooltipInfo")
	if type(getInfo)~="function" then getInfo=field(tip,"GetPrimaryTooltipInfo") end
	if type(getInfo)~="function" and primary then getInfo=field(tip,"GetProcessingTooltipInfo") end
	if type(getInfo)=="function" then
		local ok,info=pcall(getInfo,tip)
		return ok and info or nil, true
	end
	return nil, false
end
local function worldDataIsCurrent(tip)
	local info,modern=worldInfo(tip)
	if modern then return field(info,"getterName")=="GetWorldCursor" end
	-- Legacy setters can also display units. Never use their title as an object.
	for _,method in ipairs({"GetItem","GetSpell","GetUnit"}) do
		local fn=field(tip,method)
		if type(fn)=="function" then
			local ok,name,identity=pcall(fn,tip)
			if not ok or ns.isSecret(name) or ns.isSecret(identity) or name~=nil or identity~=nil then return false end
		end
	end
	-- Older clients may expose only the setter and rendered text. The setter
	-- itself is the world-origin signal; if an owner is available, constrain it.
	if not worldCue[tip] then return false end
	local getOwner=field(tip,"GetOwner")
	if type(getOwner)=="function" then
		local ok,owner=pcall(getOwner,tip)
		if not ok or ns.isSecret(owner) or (owner and owner~=_G.UIParent and owner~=_G.WorldFrame) then return false end
	end
	return true
end
local function decorateWorld(tip,data,typedObject,refresh)
	if not isAllowed(tip) or _G.GameTooltip~=tip or not worldDataIsCurrent(tip) then return end
	if ns.isSecret(data) then return end
	if typedObject and data == nil then return end
	if data ~= nil and not typedObject then
		local objectType=Enum and Enum.TooltipDataType and safeNumber(Enum.TooltipDataType.Object)
		if not objectType or safeNumber(field(data,"type"))~=objectType then return end
	end
	local id=worldObjectId(data,tip)
	local lines=id and linesFor(id,currentLevel())
	if not lines then states[tip]=nil; return end
	local state=states[tip]
	if state and state.world and state.id==id and state.done then return end
	local add=field(tip,"AddLine")
	if type(add)~="function" then return end
	local ok=pcall(function() for _,line in ipairs(lines) do add(tip,line,1,1,1,true) end end)
	if ok then
		states[tip]={id=id,world=true,done=true}
		-- Legacy SetWorldCursor has already called Show before our posthook.
		-- Reflow only an existing visible tooltip, with state set before recursion.
		if refresh then
			local isShown=field(tip,"IsShown")
			local shownOk,shown=false,false
			if type(isShown)=="function" then shownOk,shown=pcall(isShown,tip) end
			local show=field(tip,"Show")
			if shownOk and not ns.isSecret(shown) and shown==true and type(show)=="function" then pcall(show,tip) end
		end
	end
end
local function hookWorld(tip)
	if not isAllowed(tip) or _G.GameTooltip~=tip or worldHooked[tip] then return end
	worldHooked[tip]=true
	if type(tip.HookScript)=="function" then
		pcall(tip.HookScript,tip,"OnShow",function(self)
			if self~=_G.GameTooltip then return end
			local info,modern=worldInfo(self,true)
			if modern then
				if field(info,"getterName")=="GetWorldCursor" then
					local data=field(info,"tooltipData")
					if data then pcall(decorateWorld,self,data) end
				end
			else pcall(decorateWorld,self) end
		end)
		pcall(tip.HookScript,tip,"OnHide",function(self) states[self]=nil; worldCue[self]=nil end)
	end
	if type(hooksecurefunc)=="function" and type(tip.SetWorldCursor)=="function" then
		pcall(hooksecurefunc,tip,"SetWorldCursor",function(self)
			if self~=_G.GameTooltip then return end
			worldCue[self]=true
			local api=C_TooltipInfo
			local getter=api and field(api,"GetWorldCursor")
			if type(getter)=="function" then
				local ok,data=pcall(getter)
				if ok and not ns.isSecret(data) and data then pcall(decorateWorld,self,data,false,true) else states[self]=nil; worldCue[self]=nil end
			else
				local _,modern=worldInfo(self)
				if not modern then pcall(decorateWorld,self,nil,false,true) end
			end
		end)
	end
end

local function hookTip(tip)
	if not isAllowed(tip) or hooked[tip] then return end
	if type(tip.HookScript)=="function" then
		-- Modern clients removed OnTooltipSetItem; clearing is still needed even
		-- when that legacy hook is refused, for same-item rebuilds.
		pcall(tip.HookScript,tip,"OnTooltipSetItem",function(self) pcall(decorate,self) end)
		local ok=pcall(tip.HookScript,tip,"OnTooltipCleared",function(self) states[self]=nil; worldCue[self]=nil end)
		if ok then hooked[tip]=true end
	end
end
local function install()
	for name in pairs(allowedNames) do hookTip(_G[name]) end
	hookWorld(_G.GameTooltip)
	local processor=TooltipDataProcessor
	if not processorRegistered and type(processor)=="table" and type(processor.AddTooltipPostCall)=="function" then
		local itemType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
		if safeNumber(itemType) then
			local ok,result=pcall(processor.AddTooltipPostCall,itemType,function(tip,data) pcall(decorate,tip,data) end)
			if ok and result ~= false then processorRegistered=true end
		end
	end
	if not objectProcessorRegistered and type(processor)=="table" and type(processor.AddTooltipPostCall)=="function" then
		local objectType=Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
		if safeNumber(objectType) then
			local ok,result=pcall(processor.AddTooltipPostCall,objectType,function(tip,data) pcall(decorateWorld,tip,data,true) end)
			if ok and result~=false then objectProcessorRegistered=true end
		end
	end
end
install()
if type(CreateFrame)=="function" then
	local ok,frame=pcall(CreateFrame,"Frame")
	if ok and frame and type(frame.RegisterEvent)=="function" and type(frame.SetScript)=="function" then
		pcall(frame.RegisterEvent,frame,"PLAYER_LOGIN")
		pcall(frame.RegisterEvent,frame,"ADDON_LOADED")
		pcall(frame.SetScript,frame,"OnEvent",install)
	end
end

ns.Camping = { ITEMS = ITEMS, OBJECT_IDS=OBJECT_IDS, LinesFor = linesFor, Decorate = decorate, Install = install }
