-- WowSim: reads Blizzard's generated API documentation (from the Forever UI
-- source mirror) to build Enum/Constants, the event list, and harmless stubs
-- for every documented function we do not implement ourselves.

local SIM = __SIM
local type, pairs, ipairs = type, pairs, ipairs

SIM.docs = { systems = {} }
SIM.knownEvents = {}
SIM.structs = {}
SIM.enums = {}

APIDocumentation = {
	AddDocumentationTable = function(self, t) table.insert(SIM.docs.systems, t) end,
}

function SIM.loadDocChunk(code, name)
	local fn, err = loadstring(code, "=" .. name)
	if not fn then return false end
	local ok = pcall(fn)
	return ok
end

local function defaultFor(typ, nilable, depth, innerType)
	if nilable then return nil end
	depth = depth or 0
	if typ == "bool" then return false end
	if typ == "number" or typ == "luaIndex" or typ == "time_t" or typ == "fileID" or typ == "BigUInteger" or typ == "BigInteger"
		or typ == "size" or typ == "uiMapID" or typ == "SpellIdentifier" then
		if typ == "luaIndex" then return 1 end
		return 0
	end
	if typ == "string" or typ == "cstring" or typ == "WOWGUID" or typ == "UnitToken" or typ == "textureAtlas" or typ == "kstringClubInfo" then return "" end
	if typ == "table" then return {} end
	if SIM.enums[typ] then return 0 end
	local st = SIM.structs[typ]
	if st and depth < 3 then
		local t = {}
		for _, f in ipairs(st) do t[f.Name] = defaultFor(f.Type, f.Nilable, depth + 1, f.InnerType) end
		return t
	end
	return nil
end

local function makeStub(label, returns)
	return function(...)
		SIM.noteStub(label)
		if not returns or #returns == 0 then return end
		local out = {}
		for i, r in ipairs(returns) do out[i] = defaultFor(r.Type, r.Nilable, 0, r.InnerType) end
		return unpack(out, 1, #returns)
	end
end

function SIM.installDocs()
	Enum = Enum or {}
	Constants = Constants or {}
	local nFuncs, nStubs, nEvents = 0, 0, 0
	-- Pass 1: tables (enums, structures, constants)
	for _, sys in ipairs(SIM.docs.systems) do
		for _, t in ipairs(sys.Tables or {}) do
			if t.Type == "Enumeration" then
				local e = {}
				for _, f in ipairs(t.Fields or {}) do e[f.Name] = f.EnumValue end
				SIM.enums[t.Name] = true
				if Enum[t.Name] == nil then Enum[t.Name] = e end
				if t.Name:sub(-4) == "Meta" then Enum[t.Name] = Enum[t.Name] or e end
			elseif t.Type == "Structure" then
				SIM.structs[t.Name] = t.Fields or {}
			elseif t.Type == "Constants" then
				local c = {}
				for _, f in ipairs(t.Values or {}) do c[f.Name] = f.Value end
				if Constants[t.Name] == nil then Constants[t.Name] = c end
			end
		end
	end
	-- Pass 2: functions, methods, events
	for _, sys in ipairs(SIM.docs.systems) do
		local ns = sys.Namespace
		if sys.Type == "ScriptObject" then
			for _, f in ipairs(sys.Functions or {}) do SIM.docMethods[f.Name] = true end
		else
			local target
			if ns then
				target = _G[ns]
				if target == nil then target = {} _G[ns] = target end
			else
				target = _G
			end
			if type(target) == "table" then
				for _, f in ipairs(sys.Functions or {}) do
					nFuncs = nFuncs + 1
					if rawget(target, f.Name) == nil then
						target[f.Name] = makeStub((ns and (ns .. ".") or "") .. f.Name, f.Returns)
						nStubs = nStubs + 1
					end
				end
			end
		end
		for _, e in ipairs(sys.Events or {}) do
			local payload = {}
			for i, p in ipairs(e.Payload or {}) do payload[i] = { name = p.Name, type = p.Type, nilable = p.Nilable or false } end
			SIM.knownEvents[e.LiteralName] = { system = sys.Name, payload = payload }
			nEvents = nEvents + 1
		end
	end
	-- Events the docs do not list but the client fires.
	for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED",
		"SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "CHAT_MSG_ADDON",
		"COMBAT_LOG_EVENT_UNFILTERED", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
		"UPDATE_MOUSEOVER_UNIT", "PLAYER_FLAGS_CHANGED", "PLAYER_UPDATE_RESTING", "UNIT_AURA", "BAG_UPDATE",
		"SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START",
		"UNIT_SPELLCAST_STOP", "PLAYER_MOUNT_DISPLAY_CHANGED", "CHAT_MSG_SAY", "CHAT_MSG_PARTY", "CHAT_MSG_WHISPER",
		"QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "UPDATE_BINDINGS", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED",
		"PLAYER_XP_UPDATE", "UNIT_MAXHEALTH", "UNIT_DISPLAYPOWER", "LOADING_SCREEN_DISABLED", "PLAYER_TALENT_UPDATE",
		"CHARACTER_POINTS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" }) do
		if not SIM.knownEvents[ev] then SIM.knownEvents[ev] = { system = "WowSim", payload = {} } end
	end
	return nFuncs, nStubs, nEvents
end

function SIM.eventCatalog()
	local out = {}
	for name, e in pairs(SIM.knownEvents) do
		local p = {}
		for i, x in ipairs(e.payload) do p[i] = x.name .. ":" .. tostring(x.type) end
		out[#out + 1] = { n = name, s = e.system, p = p }
	end
	table.sort(out, function(a, b) return a.n < b.n end)
	return out
end
