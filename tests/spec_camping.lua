-- Focused, local-mock coverage for exact-ID camping tooltip annotations.
local function contains(s, part) return type(s)=="string" and s:find(part,1,true)~=nil end
local function withCamping(fn, configure)
	local names={"Enum","TooltipDataProcessor","GameTooltip","ItemRefTooltip","ShoppingTooltip1","ShoppingTooltip2","ShoppingTooltip3","UnitLevel","CreateFrame","C_TooltipInfo","GameTooltipTextLeft1","hooksecurefunc","UIParent","WorldFrame"}
	local old={}
	for _,k in ipairs(names) do old[k]=_G[k] end
	local level=14
	_G.UnitLevel=function(unit) assert_eq(unit,"player"); return level end
	_G.CreateFrame=nil
	_G.GameTooltip=nil; _G.ItemRefTooltip=nil; _G.ShoppingTooltip1=nil; _G.ShoppingTooltip2=nil; _G.ShoppingTooltip3=nil
	_G.TooltipDataProcessor=nil
	_G.Enum={TooltipDataType={Item=0,Object=4}}
	if configure then configure() end
	local ns={isSecret=function(v) return type(v)=="table" and v.secret==true end,toNumber=function(v) if type(v)=="table" and v.secret then return nil end; return type(v)=="number" and v or nil end}
	assert(load(ReadFile(__HOT_ROOT.."/DoHelper/Camping.lua"),"@Camping.lua"))("DoHelper",ns)
	local mod=ns.Camping
	local ok,err=pcall(fn,mod,function(v) level=v end)
	for _,k in ipairs(names) do _G[k]=old[k] end
	if not ok then error(err,0) end
end

T.register("camping catalog covers all known IDs and never matches unknown IDs",function()
	withCamping(function(m)
		local ids={279960,279948,279952,279956,279970,279990,279944,279988,279955,279962,279964,279947,279972,279943,279959,279968,279940,279951,279976,279985,279987,279979,279969,279938,279967,279965,279966,279978,279941,279945,279950,279949,279989,279981,279961,279974,279957,279982}
		for _,id in ipairs(ids) do assert_not_nil(m.ITEMS[id],"item "..id); assert_not_nil(m.LinesFor(id,60)) end
		assert_nil(m.LinesFor(123456,60)); assert_nil(m.LinesFor("Lodestone",60))
		assert_eq(m.ITEMS[279972].spell,1307240); assert_true(contains(table.concat(m.LinesFor(279972,60)," "),"Horde-only"))
	end)
end)

T.register("camping level bracket edges and fallback references are explicit",function()
	withCamping(function(m)
		local function amount(id,lvl)
			local s=table.concat(m.LinesFor(id,lvl)," ")
			return s:match("At your level %(%d+%): %+(%d+)")
		end
		local brackets={
			{279960,{{1,12},{11,12},{12,20},{21,20},{22,32},{31,32},{32,49},{41,49},{42,67},{51,67},{52,90},{60,90}}},
			{279956,{{1,10},{23,10},{24,15},{33,15},{34,20},{43,20},{44,24},{53,24},{54,29},{60,29}}},
			{279944,{{1,6},{23,6},{24,11},{37,11},{38,20},{51,20},{52,34},{60,34}}},
			{279962,{{1,2},{13,2},{14,6},{27,6},{28,12},{41,12},{42,18},{55,18},{56,25},{60,25}}},
			{279972,{{1,14},{39,14},{40,19},{49,19},{50,27},{59,27},{60,32}}},
			{279968,{{1,3},{11,3},{12,8},{23,8},{24,21},{35,21},{36,34},{47,34},{48,45},{59,45},{60,56}}},
		}
		for _,set in ipairs(brackets) do for _,v in ipairs(set[2]) do assert_eq(tonumber(amount(set[1],v[1])),v[2],set[1].." level "..v[1]) end end
		assert_eq(tonumber(amount(279960,14)),20); assert_eq(tonumber(amount(279960,60)),90)
		local fallback=table.concat(m.LinesFor(279960,nil)," "); assert_true(contains(fallback,"Level-60 reference")); assert_false(contains(fallback,"At your level"))
		assert_true(contains(table.concat(m.LinesFor(279976,5)," "),"no all-stats bonus"))
		assert_false(contains(table.concat(m.LinesFor(279976,20)," "),"resistances; amount"))
		assert_true(contains(table.concat(m.LinesFor(279976,30)," "),"resistances; amount unverified"))
	end)
end)

T.register("camping fixed perks, utility inheritance, and rested cap are described",function()
	withCamping(function(m)
		assert_true(contains(table.concat(m.LinesFor(279979,20)," "),"+2% critical"))
		assert_true(contains(table.concat(m.LinesFor(279965,20)," "),"+8% stats"))
		local rested=table.concat(m.LinesFor(279978,20)," "); assert_true(contains(rested,"up to 5% of a level")); assert_true(contains(rested,"above that cap")); assert_false(contains(rested,"5% XP gain"))
		assert_true(contains(table.concat(m.LinesFor(279948,14)," "),"+20 melee Attack Power")); assert_true(contains(table.concat(m.LinesFor(279948,14)," "),"common mining node"))
		assert_true(contains(table.concat(m.LinesFor(279990,14)," "),"+10 Mana/5 sec")); assert_true(contains(table.concat(m.LinesFor(279990,14)," "),"recipes requiring"))
		assert_true(contains(table.concat(m.LinesFor(279961,60)," "),"up to 5 additional"))
	end)
end)

T.register("camping modern and legacy hooks are safe, deduplicated, and recyclable",function()
	local post,legacy,cleared
	local tip={lines={},shown=false}
	function tip:HookScript(name,cb) if name=="OnTooltipSetItem" then legacy=cb elseif name=="OnTooltipCleared" then cleared=cb end end
	function tip:GetItem() return "Lodestone","|Hitem:279960:0|h[Lodestone]|h" end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	function tip:Show() self.shown=true end
	withCamping(function(m,setLevel)
		assert_not_nil(post); assert_not_nil(legacy)
		post(tip,{id=279960}); local n=#tip.lines; assert_true(n>0); post(tip,{id=279960}); legacy(tip); assert_eq(#tip.lines,n); assert_false(tip.shown)
		assert_true(contains(table.concat(tip.lines," "),"At your level (14): +20"))
		cleared(tip); setLevel(22); post(tip,{itemID=279960}); assert_true(contains(table.concat(tip.lines," "),"At your level (22): +32"))
		cleared(tip); tip.GetItem=function() return "unknown","|Hitem:111:0|h[whatever]|h" end; legacy(tip); assert_eq(#tip.lines,n*2)
		local unrelated={}; function unrelated:AddLine() error("must not mutate unrelated tooltip") end; post(unrelated,{itemID=279960})
		cleared(tip); tip.AddLine=function() error("tooltip method error") end; pcall(legacy,tip)
	end,function()
		_G.TooltipDataProcessor={AddTooltipPostCall=function(kind,cb) assert_eq(kind,0); post=cb end}
		_G.GameTooltip=tip
	end)
end)

T.register("camping modern enum identity, pre-show population and same-item rebuild",function()
	local post,clear
	local tip={lines={}}
	function tip:IsShown() return false end
	function tip:HookScript(name,cb)
		if name=="OnTooltipSetItem" then error("removed modern script") end
		if name=="OnTooltipCleared" then clear=cb end
	end
	function tip:GetItem() return "stale", "|Hitem:279960|h[stale]|h" end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	withCamping(function(m,setLevel)
		assert_not_nil(post); assert_not_nil(clear)
		post(tip,{id=111}); assert_eq(#tip.lines,0,"unknown modern identity must not use stale link")
		post(tip,{id=279960}); local n=#tip.lines; assert_true(n>0)
		post(tip,{id=279960}); assert_eq(#tip.lines,n)
		clear(tip); tip.lines={}; setLevel(52); post(tip,{id=279960})
		assert_eq(#tip.lines,n); assert_true(contains(table.concat(tip.lines," "),"(52): +90"))
		clear(tip); tip.lines={}
		-- GetItem still exposes a readable primary Lodestone; restricted appended
		-- data must not inherit that identity.
		post(tip,{secret=true}); assert_eq(#tip.lines,0)
		post(tip,{id={secret=true}}); assert_eq(#tip.lines,0)
		post(tip,{}); assert_eq(#tip.lines,0)
		assert_nil(m.LinesFor({secret=true},14))
		clear(tip); setLevel({secret=true}); post(tip,{id=279960})
		assert_true(contains(table.concat(tip.lines," "),"Level-60 reference"))
	end,function()
		_G.GameTooltip=tip
		_G.TooltipDataProcessor={AddTooltipPostCall=function(kind,cb) assert_eq(kind,0); post=cb end}
	end)
end)

T.register("camping legacy-only tooltip decorates and rebuilds without modern APIs",function()
	local legacy,clear
	local tip={lines={}}
	function tip:HookScript(name,cb)
		if name=="OnTooltipSetItem" then legacy=cb end
		if name=="OnTooltipCleared" then clear=cb end
	end
	function tip:GetItem() return "Lodestone","|Hitem:279960:0|h[Lodestone]|h" end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	withCamping(function(m,setLevel)
		assert_not_nil(legacy); assert_not_nil(clear)
		legacy(tip); local n=#tip.lines; assert_true(n>0)
		assert_true(contains(table.concat(tip.lines," "),"(14): +20"))
		legacy(tip); assert_eq(#tip.lines,n)
		clear(tip); tip.lines={}; setLevel(22); legacy(tip)
		assert_eq(#tip.lines,n); assert_true(contains(table.concat(tip.lines," "),"(22): +32"))
		clear(tip); tip.lines={}; tip.GetItem=function() return "secret",{secret=true} end
		legacy(tip); assert_eq(#tip.lines,0)
	end,function() _G.GameTooltip=tip end)
end)

T.register("camping lute brackets and invalid level references",function()
	withCamping(function(m)
		local cases={{1,28,0},{9,28,0},{10,71,2},{19,71,2},{20,114,4},{29,114,4},{30,163,7},{39,163,7},{40,211,9},{49,211,9},{50,260,12},{59,260,12},{60,308,13}}
		for _,v in ipairs(cases) do
			local s=table.concat(m.LinesFor(279976,v[1])," ")
			assert_true(contains(s,"+"..v[2].." Armor"))
			if v[3]>0 then assert_true(contains(s,"+"..v[3].." all stats")) else assert_true(contains(s,"no all-stats bonus")) end
		end
		for _,lvl in ipairs({0,-1,61,14.5,math.huge,"14",{secret=true}}) do
			local s=table.concat(m.LinesFor(279960,lvl)," ")
			assert_true(contains(s,"Level-60 reference")); assert_false(contains(s,"At your level"))
		end
	end)
end)

T.register("camping hook registration failures and secret data fail safely",function()
	local legacy
	local tip={}
	function tip:HookScript(name,cb) if name=="OnTooltipSetItem" then legacy=cb end end
	function tip:GetItem() return "x","|Hitem:279960:0|h[x]|h" end
	function tip:AddLine() error("secret item must not be annotated") end
	withCamping(function(m)
		assert_not_nil(legacy)
		pcall(legacy,tip)
		local normal=table.concat(m.LinesFor(279960,{secret=true})," "); assert_true(contains(normal,"Level-60 reference")); assert_false(contains(normal,"At your level"))
	end,function()
		_G.TooltipDataProcessor={AddTooltipPostCall=function() error("no modern hook") end}
		_G.GameTooltip=tip
	end)
end)

T.register("camping world objects use current Object tooltip identity and exact native name",function()
	local posts={}; local cleared,shown,hidden
	local tip={lines={},info={getterName="GetWorldCursor"}}
	function tip:HookScript(name,cb) if name=="OnTooltipCleared" then cleared=cb elseif name=="OnShow" then shown=cb elseif name=="OnHide" then hidden=cb end end
	function tip:GetProcessingTooltipInfo() return self.info end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	withCamping(function(m,setLevel)
		assert_not_nil(posts[4]); assert_eq(m.OBJECT_IDS[528996],279978)
		local function fire(data) posts[4](tip,data) end
		fire({id=528996,lines={}})
		local n=#tip.lines; assert_eq(n,2,"placed-object tooltip should contain only two rows")
		assert_true(contains(table.concat(tip.lines," "),"Rested XP up to 5%"))
		assert_true(contains(tip.lines[2],"Exclusive with: none listed"))
		fire({id=528996,lines={}}); assert_eq(#tip.lines,n,"modern postcall duplicate")
		cleared(tip); tip.lines={}; setLevel(14)
		fire({id=0,lines={{leftText="|cffffcc00Lodestone|r"}}})
		assert_eq(#tip.lines,2)
		assert_true(contains(tip.lines[1],"At level 14: +20 melee Attack Power"),"name fallback must not interpret Object id as itemID")
		assert_true(contains(tip.lines[2],"Exclusive with: Blessing of Might"))
		for id,item in pairs(m.ITEMS) do
			if item.kind~="kit" then
				cleared(tip); tip.lines={}; fire({id=0,lines={{leftText=item.name}}})
				assert_eq(#tip.lines,2,"exact world-name fallback has exactly two rows for "..item.name.." ("..id..")")
			end
		end
		cleared(tip); tip.lines={}; fire({id=123456,lines={{leftText="Lodestone"}}}); assert_true(#tip.lines>0,"foreign placer/no inventory does not gate world object")
		cleared(tip); tip.lines={}; fire({id=999,lines={{leftText="Camp Tent Item"}}}); assert_eq(#tip.lines,0,"non-exact names stay untouched")
		tip.info={getterName="GetItem"}; fire({id=528996,lines={{leftText="Camp Tent"}}}); assert_eq(#tip.lines,0,"item link never enters world-object path")
		cleared(tip); tip.lines={}; tip.info={getterName="GetUnit"}; fire({id=528996,lines={}}); assert_eq(#tip.lines,0,"unit/player/pet tooltips excluded")
		tip.info={getterName="GetWorldCursor"}; cleared(tip); tip.lines={}; fire({id=999,lines={{leftText={secret=true}}}}); assert_eq(#tip.lines,0,"secret name excluded")
		assert_not_nil(shown); assert_not_nil(hidden)
	end,function()
		_G.GameTooltip=tip
		_G.TooltipDataProcessor={AddTooltipPostCall=function(kind,cb) posts[kind]=cb end}
	end)
end)

T.register("camping legacy world setter path is scoped, deduplicated, and clears on reuse",function()
	local posts={}; local hooks={}; local clear
	local tip={lines={},info={getterName="GetWorldCursor"}}
	function tip:HookScript(name,cb) if name=="OnTooltipCleared" then clear=cb else hooks[name]=cb end end
	function tip:GetProcessingTooltipInfo() return self.info end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	function tip:SetWorldCursor() end
	local hookFunc=function(obj,method,cb) assert_eq(obj,tip); assert_eq(method,"SetWorldCursor"); hooks.setter=cb end
	withCamping(function()
		assert_not_nil(hooks.setter)
		-- The real setter is the world-origin cue; plain callback or arbitrary UI tooltip is not.
		_G.C_TooltipInfo={GetWorldCursor=function() return {type=4,id=528996,lines={}} end}
		hooks.setter(tip); local n=#tip.lines; assert_true(n>0,"legacy world setter adds reference")
		hooks.setter(tip); assert_eq(#tip.lines,n,"setter and later OnShow/postcall do not duplicate")
		clear(tip); tip.lines={}; tip.info={getterName="GetItem"}; hooks.setter(tip); assert_eq(#tip.lines,0)
		_G.C_TooltipInfo.GetWorldCursor=function() return nil end; tip.info={getterName="GetWorldCursor"}; hooks.setter(tip); assert_eq(#tip.lines,0,"nil cursor must not reuse stale identity")
		tip.GetProcessingTooltipInfo=nil; tip.GetPrimaryTooltipInfo=nil; tip.GetOwner=function() return _G.UIParent end
		_G.C_TooltipInfo=nil; _G.GameTooltipTextLeft1={GetText=function() return "Lodestone" end}
		tip.lines={}; hooks.setter(tip); assert_true(#tip.lines>0,"legacy setter plus world owner/native title decorates")
	end,function()
		_G.GameTooltip=tip; _G.hooksecurefunc=hookFunc; _G.UIParent={}
		_G.TooltipDataProcessor={AddTooltipPostCall=function(kind,cb) posts[kind]=cb end}
	end)
end)

T.register("camping modern world fallback never uses secret titles, body text or unit names",function()
	local post,hooks={},{ }
	local tip={lines={},info={getterName="GetWorldCursor"}}
	function tip:HookScript(name,cb) hooks[name]=cb end
	function tip:GetProcessingTooltipInfo() return self.info end
	function tip:GetPrimaryTooltipInfo() return self.info end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	withCamping(function()
		_G.GameTooltipTextLeft1={GetText=function() return "Camp Tent" end}
		local function check(data,expected)
			hooks.OnTooltipCleared(tip); tip.lines={}; tip.info.tooltipData=data
			post[4](tip,data); hooks.OnShow(tip)
			if expected then assert_true(#tip.lines>0) else assert_eq(#tip.lines,0) end
		end
		check({secret=true},false)
		check({type=4,lines={{leftText={secret=true}},{leftText="Camp Tent"}}},false)
		check({type=4,lines={{leftText="Unrelated Object"},{leftText="Camp Tent"}}},false)
		check({type=4,id=279978},false) -- itemID must never be a world ID
		check({type=4,lines={{leftText="Camp Tent"}}},true)
		local n=#tip.lines; hooks.OnShow(tip); assert_eq(#tip.lines,n)
		hooks.OnHide(tip); tip.lines={}; hooks.OnShow(tip); assert_true(#tip.lines>0)
		-- A world unit can have an identical name; Object postcall is NOT invoked.
		hooks.OnTooltipCleared(tip); tip.lines={}
		tip.info.tooltipData={type=2,id=528996,lines={{leftText="Camp Tent"}}}
		hooks.OnShow(tip); assert_eq(#tip.lines,0)
		tip.info={getterName="GetItemByID",tooltipData={type=0,id=279978}}
		hooks.OnShow(tip); assert_eq(#tip.lines,0)
	end,function()
		_G.GameTooltip=tip
		_G.TooltipDataProcessor={AddTooltipPostCall=function(kind,cb) post[kind]=cb end}
	end)
end)

T.register("camping text-only legacy world setter reflows after Show and excludes units",function()
	local hooks={}
	local tip={lines={},shown=false,shows=0,title="Camp Tent"}
	function tip:HookScript(name,cb) hooks[name]=cb end
	function tip:GetOwner() return _G.WorldFrame end
	function tip:GetUnit() return self.unitName,self.unit end
	function tip:GetItem() return self.itemName,self.itemLink end
	function tip:GetSpell() return nil end
	function tip:AddLine(s) self.lines[#self.lines+1]=s end
	function tip:IsShown() return self.shown end
	function tip:Show() self.shown=true; self.shows=self.shows+1; if hooks.OnShow then hooks.OnShow(self) end end
	function tip:SetWorldCursor()
		self.lines={}; hooks.OnTooltipCleared(self)
		if self.title then self:Show() else self.shown=false; hooks.OnHide(self) end
	end
	withCamping(function(_,setLevel)
		tip:SetWorldCursor(); assert_eq(#tip.lines,2); assert_eq(tip.shows,2,"posthook reflows already-shown native tooltip")
		assert_true(contains(table.concat(tip.lines," "),"Rested XP up to 5%"))
		tip.title="Lodestone"; setLevel(22); tip:SetWorldCursor()
		assert_true(contains(tip.lines[1],"At level 22: +32 melee Attack Power")); assert_true(contains(tip.lines[2],"Exclusive with: Blessing of Might")); assert_eq(tip.shows,4)
		tip.title="Camp Tent"; tip.unitName="Camp Tent"; tip.unit="mouseover"; tip:SetWorldCursor(); assert_eq(#tip.lines,0)
		tip.unitName=nil; tip.unit=nil; tip.itemName="Camp Tent"; tip.itemLink="item:279978"; tip:SetWorldCursor(); assert_eq(#tip.lines,0)
		tip.itemName=nil; tip.itemLink=nil; tip.title={secret=true}; tip:SetWorldCursor(); assert_eq(#tip.lines,0)
		tip.title=nil; tip:SetWorldCursor(); assert_eq(#tip.lines,0); assert_false(tip.shown)
	end,function()
		_G.GameTooltip=tip; _G.WorldFrame={}; _G.C_TooltipInfo=nil
		_G.GameTooltipTextLeft1={GetText=function() return tip.title end}
		_G.hooksecurefunc=function(obj,method,cb)
			local original=obj[method]
			obj[method]=function(self,...) original(self,...); cb(self,...) end
		end
	end)
end)

T.register("camping compact object reference contains only benefit and exclusive rows",function()
	withCamping(function(m)
		local function rows(id,level)
			local result=m.CompactLinesFor(id,level)
			assert_eq(#result,2,"expected exactly two object tooltip rows")
			return result
		end
		local tent=rows(279978,14)
		assert_eq(tent[1],"Rested XP up to 5% of a level")
		assert_eq(tent[2],"Exclusive with: none listed")
		local lodestone=rows(279960,14)
		assert_eq(lodestone[1],"At level 14: +20 melee Attack Power")
		assert_eq(lodestone[2],"Exclusive with: Blessing of Might")
		assert_eq(rows(279960,60)[1],"At level 60: +90 melee Attack Power")
		assert_eq(rows(279956,14)[1],"At level 14: +10 Mana/5 sec")
		assert_eq(rows(279979,14)[1],"+2% critical strike chance (spells and attacks)")
		assert_true(contains(rows(279976,14)[1],"+71 Armor, +2 all stats"))
		assert_eq(rows(279950,14)[1],"Allows purchasing reagents")
	end)
end)
