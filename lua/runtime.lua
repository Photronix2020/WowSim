-- WowSim: addon loading, login sequence, profile changes, and the state the
-- browser polls.

local SIM = __SIM
local S = SIM.S
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

SIM.addonNS = {}

-- Load a Blizzard FrameXML Lua file from the API mirror, keeping only the
-- globals WowSim does not define itself.
function SIM.fillFromBlizzard(code, name)
	local fn, err = loadstring(code, "@Blizzard/" .. name)
	if not fn then return false, tostring(err) end
	local env = setmetatable({}, { __index = _G })
	setfenv(fn, env)
	local ok, e = pcall(fn)
	local added = 0
	for k, v in pairs(env) do
		if rawget(_G, k) == nil then _G[k] = v added = added + 1 end
	end
	if not ok then return false, tostring(e), added end
	return true, nil, added
end

function SIM.registerAddon(name, meta, index)
	SIM.addons[name] = { meta = meta or {}, loaded = false }
	SIM.addonOrder[index] = name
	SIM.addonNS[name] = {}
end

-- Run one addon file the way the client does: (addonName, namespace) varargs.
function SIM.runFile(code, chunkName, addonName)
	local fn, err = loadstring(code, "@" .. chunkName)
	if not fn then
		SIM.reportError({ msg = tostring(err), stack = "while loading " .. chunkName })
		return false
	end
	local ok = SIM.pcall(fn, addonName, SIM.addonNS[addonName])
	return ok
end

function SIM.runSaved(code, name)
	local fn, err = loadstring(code, "=SavedVariables:" .. name)
	if not fn then
		SIM.reportError({ msg = "SavedVariables for " .. name .. " failed to parse: " .. tostring(err), stack = "" })
		return false
	end
	return SIM.pcall(fn)
end

function SIM.saveVariables(names)
	local out = {}
	for _, n in ipairs(names) do
		local v = rawget(_G, n)
		if v ~= nil then out[#out + 1] = SIM.serialize(n, v) end
	end
	return table.concat(out, "\n")
end

function SIM.addonLoaded(name)
	if SIM.addons[name] then SIM.addons[name].loaded = true end
	SIM.fireEvent("ADDON_LOADED", name)
end

function SIM.login()
	SIM.fireEvent("SPELLS_CHANGED")
	SIM.fireEvent("VARIABLES_LOADED")
	SIM.loggedIn = true
	SIM.fireEvent("PLAYER_LOGIN")
	SIM.fireEvent("PLAYER_ENTERING_WORLD", true, false)
	SIM.fireEvent("ZONE_CHANGED_NEW_AREA")
	SIM.fireEvent("LOADING_SCREEN_DISABLED")
	SIM.fireEvent("GROUP_ROSTER_UPDATE")
	SIM.fireEvent("UPDATE_BINDINGS")
	SIM.loadingDone = true
end

function SIM.logout()
	SIM.fireEvent("PLAYER_LOGOUT")
end

------------------------------------------------------------------------
-- Profile changes from the control panel fire the matching game events.
------------------------------------------------------------------------
local P = SIM.profile
function SIM.setProfile(key, value, sub)
	local old
	if sub then
		P[key] = P[key] or {}
		old = P[key][sub]
		P[key][sub] = value
	else
		old = P[key]
		P[key] = value
	end
	if old == value then return end
	local fire = SIM.fireEvent
	if key == "inCombat" then
		if value then fire("PLAYER_REGEN_DISABLED") else fire("PLAYER_REGEN_ENABLED") end
		fire("UNIT_FLAGS", "player")
	elseif key == "target" then
		fire("PLAYER_TARGET_CHANGED")
		if sub == "health" then fire("UNIT_HEALTH", "target") end
		if sub == "dead" and value then fire("UNIT_HEALTH", "target") end
	elseif key == "health" or key == "healthMax" then
		fire("UNIT_HEALTH", "player")
		if key == "healthMax" then fire("UNIT_MAXHEALTH", "player") end
	elseif key == "power" or key == "powerMax" then
		local _, ptoken = UnitPowerType("player")
		fire("UNIT_POWER_UPDATE", "player", ptoken)
		fire("UNIT_POWER_FREQUENT", "player", ptoken)
		if key == "powerMax" then fire("UNIT_MAXPOWER", "player", ptoken) end
	elseif key == "group" or key == "raid" or key == "party" then
		fire("GROUP_ROSTER_UPDATE")
	elseif key == "level" then
		fire("PLAYER_LEVEL_UP", value, 0, 0, 0, 0, 0, 0, 0, 0)
		fire("UNIT_LEVEL", "player")
	elseif key == "money" then
		fire("PLAYER_MONEY")
	elseif key == "zone" or key == "subZone" then
		fire("ZONE_CHANGED")
		fire("ZONE_CHANGED_NEW_AREA")
	elseif key == "dead" then
		if value then fire("PLAYER_DEAD") else fire("PLAYER_ALIVE") fire("PLAYER_UNGHOST") end
		fire("UNIT_HEALTH", "player")
	elseif key == "mounted" then
		fire("PLAYER_MOUNT_DISPLAY_CHANGED")
	elseif key == "resting" then
		fire("PLAYER_UPDATE_RESTING")
	elseif key == "afk" then
		fire("PLAYER_FLAGS_CHANGED", "player")
	elseif key == "class" then
		fire("SPELLS_CHANGED")
		fire("PLAYER_TALENT_UPDATE")
	elseif key == "spells" then
		fire("SPELLS_CHANGED")
	elseif key == "xp" or key == "xpMax" then
		fire("PLAYER_XP_UPDATE", "player")
	end
end

------------------------------------------------------------------------
-- Console
------------------------------------------------------------------------
function SIM.exec(code)
	local fn, err = loadstring("return " .. code, "=console")
	if not fn then fn, err = loadstring(code, "=console") end
	if not fn then return "syntax error: " .. tostring(err) end
	local res = { xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end) }
	if not res[1] then return "error: " .. tostring(res[2]) end
	local parts = {}
	for i = 2, table.maxn(res) do parts[#parts + 1] = SIM.dump(res[i]) end
	if #parts == 0 then return "(no value)" end
	return table.concat(parts, "\n")
end

------------------------------------------------------------------------
-- Poll state
------------------------------------------------------------------------
local function since(list, seq, out)
	for _, item in ipairs(list) do
		if item.seq > seq then out[#out + 1] = item end
	end
	return out
end

function SIM.state(chatSeq, errSeq, soundSeq, msgSeq, stubSeq, inspect, ix, iy)
	local scene = SIM.scene()
	scene.__array = true
	local st = {
		scene = scene,
		now = SIM.now,
		W = SIM.screenW, H = SIM.screenH,
		focus = SIM.focus and S[SIM.focus] and S[SIM.focus].id or nil,
		chat = since(SIM.chatLines, chatSeq, { __array = true }),
		errors = since(SIM.errors, errSeq, { __array = true }),
		errorCount = #SIM.errors,
		sounds = since(SIM.sounds, soundSeq, { __array = true }),
		addonMsgs = since(SIM.addonMessages, msgSeq, { __array = true }),
		hover = SIM.hover and S[SIM.hover] and (S[SIM.hover].name or (S[SIM.hover].otype .. "#" .. S[SIM.hover].id)) or nil,
		combat = SIM.profile.inCombat,
	}
	if SIM.openChat then st.openChat = SIM.openChat SIM.openChat = nil end
	if SIM.stubSeq > stubSeq then
		local stubs = {}
		for name, s in pairs(SIM.stubs) do stubs[#stubs + 1] = { n = name, c = s.count } end
		table.sort(stubs, function(a, b) return a.n < b.n end)
		st.stubs = stubs
		st.stubSeq = SIM.stubSeq
	end
	if inspect then st.inspect = SIM.inspectAt(ix, iy) end
	return SIM.json(st)
end

function SIM.info()
	return SIM.json({
		slash = SIM.listSlash(),
		categories = SIM.listCategories(),
		profile = SIM.profile,
		classes = (function() local t = {} for k in pairs(SIM.CLASSES) do t[#t + 1] = k end table.sort(t) return t end)(),
	})
end
