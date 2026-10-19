-- WowSim: the pretend game. Player/target/group state comes from the control
-- panel (SIM.profile); everything here reads it live.

local SIM = __SIM
local S = SIM.S
local type, pairs, ipairs, tostring, select, unpack = type, pairs, ipairs, tostring, select, unpack
local sformat, slower, supper, sgsub, smatch = string.format, string.lower, string.upper, string.gsub, string.match
local floor = math.floor

------------------------------------------------------------------------
-- Root frames
------------------------------------------------------------------------
UIParent = SIM.createRoot("UIParent")
WorldFrame = SIM.createRoot("WorldFrame")
SIM.hiddenParent = CreateFrame("Frame", nil, UIParent)
SIM.hiddenParent:Hide()

------------------------------------------------------------------------
-- Profile (fake character); the panel overwrites fields via SIM.setProfile
------------------------------------------------------------------------
local CLASSES = {
	WARRIOR = { "Warrior", 1, "RAGE", 1, 0.78, 0.61, 0.43 },
	PALADIN = { "Paladin", 2, "MANA", 0, 0.96, 0.55, 0.73 },
	HUNTER = { "Hunter", 3, "MANA", 0, 0.67, 0.83, 0.45 },
	ROGUE = { "Rogue", 4, "ENERGY", 3, 1.00, 0.96, 0.41 },
	PRIEST = { "Priest", 5, "MANA", 0, 1.00, 1.00, 1.00 },
	DEATHKNIGHT = { "Death Knight", 6, "RUNIC_POWER", 6, 0.77, 0.12, 0.23 },
	SHAMAN = { "Shaman", 7, "MANA", 0, 0.00, 0.44, 0.87 },
	MAGE = { "Mage", 8, "MANA", 0, 0.25, 0.78, 0.92 },
	WARLOCK = { "Warlock", 9, "MANA", 0, 0.53, 0.53, 0.93 },
	MONK = { "Monk", 10, "ENERGY", 3, 0.00, 1.00, 0.60 },
	DRUID = { "Druid", 11, "MANA", 0, 1.00, 0.49, 0.04 },
	DEMONHUNTER = { "Demon Hunter", 12, "FURY", 17, 0.64, 0.19, 0.79 },
	EVOKER = { "Evoker", 13, "MANA", 0, 0.20, 0.58, 0.50 },
}
SIM.CLASSES = CLASSES

SIM.profile = {
	name = "Simsalot", realm = "Simrealm", class = "PRIEST", level = 60, race = "Human", faction = "Alliance",
	health = 100, healthMax = 100, power = 100, powerMax = 100, inCombat = false, dead = false,
	mounted = false, resting = false, afk = false, money = 1234567, xp = 4200, xpMax = 10000,
	zone = "Elwynn Forest", subZone = "Goldshire", group = 0, raid = false, leader = true,
	target = { exists = false, name = "Defias Bandit", level = 12, hostile = true, classification = "normal",
		creatureType = "Humanoid", health = 100, dead = false, isPlayer = false, class = "WARRIOR" },
	party = {
		{ name = "Tankyboi", class = "WARRIOR", level = 60 },
		{ name = "Healzor", class = "PRIEST", level = 60 },
		{ name = "Stabbs", class = "ROGUE", level = 59 },
		{ name = "Frostie", class = "MAGE", level = 60 },
	},
	spells = {},
	loopbackAddonMessages = true,
}

local P = SIM.profile

local function unitInfo(unit)
	if type(unit) ~= "string" then return end
	unit = slower(unit)
	if unit == "player" or unit == "vehicle" then
		return { name = P.name, class = P.class, level = P.level, isPlayer = true, friendly = true,
			health = P.health, healthMax = P.healthMax, dead = P.dead, me = true, combat = P.inCombat, guid = "Player-0000-00000001" }
	end
	if unit == "target" or unit == "softenemy" or unit == "mouseover" then
		local t = P.target
		if not t or not t.exists then return end
		return { name = t.name, class = t.class or "WARRIOR", level = t.level, isPlayer = t.isPlayer, friendly = not t.hostile,
			health = t.health or 100, healthMax = 100, dead = t.dead, classification = t.classification,
			creatureType = t.creatureType, combat = P.inCombat and t.hostile, guid = t.isPlayer and "Player-0000-00000099" or "Creature-0-0000-0000-0000-1234-000000001" }
	end
	if unit == "targettarget" then
		if P.target and P.target.exists and P.target.hostile and P.inCombat then return unitInfo("player") end
		return
	end
	local n = smatch(unit, "^party(%d)$") or smatch(unit, "^raid(%d+)$")
	if n then
		n = tonumber(n)
		if n <= (P.group or 0) and P.party[n] then
			local m = P.party[n]
			return { name = m.name, class = m.class, level = m.level, isPlayer = true, friendly = true,
				health = m.health or 100, healthMax = 100, dead = m.dead, combat = P.inCombat, guid = "Player-0000-0000000" .. (n + 1) }
		end
	end
end
SIM.unitInfo = unitInfo

function UnitExists(u) return unitInfo(u) ~= nil end
function UnitName(u) local i = unitInfo(u) if i then return i.name, nil end end
function UnitNameUnmodified(u) return UnitName(u) end
function UnitFullName(u) local i = unitInfo(u) if i then return i.name, P.realm end end
function GetUnitName(u, showServer) return (UnitName(u)) end
function UnitGUID(u) local i = unitInfo(u) return i and i.guid end
function UnitIsUnit(a, b)
	local x, y = unitInfo(a), unitInfo(b)
	return x ~= nil and y ~= nil and x.guid == y.guid
end
function UnitClass(u)
	local i = unitInfo(u)
	if not i then return end
	local c = CLASSES[i.class] or CLASSES.WARRIOR
	return c[1], i.class, c[2]
end
function UnitClassBase(u) local _, t, id = UnitClass(u) return t, id end
function UnitLevel(u) local i = unitInfo(u) return i and i.level or 0 end
function UnitEffectiveLevel(u) return UnitLevel(u) end
function UnitRace(u) if unitInfo(u) then return P.race, sgsub(P.race, " ", ""), 1 end end
function UnitFactionGroup(u) if unitInfo(u) then return P.faction, P.faction end end
function UnitSex(u) return 2 end
function UnitHealth(u) local i = unitInfo(u) return i and i.health or 0 end
function UnitHealthMax(u) local i = unitInfo(u) return i and i.healthMax or 0 end
function UnitHealthPercent(u) local i = unitInfo(u) return i and (i.health / math.max(1, i.healthMax)) or 0 end
function UnitPower(u, ptype)
	local i = unitInfo(u)
	if not i then return 0 end
	if i.me then return P.power end
	return 100
end
function UnitPowerMax(u) local i = unitInfo(u) if not i then return 0 end return i.me and P.powerMax or 100 end
function UnitPowerType(u)
	local i = unitInfo(u)
	local c = CLASSES[i and i.class or "WARRIOR"] or CLASSES.WARRIOR
	return c[4], c[3]
end
function UnitIsDead(u) local i = unitInfo(u) return i and i.dead or false end
function UnitIsGhost(u) return false end
function UnitIsDeadOrGhost(u) return UnitIsDead(u) end
function UnitIsCorpse(u) return false end
function UnitAffectingCombat(u) local i = unitInfo(u) return i and i.combat or false end
function UnitIsPlayer(u) local i = unitInfo(u) return i and i.isPlayer or false end
function UnitPlayerControlled(u) return UnitIsPlayer(u) end
function UnitIsFriend(a, b) local i = unitInfo(b) if not i then return false end return i.friendly end
function UnitIsEnemy(a, b) local i = unitInfo(b) if not i then return false end return not i.friendly end
function UnitCanAttack(a, b) return UnitIsEnemy(a, b) end
function UnitCanAssist(a, b) return UnitIsFriend(a, b) end
function UnitCanCooperate(a, b) return UnitIsFriend(a, b) and UnitIsPlayer(b) end
function UnitReaction(a, b) local i = unitInfo(b) if not i then return end return i.friendly and 5 or 2 end
function UnitClassification(u) local i = unitInfo(u) return i and (i.classification or "normal") or "normal" end
function UnitCreatureType(u) local i = unitInfo(u) if i and not i.isPlayer then return i.creatureType or "Humanoid" end if i then return "Humanoid" end end
function UnitCreatureFamily(u) return nil end
function UnitIsConnected(u) return unitInfo(u) ~= nil end
function UnitIsAFK(u) local i = unitInfo(u) return i and i.me and P.afk or false end
function UnitIsDND(u) return false end
function UnitInParty(u) local i = unitInfo(u) return i ~= nil and i.isPlayer and i.friendly and ((P.group or 0) > 0 or i.me) end
function UnitInRaid(u) if P.raid and UnitInParty(u) then return 1 end end
function UnitIsGroupLeader(u) local i = unitInfo(u) return i and i.me and P.leader or false end
function UnitIsGroupAssistant(u) return false end
function UnitXP(u) return P.xp end
function UnitXPMax(u) return P.xpMax end
function GetXPExhaustion() return nil end
function UnitIsTapDenied(u) return false end
function UnitIsPVP(u) return false end
function UnitIsTrivial(u) return false end
function UnitIsVisible(u) return unitInfo(u) ~= nil end
function UnitInRange(u) local i = unitInfo(u) return i ~= nil, i ~= nil end
function CheckInteractDistance(u, d) return unitInfo(u) ~= nil end
function UnitGroupRolesAssigned(u) return "NONE" end
function UnitPosition(u) return 0, 0, 0, 0 end
function UnitOnTaxi(u) return false end
function UnitInVehicle(u) return false end
function UnitHasVehicleUI(u) return false end
function UnitUsingVehicle(u) return false end
function UnitCastingInfo(u) return nil end
function UnitChannelInfo(u) return nil end
function UnitThreatSituation(u, m) return nil end
function UnitDetailedThreatSituation(u, m) return nil end
function UnitSelectionColor(u) return 1, 0, 0, 1 end
function UnitAura(u, i, filter) return nil end
function UnitBuff(u, i, filter) return nil end
function UnitDebuff(u, i, filter) return nil end
function UnitStat(u, i) return 50, 50, 0, 0 end
function UnitArmor(u) return 1000, 1000, 1000, 0, 0 end
function UnitAttackPower(u) return 500, 0, 0 end
function UnitRangedAttackPower(u) return 500, 0, 0 end
function UnitAttackSpeed(u) return 2.0, 2.0 end
function UnitRangedDamage(u) return 2.8, 100, 150, 0, 0, 1 end
function UnitDamage(u) return 100, 150, 0, 0, 0, 0, 1 end
function UnitSpellHaste(u) return 0 end
function GetHaste() return 0 end
function GetCritChance() return 5 end
function GetSpellCritChance() return 5 end
function GetRangedCritChance() return 5 end
function GetComboPoints() return 0 end
function GetShapeshiftForm() return 0 end
function GetNumShapeshiftForms() return 0 end
function IsStealthed() return false end
function IsMounted() return P.mounted end
function IsResting() return P.resting end
function IsFlying() return false end
function IsSwimming() return false end
function IsFalling() return false end
function IsIndoors() return false end
function IsOutdoors() return true end
function GetUnitSpeed() return 0, 7, 7, 4.72 end
function GetPlayerFacing() return 0 end
function InCombatLockdown() return P.inCombat end
function IsInGroup() return (P.group or 0) > 0 end
function IsInRaid() return P.raid and (P.group or 0) > 0 end
function GetNumGroupMembers() local g = P.group or 0 return g > 0 and g + 1 or 0 end
function GetNumSubgroupMembers() return P.group or 0 end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return P.zone, "none", 0, "", 5, 0, false, 0, 0 end
function IsInGuild() return false end
function GetGuildInfo() return nil end
function GetMoney() return P.money end
function GetRealZoneText() return P.zone end
function GetZoneText() return P.zone end
function GetSubZoneText() return P.subZone end
function GetMinimapZoneText() return P.subZone ~= "" and P.subZone or P.zone end
function GetZonePVPInfo() return nil end
function GetRealmName() return P.realm end
function GetNormalizedRealmName() return (sgsub(P.realm, "[%s%-]", "")) end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.60.1", "70009", "Oct 1 2026", 16001, "", "", 16001 end
function GetCurrentRegion() return 1 end
function GetCurrentRegionName() return "US" end
function IsTrialAccount() return false end
function IsVeteranTrialAccount() return false end
function GetRestrictedAccountData() return 0, 0, 0 end
function HasNewMail() return false end
function GetPlayerInfoByGUID(guid)
	for _, u in ipairs({ "player", "target", "party1", "party2", "party3", "party4" }) do
		local i = unitInfo(u)
		if i and i.guid == guid then
			local c = CLASSES[i.class] or CLASSES.WARRIOR
			return c[1], i.class, P.race, P.race, 2, i.name, P.realm
		end
	end
end
function GetRaidRosterInfo(i)
	local u = i == 1 and "player" or ("party" .. (i - 1))
	local info = unitInfo(u)
	if not info then return end
	local c = CLASSES[info.class] or CLASSES.WARRIOR
	return info.name, i == 1 and 2 or 0, 1, info.level, c[1], info.class, P.zone, true, false, "NONE", false
end
function GetRaidTargetIndex() return nil end
function SetRaidTarget() end
function GetPartyAssignment() return false end
function GetLootMethod() return "group", 0, nil end
function GetNumClasses() return 13 end
function GetClassInfo(id)
	for token, c in pairs(CLASSES) do if c[2] == id then return c[1], token, id end end
end
function GetClassColor(class)
	local c = RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b, c.colorStr end
	return 1, 1, 1, "ffffffff"
end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 0, "Spec", "", 136243, "DAMAGER" end
function GetActiveSpecGroup() return 1 end

------------------------------------------------------------------------
-- Time / system
------------------------------------------------------------------------
function GetCurrentEnvironment() return _G end
function GetTime() return SIM.now end
function GetTimePreciseSec() return SIM.now end
function GetServerTime() return time() end
function GetGameTime() local d = date("*t") return d.hour, d.min end
function GetSessionTime() return floor(SIM.now) end
function GetFramerate() return 60 end
function GetNetStats() return 0, 0, 42, 42 end
function GetFileStreamingStatus() return 0 end
function GetBackgroundLoadingStatus() return 0 end
function debugprofilestart() SIM.profStart = SIM.realClock() end
function debugprofilestop() return (SIM.realClock() - (SIM.profStart or 0)) * 1000 end
function debugstack(start, top, bottom) return debug.traceback("", (start or 1) + 1) end
function debuglocals() return "" end
function GetCVar(k) return SIM.cvars[k] end
function GetCVarBool(k) local v = SIM.cvars[k] return v == "1" or v == true end
function GetCVarDefault(k) return SIM.cvars[k] end
function SetCVar(k, v) SIM.cvars[k] = v ~= nil and tostring(v) or nil return true end
function GetCVarBitfield(k, i) return false end
function SetCVarBitfield(k, i, v) return true end
function RegisterCVar(k, v) if SIM.cvars[k] == nil then SIM.cvars[k] = v and tostring(v) end end
SIM.cvars = { uiScale = "1", useUiScale = "0", Sound_EnableSFX = "1", nameplateShowEnemies = "1", autoLootDefault = "1", scriptErrors = "1" }
function IsShiftKeyDown() return SIM.mods.shift end
function IsLeftShiftKeyDown() return SIM.mods.shift end
function IsRightShiftKeyDown() return false end
function IsControlKeyDown() return SIM.mods.ctrl end
function IsLeftControlKeyDown() return SIM.mods.ctrl end
function IsRightControlKeyDown() return false end
function IsAltKeyDown() return SIM.mods.alt end
function IsLeftAltKeyDown() return SIM.mods.alt end
function IsRightAltKeyDown() return false end
function IsMetaKeyDown() return false end
function IsModifierKeyDown() return SIM.mods.shift or SIM.mods.ctrl or SIM.mods.alt end
function IsMouseButtonDown(b) return SIM.mouseState ~= nil end
function IsKeyDown(k) return false end
function GetCursorPosition() return SIM.cursor.x, SIM.cursor.y end
function GetScreenWidth() return SIM.screenW end
function GetScreenHeight() return SIM.screenH end
function GetPhysicalScreenSize() return floor(SIM.screenW * 1080 / 768), 1080 end
function GetScreenDPIScale() return 1 end
function GetMouseFocus() return SIM.hover end
function GetMouseFoci() return { SIM.hover } end
function GetMouseButtonClicked() return SIM.lastClickButton end
function ReloadUI() SIM.py.request("reload") end
function Logout() SIM.chat("[Sim] Logout() called", 1, 0.5, 0.5) end
function Quit() SIM.chat("[Sim] Quit() called", 1, 0.5, 0.5) end
function Screenshot() SIM.chat("[Sim] Screenshot taken (not really)", 1, 1, 0) end
function GetBindingKey() return nil end
function GetBindingText(k) return k or "" end
function GetBindingAction() return "" end
function GetBinding() return nil end
function GetNumBindings() return 0 end
function SetBinding() return true end
function SetBindingClick() return true end
function SetBindingSpell() return true end
function SetOverrideBinding() end
function SetOverrideBindingClick() end
function ClearOverrideBindings() end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function RunBinding() end
function CombatLogGetCurrentEventInfo() return nil end
function CombatLog_Object_IsA() return false end
function GetAddOnCPUUsage() return 0 end
function GetAddOnMemoryUsage() return 0 end
function UpdateAddOnMemoryUsage() end
function UpdateAddOnCPUUsage() end
function collectgarbage(opt) if opt == "count" then return 1024 end return 0 end
function GetLatestThreeSenders() return nil end
function IsPlayerSpell(id) return SIM.spellKnown(id) end
function IsSpellKnown(id) return SIM.spellKnown(id) end
function IsSpellKnownOrOverridesKnown(id) return SIM.spellKnown(id) end
function SetPortraitTexture(tex, unit) if tex and tex.SetColorTexture then tex:SetColorTexture(0.3, 0.3, 0.35, 1) end end
function SetPortraitToTexture(tex, path) if type(tex) == "table" and tex.SetTexture then tex:SetTexture(path) end end
function SetRaidTargetIconTexture() end
function RegisterStateDriver() end
function UnregisterStateDriver() end
function RegisterAttributeDriver() end
function UnregisterAttributeDriver() end
function RegisterUnitWatch() end
function UnregisterUnitWatch() end
function SecureCmdOptionParse(s) return s end
function SecureHandlerWrapScript() end
function SecureHandler_OnLoad() end
function GetActionInfo() return nil end
function HasAction() return false end
function GetActionTexture() return nil end
function GetActionCooldown() return 0, 0, 1 end
function IsUsableAction() return false, false end
function IsActionInRange() return nil end
function GetMacroInfo() return nil end
function GetNumMacros() return 0, 0 end
function DoEmote(e) SIM.chat("[Sim] /" .. slower(tostring(e)), 1, 0.5, 0.25) end
function RepopMe() end
function AcceptGroup() SIM.chat("[Sim] AcceptGroup()", 0.6, 0.6, 1) end
function DeclineGroup() end
function InviteUnit(n) SIM.chat("[Sim] invited " .. tostring(n), 0.6, 0.6, 1) end
C_PartyInfo = C_PartyInfo or {}
function C_PartyInfo.InviteUnit(n) InviteUnit(n) end
function C_PartyInfo.LeaveParty() SIM.chat("[Sim] left party", 0.6, 0.6, 1) end
function C_PartyInfo.ConvertToRaid() end
function C_PartyInfo.IsPartyFull() return (P.group or 0) >= 4 end
function LeaveParty() C_PartyInfo.LeaveParty() end

------------------------------------------------------------------------
-- Spells (a small fake spellbook; names come from the profile)
------------------------------------------------------------------------
SIM.spellDB = SIM.spellDB or {}
local function spellRecord(id)
	if id == nil then return end
	if type(id) == "string" then
		local n = tonumber(id)
		if n then id = n
		else
			for sid, rec in pairs(SIM.spellDB) do if slower(rec.name) == slower(id) then return rec, sid end end
			for _, s in ipairs(P.spells or {}) do if slower(s.name or "") == slower(id) then return s, s.id end end
			return nil
		end
	end
	local rec = SIM.spellDB[id]
	if not rec then
		for _, s in ipairs(P.spells or {}) do
			if s.id == id and s.name and s.name ~= "" and not s.name:match("^Spell %d+$") then rec = s break end
		end
	end
	if not rec and type(id) == "number" and SIM.py.spellInfo then
		local name, icon = SIM.py.spellInfo(id)
		if name then
			rec = { name = name, icon = "Interface\\Icons\\" .. icon }
			SIM.spellDB[id] = rec
		end
	end
	return rec, id
end

local spellsChangedPending = false
function SIM.spellLoaded(id, name, icon)
	SIM.spellDB[id] = { name = name, icon = "Interface\\Icons\\" .. icon }
	SIM.fireEvent("SPELL_DATA_LOAD_RESULT", id, true)
	for _, s in ipairs(P.spells or {}) do
		if s.id == id and not spellsChangedPending then
			spellsChangedPending = true
			C_Timer.After(0.4, function() spellsChangedPending = false SIM.fireEvent("SPELLS_CHANGED") end)
		end
	end
end
SIM.spellRecord = spellRecord
function SIM.spellKnown(id)
	local rec, sid = spellRecord(id)
	if not sid then return false end
	for _, s in ipairs(P.spells or {}) do if s.id == sid then return true end end
	return false
end
function GetSpellInfo(spell)
	local rec, id = spellRecord(spell)
	if not id or not rec then return nil end -- not cached yet: SPELL_DATA_LOAD_RESULT follows
	local icon = rec.icon or 134400
	return rec.name, nil, icon, 0, 0, 0, id, icon
end
function GetSpellTexture(spell) local _, _, icon = GetSpellInfo(spell) return icon end
function GetSpellCooldown(spell) return 0, 0, 1, 1 end
function GetSpellLink(spell) local n, _, _, _, _, _, id = GetSpellInfo(spell) if n then return "|cff71d5ff|Hspell:" .. id .. "|h[" .. n .. "]|h|r" end end
function GetSpellDescription(spell) return "" end
function IsUsableSpell(spell) return SIM.spellKnown(spell), false end
function IsSpellInRange() return 1 end
function GetSpellCharges() return nil end
function GetSpellCount() return 0 end
function IsCurrentSpell() return false end
function IsAutoRepeatSpell() return false end
function SpellIsTargeting() return false end
function CastSpellByName(n) SIM.chat("[Sim] cast " .. tostring(n), 0.5, 0.8, 1) end
function CastSpellByID(id) SIM.chat("[Sim] cast spell " .. tostring(id), 0.5, 0.8, 1) end
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo(i) if i == 1 then return "General", 136243, 0, #(P.spells or {}), false, 0 end end
function GetSpellBookItemName(i, book) local s = (P.spells or {})[i] if s then local r = spellRecord(s.id) return r and r.name or s.name, "" end end
function GetSpellBookItemInfo(i, book) local s = (P.spells or {})[i] if s then return "SPELL", s.id end end
function GetSpellBookItemTexture(i) local s = (P.spells or {})[i] if s then return s.icon or 134400 end end
function HasPetSpells() return nil end

C_SpellBook = C_SpellBook or {}
local function bookSpell(i)
	local s = (P.spells or {})[i]
	if not s then return end
	local rec = spellRecord(s.id)
	return s, rec
end
function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
function C_SpellBook.GetSpellBookSkillLineInfo(i)
	if i ~= 1 then return nil end
	return { name = "General", iconID = 136243, itemIndexOffset = 0, numSpellBookItems = #(P.spells or {}), isGuild = false, shouldHide = false }
end
function C_SpellBook.GetSpellBookItemInfo(i, bank)
	local s, rec = bookSpell(i)
	if not s then return nil end
	return { actionID = s.id, spellID = s.id, itemType = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1,
		name = rec and rec.name or "", subName = "", iconID = rec and rec.icon or 134400, isPassive = false, isOffSpec = false, skillLineIndex = 1 }
end
function C_SpellBook.GetSpellBookItemName(i, bank) local s, rec = bookSpell(i) if rec then return rec.name, "" end end
function C_SpellBook.GetSpellBookItemTexture(i, bank) local s, rec = bookSpell(i) if s then return rec and rec.icon or 134400 end end
function C_SpellBook.GetSpellBookItemType(i, bank) local s = bookSpell(i) if s then return (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1, s.id, s.id end end
function C_SpellBook.IsSpellKnown(id) return SIM.spellKnown(id) end
function C_SpellBook.IsSpellInSpellBook(id) return SIM.spellKnown(id) end
function C_SpellBook.HasPetSpells() return nil end
function C_SpellBook.FindSpellBookSlotForSpell(id)
	for i, s in ipairs(P.spells or {}) do if s.id == id then return i, 0 end end
end

C_Spell = C_Spell or {}
function C_Spell.GetSpellInfo(spell)
	local name, _, icon, castTime, minR, maxR, id = GetSpellInfo(spell)
	if not name then return nil end
	return { name = name, iconID = icon, originalIconID = icon, castTime = castTime, minRange = minR, maxRange = maxR, spellID = id }
end
function C_Spell.GetSpellName(spell) return (GetSpellInfo(spell)) end
function C_Spell.GetSpellTexture(spell) local _, _, icon = GetSpellInfo(spell) return icon, icon end
function C_Spell.GetSpellCooldown(spell)
	return { startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }
end
function C_Spell.IsSpellUsable(spell) return SIM.spellKnown(spell), false end
function C_Spell.DoesSpellExist(spell) return spellRecord(spell) ~= nil or type(spell) == "number" end
function C_Spell.GetSpellLink(spell) return GetSpellLink(spell) end
function C_Spell.GetSpellSubtext(spell) return "" end
function C_Spell.GetSpellDescription(spell) return "" end
function C_Spell.IsSpellInRange() return true end
function C_Spell.GetSpellCharges() return nil end
function C_Spell.GetSpellPowerCost() return {} end
function C_Spell.RequestLoadSpellData() end
function C_Spell.IsSpellDataCached(spell) return spellRecord(spell) ~= nil end

------------------------------------------------------------------------
-- Items / bags (empty bags, a few free slots)
------------------------------------------------------------------------
function GetItemInfo(item) return nil end
function GetItemInfoInstant(item) if type(item) == "number" then return item, "", "", "", 134400, 0, 0 end end
function GetItemCount() return 0 end
function GetItemIcon() return 134400 end
function GetItemCooldown() return 0, 0, 1 end
function IsEquippedItem() return false end
function GetInventoryItemID() return nil end
function GetInventoryItemLink() return nil end
function GetInventoryItemTexture() return nil end
function GetInventoryItemDurability() return 100, 100 end
function GetInventorySlotInfo(n) return 1, nil end
function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
function GetContainerNumFreeSlots(bag) return bag == 0 and 9 or 0, 0 end
C_Container = C_Container or {}
C_Container.GetContainerNumSlots = GetContainerNumSlots
C_Container.GetContainerNumFreeSlots = GetContainerNumFreeSlots
function C_Container.GetContainerItemInfo() return nil end
function C_Container.GetContainerItemID() return nil end
function C_Container.GetContainerItemLink() return nil end
function C_Container.GetItemCooldown() return 0, 0, 1 end
function C_Container.UseContainerItem(b, s) SIM.chat("[Sim] use bag " .. tostring(b) .. " slot " .. tostring(s), 0.8, 0.8, 0.8) end
C_Item = C_Item or {}
function C_Item.GetItemInfo(i) return nil end
function C_Item.GetItemNameByID(i) return nil end
function C_Item.GetItemCount() return 0 end
function C_Item.GetItemIconByID() return 134400 end
function C_Item.GetItemInfoInstant(i) return GetItemInfoInstant(i) end
function C_Item.RequestLoadItemDataByID() end
function C_Item.IsItemDataCachedByID() return true end
function C_Item.DoesItemExistByID() return true end

------------------------------------------------------------------------
-- Addons
------------------------------------------------------------------------
SIM.addons = SIM.addons or {}      -- name -> { meta = {}, loaded = bool, title, notes }
SIM.addonOrder = SIM.addonOrder or {}
local function addonByIndexOrName(x)
	if type(x) == "number" then local n = SIM.addonOrder[x] return n and SIM.addons[n], n end
	for name, a in pairs(SIM.addons) do if slower(name) == slower(tostring(x)) then return a, name end end
end
C_AddOns = C_AddOns or {}
function C_AddOns.GetAddOnMetadata(addon, field)
	local a = addonByIndexOrName(addon)
	if not a then return nil end
	if field and a.meta then
		for k, v in pairs(a.meta) do if slower(k) == slower(field) then return v end end
	end
end
function C_AddOns.IsAddOnLoaded(addon) local a = addonByIndexOrName(addon) return a and a.loaded or false, a and a.loaded or false end
function C_AddOns.GetNumAddOns() return #SIM.addonOrder end
function C_AddOns.GetAddOnInfo(addon)
	local a, name = addonByIndexOrName(addon)
	if not a then return nil end
	return name, a.meta.Title or name, a.meta.Notes or "", true, a.loaded and "INSECURE" or "DEMAND_LOADED", "INSECURE", false
end
function C_AddOns.LoadAddOn(addon) local a = addonByIndexOrName(addon) if a then return true end return false, "MISSING" end
function C_AddOns.EnableAddOn() end
function C_AddOns.DisableAddOn() end
function C_AddOns.DoesAddOnExist(addon) return addonByIndexOrName(addon) ~= nil end
function C_AddOns.GetAddOnEnableState(addon) return addonByIndexOrName(addon) and 2 or 0 end
function C_AddOns.IsAddOnLoadOnDemand() return false end
function C_AddOns.GetAddOnDependencies() return end
function C_AddOns.GetAddOnOptionalDependencies() return end
function C_AddOns.IsAddOnLoadable(addon) return addonByIndexOrName(addon) ~= nil end
function C_AddOns.GetAddOnTitle(addon) return C_AddOns.GetAddOnMetadata(addon, "Title") end
function C_AddOns.GetAddOnNotes(addon) return C_AddOns.GetAddOnMetadata(addon, "Notes") end
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
IsAddOnLoaded = C_AddOns.IsAddOnLoaded
GetNumAddOns = C_AddOns.GetNumAddOns
GetAddOnInfo = C_AddOns.GetAddOnInfo
LoadAddOn = C_AddOns.LoadAddOn
EnableAddOn = C_AddOns.EnableAddOn
DisableAddOn = C_AddOns.DisableAddOn
IsAddOnLoadOnDemand = C_AddOns.IsAddOnLoadOnDemand

------------------------------------------------------------------------
-- Error handler, hooks, security
------------------------------------------------------------------------
local userErrorHandler
function geterrorhandler()
	return userErrorHandler or function(msg) SIM.reportError({ msg = tostring(msg), stack = debug.traceback("", 2) }) end
end
function seterrorhandler(fn) userErrorHandler = fn end
function securecall(fn, ...)
	if type(fn) == "string" then fn = _G[fn] end
	return SIM.pcall(fn, ...)
end
function securecallfunction(fn, ...) return securecall(fn, ...) end
function secureexecuterange(t, fn, ...) for k, v in pairs(t) do securecall(fn, k, v, ...) end end
function issecure() return false end
function issecurevariable() return false, "WowSim" end
function forceinsecure() end
function issecretvalue() return false end
function canaccessvalue() return true end
function canaccesstable() return true end
function issecrettable() return false end
function hasanysecretvalues() return false end
function scrubsecretvalues(...) return ... end
function secretwrap(...) return ... end

function hooksecurefunc(tbl, name, fn)
	if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
	if type(tbl) ~= "table" then error("hooksecurefunc(): bad table", 2) end
	local orig = tbl[name]
	if type(orig) ~= "function" then
		-- Probably a Blizzard function we do not simulate: hook a no-op so the addon keeps loading.
		SIM.noteStub("hooksecurefunc target missing: " .. tostring(name))
		orig = function() end
	end
	tbl[name] = function(...)
		local r = { orig(...) }
		local n = select("#", ...)
		local args = { ... }
		SIM.pcall(fn, unpack(args, 1, n))
		return unpack(r)
	end
end

------------------------------------------------------------------------
-- Timers
------------------------------------------------------------------------
C_Timer = {}
local TimerMethods = {}
TimerMethods.__index = TimerMethods
function TimerMethods:Cancel() self._t.cancelled = true end
function TimerMethods:IsCancelled() return self._t.cancelled or false end
function TimerMethods:Invoke(...) return self._t.fn(self, ...) end
function TimerMethods:GetRemainingTime() return math.max(0, self._t.at - SIM.now) end

local function newTimer(seconds, fn, iterations, repeating)
	if type(fn) ~= "function" and not (type(fn) == "table" and getmetatable(fn) and getmetatable(fn).__call) then
		error("C_Timer: callback must be a function", 3)
	end
	local t = { at = SIM.now + math.max(0, seconds or 0), fn = fn }
	local handle = setmetatable({ _t = t }, TimerMethods)
	t.handle = handle
	if repeating then t.interval = math.max(0.01, seconds or 0) t.iterations = iterations end
	SIM.addTimer(t)
	return handle
end
function C_Timer.After(seconds, fn)
	local t = { at = SIM.now + math.max(0, seconds or 0), fn = function() fn() end }
	SIM.addTimer(t)
end
function C_Timer.NewTimer(seconds, fn) return newTimer(seconds, fn, 1, true) end
function C_Timer.NewTicker(seconds, fn, iterations) return newTimer(seconds, fn, iterations, true) end

------------------------------------------------------------------------
-- Chat, print, slash commands
------------------------------------------------------------------------
SIM.chatLines, SIM.chatSeq = {}, 0
function SIM.chat(text, r, g, b, frameName)
	SIM.chatSeq = SIM.chatSeq + 1
	local lines = SIM.chatLines
	lines[#lines + 1] = { seq = SIM.chatSeq, t = tostring(text), c = { r or 1, g or 1, b or 1 }, time = date("%H:%M:%S") }
	if #lines > 500 then table.remove(lines, 1) end
end

local ChatHolder = CreateFrame("Frame", nil, SIM.hiddenParent)
for i = 1, 10 do
	local cf = CreateFrame("ScrollingMessageFrame", "ChatFrame" .. i, ChatHolder)
	S[cf].isChat = (i == 1)
	cf:SetSize(430, 120)
	cf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95)
	cf:SetFontObject(ChatFontNormal)
	cf.editBox = CreateFrame("EditBox", "ChatFrame" .. i .. "EditBox", cf)
end
DEFAULT_CHAT_FRAME = ChatFrame1
SELECTED_CHAT_FRAME = ChatFrame1
NUM_CHAT_WINDOWS = 10
ChatFrame1EditBox = ChatFrame1.editBox
function ChatFrame_OpenChat(text) SIM.openChat = text or "" end
function ChatFrame_AddMessageEventFilter() end
function ChatFrame_RemoveMessageEventFilter() end
function ChatFrame_GetMessageEventFilters() return {} end
function ChatFrame_AddChannel() end
function ChatEdit_GetActiveWindow() return nil end
function ChatEdit_InsertLink(link) return false end
function ChatEdit_ChooseBoxForSend() return ChatFrame1EditBox end
function ChatEdit_ActivateChat() end
function ChatEdit_SendText() end
function ChatFrame_SendTell(name) SIM.openChat = "/w " .. tostring(name) .. " " end
function FCF_GetCurrentChatFrame() return ChatFrame1 end
ChatTypeInfo = setmetatable({}, { __index = function(t, k) local v = { r = 1, g = 1, b = 1, id = 0, sticky = 0 } rawset(t, k, v) return v end })
ChatTypeInfo.SYSTEM = { r = 1, g = 1, b = 0, id = 1 }
ChatTypeInfo.SAY = { r = 1, g = 1, b = 1 }
ChatTypeInfo.PARTY = { r = 0.67, g = 0.67, b = 1 }
ChatTypeInfo.WHISPER = { r = 1, g = 0.5, b = 1 }
ChatTypeInfo.GUILD = { r = 0.25, g = 1, b = 0.25 }

function print(...)
	local t = {}
	for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
	SIM.chat(table.concat(t, " "), 1, 1, 1)
end
function message(text) SIM.showMessage(tostring(text)) end

SlashCmdList = SlashCmdList or {}
hash_SlashCmdList = {}
local BUILTIN_SLASH = {
	["/reload"] = function() ReloadUI() end, ["/rl"] = function() ReloadUI() end,
	["/console"] = function(msg) local k, v = smatch(msg, "^(%S+)%s*(.*)$") if k then SetCVar(k, v) end end,
	["/dump"] = function(msg)
		local f, err = loadstring("return " .. msg)
		if not f then SIM.chat("Dump error: " .. tostring(err), 1, 0.3, 0.3) return end
		local res = { SIM.pcall(f) }
		if res[1] then
			SIM.chat("Dump: " .. msg, 1, 0.82, 0)
			for i = 2, math.max(2, #res) do SIM.chat("[" .. (i - 1) .. "]=" .. SIM.dump(res[i]), 1, 1, 1) end
		end
	end,
	["/run"] = function(msg) local f, err = loadstring(msg) if f then SIM.pcall(f) else SIM.chat(tostring(err), 1, 0.3, 0.3) end end,
	["/script"] = function(msg) local f, err = loadstring(msg) if f then SIM.pcall(f) else SIM.chat(tostring(err), 1, 0.3, 0.3) end end,
	["/fstack"] = function() SIM.py.request("fstack") end,
	["/etrace"] = function() SIM.chat("[Sim] see the Events panel", 1, 1, 0) end,
}

local function findSlash(cmd)
	cmd = slower(cmd)
	for key in pairs(SlashCmdList) do
		local i = 1
		while true do
			local v = _G["SLASH_" .. key .. i]
			if not v then break end
			if slower(v) == cmd then return SlashCmdList[key] end
			i = i + 1
		end
	end
end

function SIM.listSlash()
	local out = {}
	for key in pairs(SlashCmdList) do
		local i = 1
		while true do
			local v = _G["SLASH_" .. key .. i]
			if not v then break end
			out[#out + 1] = v
			i = i + 1
		end
	end
	table.sort(out)
	return out
end

function SIM.chatInput(text)
	text = strtrim(text or "")
	if text == "" then return end
	local cmd, rest = smatch(text, "^(/%S+)%s*(.-)$")
	if cmd then
		local fn = findSlash(cmd)
		if fn then
			SIM.pcall(fn, rest, ChatFrame1EditBox)
			return
		end
		local b = BUILTIN_SLASH[slower(cmd)]
		if b then b(rest) return end
		local chatCmds = { ["/s"] = "SAY", ["/say"] = "SAY", ["/p"] = "PARTY", ["/party"] = "PARTY", ["/g"] = "GUILD",
			["/y"] = "YELL", ["/ra"] = "RAID", ["/i"] = "INSTANCE_CHAT" }
		if chatCmds[slower(cmd)] then SendChatMessage(rest, chatCmds[slower(cmd)]) return end
		local w = smatch(text, "^/w%s+(%S+)%s+(.+)$") or smatch(text, "^/whisper%s+(%S+)%s+(.+)$")
		if w then
			local name, msg = smatch(text, "^/%a+%s+(%S+)%s+(.+)$")
			SendChatMessage(msg, "WHISPER", nil, name)
			return
		end
		SIM.chat("Type '/help' for a listing of a few commands.", 1, 1, 0)
		SIM.chat("[Sim] Unknown command " .. cmd .. ". Addon commands: " .. table.concat(SIM.listSlash(), " "), 1, 0.6, 0.2)
		return
	end
	SendChatMessage(text, "SAY")
end

local CHAT_EVENTS = { SAY = "CHAT_MSG_SAY", YELL = "CHAT_MSG_YELL", PARTY = "CHAT_MSG_PARTY", RAID = "CHAT_MSG_RAID",
	GUILD = "CHAT_MSG_GUILD", WHISPER = "CHAT_MSG_WHISPER_INFORM", INSTANCE_CHAT = "CHAT_MSG_INSTANCE_CHAT", EMOTE = "CHAT_MSG_EMOTE" }
function SendChatMessage(msg, chatType, lang, target)
	chatType = supper(chatType or "SAY")
	local c = ChatTypeInfo[chatType] or ChatTypeInfo.SAY
	if chatType == "WHISPER" then
		SIM.chat("To [" .. tostring(target) .. "]: " .. tostring(msg), 1, 0.5, 1)
	elseif chatType == "EMOTE" then
		SIM.chat(P.name .. " " .. tostring(msg), 1, 0.5, 0.25)
	else
		local verb = ({ SAY = "says", YELL = "yells" })[chatType]
		if verb then SIM.chat("[" .. P.name .. "] " .. verb .. ": " .. tostring(msg), c.r, c.g, c.b)
		else SIM.chat("[" .. chatType:sub(1, 1) .. chatType:sub(2):lower() .. "] [" .. P.name .. "]: " .. tostring(msg), c.r, c.g, c.b) end
	end
	local ev = CHAT_EVENTS[chatType]
	if ev then
		C_Timer.After(0, function() SIM.fireEvent(ev, msg, P.name .. "-" .. P.realm, "Common", "", P.name, "", 0, 0, "", 0, 1, "Player-0000-00000001") end)
	end
end
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.SendChatMessage = SendChatMessage
local prefixes = {}
SIM.addonMessages, SIM.addonMsgSeq = {}, 0
function C_ChatInfo.RegisterAddonMessagePrefix(p) prefixes[p] = true return true end
function C_ChatInfo.IsAddonMessagePrefixRegistered(p) return prefixes[p] or false end
function C_ChatInfo.GetRegisteredAddonMessagePrefixes() local r = {} for p in pairs(prefixes) do r[#r + 1] = p end return r end
function C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
	SIM.addonMsgSeq = SIM.addonMsgSeq + 1
	local list = SIM.addonMessages
	list[#list + 1] = { seq = SIM.addonMsgSeq, prefix = prefix, msg = tostring(msg), channel = channel, target = target, time = date("%H:%M:%S") }
	if #list > 300 then table.remove(list, 1) end
	if P.loopbackAddonMessages and prefixes[prefix] then
		C_Timer.After(0.05, function()
			SIM.fireEvent("CHAT_MSG_ADDON", prefix, msg, channel, P.name .. "-" .. GetNormalizedRealmName(), target or "", 0, 0, "", 0)
		end)
	end
	return true, 0
end
C_ChatInfo.SendAddonMessageLogged = C_ChatInfo.SendAddonMessage
function C_ChatInfo.InChatMessagingLockdown() return false end
function C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() return false end
function C_ChatInfo.PerformEmote(e, target) DoEmote(e) end
function C_ChatInfo.GetChannelRosterInfo() return nil end
function C_ChatInfo.GetNumActiveChannels() return 0 end
RegisterAddonMessagePrefix = C_ChatInfo.RegisterAddonMessagePrefix
SendAddonMessage = C_ChatInfo.SendAddonMessage
function JoinChannelByName() return 1 end
function GetChannelName(n) return 0, nil end
function LeaveChannelByName() end
function Ambiguate(name, ctx)
	if type(name) ~= "string" then return name end
	local short, realm = smatch(name, "^([^%-]+)%-(.+)$")
	if short and (ctx == "short" or ctx == "none" and realm == GetNormalizedRealmName() or realm == GetNormalizedRealmName()) then return short end
	return name
end

------------------------------------------------------------------------
-- Sounds
------------------------------------------------------------------------
SIM.sounds, SIM.soundSeq = {}, 0
local function pushSound(kind, what, channel)
	SIM.soundSeq = SIM.soundSeq + 1
	SIM.sounds[#SIM.sounds + 1] = { seq = SIM.soundSeq, kind = kind, id = what, ch = channel }
	if #SIM.sounds > 50 then table.remove(SIM.sounds, 1) end
	return true, SIM.soundSeq
end
function PlaySound(kit, channel) return pushSound("kit", kit, channel) end
function PlaySoundFile(path, channel) return pushSound("file", path, channel) end
function PlayMusic(path) return pushSound("file", path, "Music") end
function StopMusic() end
function StopSound() end
C_Sound = C_Sound or {}
function C_Sound.PlaySound(kit, channel) return pushSound("kit", kit, channel) end
function C_Sound.PlaySoundFile(path, channel) return pushSound("file", path, channel) end
function C_Sound.PlaySoundWithOptions(kit, opts) return pushSound("kit", kit) end
function C_Sound.StopSound() end
function C_Sound.IsPlaying() return false end
SOUNDKIT = setmetatable({
	IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
	IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, U_CHAT_SCROLL_BUTTON = 1115, RAID_WARNING = 8959, READY_CHECK = 8960,
	ALARM_CLOCK_WARNING_3 = 12889, IG_QUEST_LOG_OPEN = 875, IG_CHARACTER_INFO_TAB = 841, GS_TITLE_OPTION_OK = 798,
	TELL_MESSAGE = 3081, MAP_PING = 3175, LEVELUP = 888, IG_PLAYER_INVITE = 880,
}, { __index = function() return 0 end })

------------------------------------------------------------------------
-- Colors and constants
------------------------------------------------------------------------
local ColorMixin = {}
function ColorMixin:OnLoad(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a or 1 end
function ColorMixin:GetRGBAsBytes() return floor(self.r * 255 + 0.5), floor(self.g * 255 + 0.5), floor(self.b * 255 + 0.5) end
function ColorMixin:SetRGB(r, g, b) self.r, self.g, self.b = r, g, b end
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:IsEqualTo(o) return self.r == o.r and self.g == o.g and self.b == o.b and self.a == o.a end
function ColorMixin:GenerateHexColor() return sformat("ff%02x%02x%02x", floor(self.r * 255 + 0.5), floor(self.g * 255 + 0.5), floor(self.b * 255 + 0.5)) end
function ColorMixin:GenerateHexColorNoAlpha() return sformat("%02x%02x%02x", floor(self.r * 255 + 0.5), floor(self.g * 255 + 0.5), floor(self.b * 255 + 0.5)) end
function ColorMixin:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
function ColorMixin:WrapTextInColorCode(t) return "|c" .. self:GenerateHexColor() .. tostring(t) .. "|r" end
ColorMixin.GetHex = ColorMixin.GenerateHexColor
_G.ColorMixin = ColorMixin
function CreateColor(r, g, b, a)
	local c = CreateFromMixins(ColorMixin)
	c:OnLoad(r, g, b, a)
	return c
end
function CreateColorFromHexString(hex)
	if #hex == 8 then
		local a, r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
		return CreateColor(r / 255, g / 255, b / 255, a / 255)
	end
end
function CreateColorFromBytes(r, g, b, a) return CreateColor(r / 255, g / 255, b / 255, (a or 255) / 255) end
function WrapTextInColorCode(text, hex) return "|c" .. hex .. tostring(text) .. "|r" end
function WrapTextInColor(text, color) return color:WrapTextInColorCode(text) end

NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0)
HIGHLIGHT_FONT_COLOR = CreateColor(1, 1, 1)
WHITE_FONT_COLOR = CreateColor(1, 1, 1)
RED_FONT_COLOR = CreateColor(1, 0.1, 0.1)
DIM_RED_FONT_COLOR = CreateColor(0.8, 0.1, 0.1)
GREEN_FONT_COLOR = CreateColor(0.1, 1, 0.1)
GRAY_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
DISABLED_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
YELLOW_FONT_COLOR = CreateColor(1, 1, 0)
ORANGE_FONT_COLOR = CreateColor(1, 0.5, 0.25)
LIGHTBLUE_FONT_COLOR = CreateColor(0.53, 0.67, 1)
LIGHTGRAY_FONT_COLOR = CreateColor(0.75, 0.75, 0.75)
BLACK_FONT_COLOR = CreateColor(0, 0, 0)
PASSIVE_SPELL_FONT_COLOR = CreateColor(0.77, 0.64, 0)
BLUE_FONT_COLOR = CreateColor(0, 0.749, 0.953)
EPIC_PURPLE_COLOR = CreateColor(0.64, 0.21, 0.93)
NORMAL_FONT_COLOR_CODE = "|cffffd200"
HIGHLIGHT_FONT_COLOR_CODE = "|cffffffff"
RED_FONT_COLOR_CODE = "|cffff2020"
GREEN_FONT_COLOR_CODE = "|cff20ff20"
GRAY_FONT_COLOR_CODE = "|cff808080"
YELLOW_FONT_COLOR_CODE = "|cffffff00"
ORANGE_FONT_COLOR_CODE = "|cffff7f3f"
LIGHTYELLOW_FONT_COLOR_CODE = "|cffffff9a"
FONT_COLOR_CODE_CLOSE = "|r"

RAID_CLASS_COLORS = {}
LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE = {}, {}
CLASS_SORT_ORDER = {}
for token, c in pairs(CLASSES) do
	local col = CreateColor(c[5], c[6], c[7], 1)
	col.colorStr = col:GenerateHexColor()
	RAID_CLASS_COLORS[token] = col
	LOCALIZED_CLASS_NAMES_MALE[token] = c[1]
	LOCALIZED_CLASS_NAMES_FEMALE[token] = c[1]
	CLASS_SORT_ORDER[#CLASS_SORT_ORDER + 1] = token
end
table.sort(CLASS_SORT_ORDER)
C_ClassColor = { GetClassColor = function(t) return RAID_CLASS_COLORS[t] end }
CLASS_ICON_TCOORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
	DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 }, PALADIN = { 0, 0.25, 0.5, 0.75 },
	DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 }, MONK = { 0.49609375, 0.7421875, 0.5, 0.75 }, DEMONHUNTER = { 0.7421875, 0.98828125, 0.5, 0.75 },
	EVOKER = { 0, 0.25, 0.75, 1 },
}
ITEM_QUALITY_COLORS = {}
local qc = { { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 }, { 0.9, 0.8, 0.5 }, { 0, 0.8, 1 } }
for i, c in ipairs(qc) do
	local col = CreateColor(c[1], c[2], c[3])
	ITEM_QUALITY_COLORS[i - 1] = { r = c[1], g = c[2], b = c[3], hex = "|c" .. col:GenerateHexColor(), color = col }
end
FACTION_BAR_COLORS = {}
for i = 1, 8 do FACTION_BAR_COLORS[i] = { r = i < 4 and 0.8 or 0, g = i >= 4 and 0.6 or 0.3, b = 0 } end
PowerBarColor = setmetatable({
	MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, FOCUS = { r = 1, g = 0.5, b = 0.25 },
	ENERGY = { r = 1, g = 1, b = 0 }, RUNIC_POWER = { r = 0, g = 0.82, b = 1 },
}, { __index = function(t, k) return rawget(t, "MANA") end })
PowerBarColor[0], PowerBarColor[1], PowerBarColor[2], PowerBarColor[3] = PowerBarColor.MANA, PowerBarColor.RAGE, PowerBarColor.FOCUS, PowerBarColor.ENERGY

WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 2, 5
WOW_PROJECT_WRATH_CLASSIC, WOW_PROJECT_CATACLYSM_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 11, 14, 19
WOW_PROJECT_ID = WOW_PROJECT_MAINLINE
LE_EXPANSION_LEVEL_CURRENT = 0
MAX_PLAYER_LEVEL = 60
MAX_PARTY_MEMBERS, MAX_RAID_MEMBERS, NUM_BAG_SLOTS, NUM_BAG_FRAMES = 4, 40, 4, 4
BACKPACK_CONTAINER, BANK_CONTAINER = 0, -1
BOOKTYPE_SPELL, BOOKTYPE_PET = "spell", "pet"
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NAMEPLATE_FONT = "Fonts\\FRIZQT__.TTF"
CHAT_FONT_HEIGHTS = { 12, 14, 16, 18 }
OKAY, CANCEL, ACCEPT, DECLINE, YES, NO, CLOSE, DONE = "Okay", "Cancel", "Accept", "Decline", "Yes", "No", "Close", "Done"
DEFAULTS, RESET, ENABLE, DISABLE, NONE, UNKNOWN, OPTIONS, SETTINGS = "Defaults", "Reset", "Enable", "Disable", "None", "Unknown", "Options", "Settings"
ADDON_LOADED_TEXT = "AddOn Loaded"
SECONDS, MINUTES, HOURS, DAYS = "Seconds", "Minutes", "Hours", "Days"
TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0.09, g = 0.09, b = 0.19 }
UISpecialFrames = {}
UIPanelWindows = {}
function SIM.closeSpecialFrames()
	for _, name in ipairs(UISpecialFrames) do
		local f = _G[name]
		if f and f.IsShown and f:IsShown() then f:Hide() end
	end
end
function ShowUIPanel(f) if f then f:Show() end end
function HideUIPanel(f) if f then f:Hide() end end
function ToggleFrame(f) if f then f:SetShown(not f:IsShown()) end end
function CloseAllWindows() SIM.closeSpecialFrames() end

------------------------------------------------------------------------
-- Number / text formatting helpers
------------------------------------------------------------------------
function BreakUpLargeNumbers(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end
FormatLargeNumber = BreakUpLargeNumbers
function AbbreviateNumbers(n)
	n = tonumber(n) or 0
	local a = math.abs(n)
	if a >= 1e9 then return sformat("%.1fB", n / 1e9):gsub("%.0B", "B") end
	if a >= 1e6 then return sformat("%.1fM", n / 1e6):gsub("%.0M", "M") end
	if a >= 1e4 then return sformat("%dK", floor(n / 1e3)) end
	if a >= 1e3 then return sformat("%.1fK", n / 1e3):gsub("%.0K", "K") end
	return tostring(floor(n))
end
AbbreviateLargeNumbers = AbbreviateNumbers
function FormatPercentage(p, round) return sformat(round and "%d%%" or "%.1f%%", (p or 0) * 100) end
function SecondsToTime(s, noSeconds, notAbbreviated, maxCount)
	s = floor(s or 0)
	local d, h, m = floor(s / 86400), floor(s % 86400 / 3600), floor(s % 3600 / 60)
	local sec = s % 60
	local parts = {}
	if d > 0 then parts[#parts + 1] = d .. " Day" .. (d > 1 and "s" or "") end
	if h > 0 then parts[#parts + 1] = h .. " Hr" end
	if m > 0 then parts[#parts + 1] = m .. " Min" end
	if (sec > 0 or #parts == 0) and not noSeconds then parts[#parts + 1] = sec .. " Sec" end
	if maxCount then while #parts > maxCount do table.remove(parts) end end
	return table.concat(parts, " ")
end
function SecondsToClock(s, displayZero)
	s = floor(s or 0)
	local h, m, sec = floor(s / 3600), floor(s % 3600 / 60), s % 60
	if h > 0 then return sformat("%d:%02d:%02d", h, m, sec) end
	return sformat("%d:%02d", m, sec)
end
function GetCoinText(copper)
	copper = floor(copper or 0)
	local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. " Gold" end
	if s > 0 then out[#out + 1] = s .. " Silver" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. " Copper" end
	return table.concat(out, ", ")
end
function GetCoinTextureString(copper)
	copper = floor(copper or 0)
	local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = BreakUpLargeNumbers(g) .. "|cffffd700g|r" end
	if s > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "|cffeda55fc|r" end
	return table.concat(out, " ")
end
GetMoneyString = GetCoinTextureString
C_CurrencyInfo = C_CurrencyInfo or {}
function C_CurrencyInfo.GetCoinTextureString(c) return GetCoinTextureString(c) end
function CreateTextureMarkup(file, fw, fh, w, h, l, r, t, b) return "|T" .. tostring(file) .. ":" .. (h or 0) .. ":" .. (w or 0) .. "|t" end
function CreateAtlasMarkup(atlas, w, h) return "|A:" .. tostring(atlas) .. ":" .. (h or 0) .. ":" .. (w or 0) .. "|a" end
function GetTextureInfo() return nil end

------------------------------------------------------------------------
-- Frame enumeration, pools, events helpers
------------------------------------------------------------------------
function EnumerateFrames(f)
	local list = SIM.frames
	if not f then
		for _, x in ipairs(list) do if not S[x].isRoot then return x end end
		return nil
	end
	local found = false
	for _, x in ipairs(list) do
		if found and not S[x].isRoot then return x end
		if x == f then found = true end
	end
end
function GetFramesRegisteredForEvent(event)
	local l = SIM.eventFrames[event]
	if l then return unpack(l) end
end
function GetClickFrame(name) return _G[name] end

local Pool = {}
Pool.__index = Pool
function Pool:Acquire()
	local o = table.remove(self.inactive)
	local isNew = false
	if not o then o = self.create(self) isNew = true end
	self.active[o] = true
	if self.reset and isNew and self.resetNew then self.reset(self, o, true) end
	return o, isNew
end
function Pool:Release(o)
	if not self.active[o] then return false end
	self.active[o] = nil
	if self.reset then self.reset(self, o, false) end
	self.inactive[#self.inactive + 1] = o
	return true
end
function Pool:ReleaseAll() for o in pairs(self.active) do self:Release(o) end end
function Pool:EnumerateActive() return pairs(self.active) end
function Pool:GetNumActive() local n = 0 for _ in pairs(self.active) do n = n + 1 end return n end
function Pool:IsActive(o) return self.active[o] or false end
function Pool:GetNextActive(cur) return (next(self.active, cur)) end
function Pool:EnumerateInactive() return ipairs(self.inactive) end
function CreateObjectPool(create, reset)
	return setmetatable({ create = create, reset = reset, active = {}, inactive = {} }, Pool)
end
local function hideReset(_, o) o:Hide() if o.ClearAllPoints then o:ClearAllPoints() end end
function CreateFramePool(ftype, parent, template, reset, forbidden, init)
	return setmetatable({ create = function() local f = CreateFrame(ftype, nil, parent, template) if init then init(f) end return f end,
		reset = reset or hideReset, active = {}, inactive = {} }, Pool)
end
function CreateTexturePool(parent, layer, sub, template, reset)
	return setmetatable({ create = function() return parent:CreateTexture(nil, layer, template, sub) end,
		reset = reset or hideReset, active = {}, inactive = {} }, Pool)
end
function CreateFontStringPool(parent, layer, sub, template, reset)
	return setmetatable({ create = function() return parent:CreateFontString(nil, layer, template) end,
		reset = reset or hideReset, active = {}, inactive = {} }, Pool)
end
function CreateUnsecuredObjectPool(create, reset) return CreateObjectPool(create, reset) end
function CreateFramePoolCollection()
	local c = { pools = {} }
	function c:CreatePool(ftype, parent, template, reset)
		local p = CreateFramePool(ftype, parent, template, reset)
		self.pools[#self.pools + 1] = p
		return p
	end
	function c:ReleaseAll() for _, p in ipairs(self.pools) do p:ReleaseAll() end end
	return c
end

-- Callback registry (subset)
CallbackRegistryMixin = {}
function CallbackRegistryMixin:OnLoad() self.callbackTables = {} end
function CallbackRegistryMixin:SetUndefinedEventsAllowed() end
function CallbackRegistryMixin:GenerateCallbackEvents(events) self.Event = self.Event or {} for _, e in ipairs(events) do self.Event[e] = e end end
function CallbackRegistryMixin:RegisterCallback(event, fn, owner, ...)
	self.callbackTables = self.callbackTables or {}
	self.callbackTables[event] = self.callbackTables[event] or {}
	local extra = { ... }
	self.callbackTables[event][owner or fn] = function(...) if owner then return fn(owner, unpack(extra), ...) end return fn(...) end
	return owner or fn
end
function CallbackRegistryMixin:RegisterCallbackWithHandle(event, fn, owner, ...)
	local key = self:RegisterCallback(event, fn, owner, ...)
	local reg = self
	return { Unregister = function() reg:UnregisterCallback(event, key) end }
end
function CallbackRegistryMixin:UnregisterCallback(event, owner)
	if self.callbackTables and self.callbackTables[event] then self.callbackTables[event][owner] = nil end
end
function CallbackRegistryMixin:TriggerEvent(event, ...)
	local t = self.callbackTables and self.callbackTables[event]
	if not t then return end
	local copy = {}
	for k, f in pairs(t) do copy[#copy + 1] = f end
	for _, f in ipairs(copy) do SIM.pcall(f, ...) end
end
EventRegistry = CreateFromMixins(CallbackRegistryMixin)
EventRegistry:OnLoad()
function EventRegistry:RegisterFrameEventAndCallback(event, fn, owner, ...)
	SIM.registryFrameEvents = SIM.registryFrameEvents or {}
	SIM.registryFrameEvents[event] = true
	return self:RegisterCallback(event, fn, owner, ...)
end
function EventRegistry:UnregisterFrameEventAndCallback(event, owner) self:UnregisterCallback(event, owner) end
SIM.eventCallbacks = function(event, ...)
	if SIM.registryFrameEvents and SIM.registryFrameEvents[event] then EventRegistry:TriggerEvent(event, ...) end
end
EventUtil = {}
function EventUtil.ContinueOnAddOnLoaded(addon, fn)
	if C_AddOns.IsAddOnLoaded(addon) then fn() return end
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function(self, _, name) if name == addon then self:UnregisterAllEvents() fn() end end)
end
function EventUtil.RegisterOnceFrameEventAndCallback(event, fn)
	local f = CreateFrame("Frame")
	f:RegisterEvent(event)
	f:SetScript("OnEvent", function(self, ...) self:UnregisterAllEvents() fn(select(2, ...)) end)
end
function EventUtil.ContinueAfterAllEvents(fn, ...) fn() end
function EventUtil.ContinueOnPlayerLogin(fn) if SIM.loggedIn then fn() else EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", fn) end end
C_FunctionContainers = { CreateCallback = function(fn) return setmetatable({ Invoke = function(_, ...) return fn(...) end, Cancel = function() end }, { __call = function(_, ...) return fn(...) end }) end }
function GenerateClosure(fn, ...)
	local a = { ... }
	local n = select("#", ...)
	return function(...)
		local b = { unpack(a, 1, n) }
		for i = 1, select("#", ...) do b[n + i] = select(i, ...) end
		return fn(unpack(b, 1, n + select("#", ...)))
	end
end
function GenerateFlatClosure(fn, ...) return GenerateClosure(fn, ...) end
function RunNextFrame(fn) C_Timer.After(0, fn) end

------------------------------------------------------------------------
-- Map / quests / misc stubs that need sensible values
------------------------------------------------------------------------
C_Map = C_Map or {}
function C_Map.GetBestMapForUnit(u) return 1429 end
function C_Map.GetPlayerMapPosition(map, u)
	return { x = 0.42, y = 0.65, GetXY = function(self) return self.x, self.y end }
end
function C_Map.GetMapInfo(id) return { mapID = id, name = P.zone, mapType = 3, parentMapID = 1415 } end
function C_Map.GetMapWorldSize() return 3470, 2314 end
CreateVector2D = function(x, y)
	return { x = x, y = y, GetXY = function(self) return self.x, self.y end, SetXY = function(self, a, b) self.x, self.y = a, b end }
end
C_QuestLog = C_QuestLog or {}
function C_QuestLog.GetNumQuestLogEntries() return 0, 0 end
function C_QuestLog.GetNumQuestWatches() return 0 end
function C_QuestLog.GetInfo() return nil end
function C_QuestLog.GetTitleForQuestID() return nil end
function C_QuestLog.GetQuestsOnMap() return {} end
function C_QuestLog.GetMaxNumQuestsCanWatch() return 25 end
function GetNumQuestLogEntries() return 0, 0 end
function GetQuestLogTitle() return nil end
function GetNumQuestWatches() return 0 end
C_UnitAuras = C_UnitAuras or {}
function C_UnitAuras.GetAuraDataByIndex() return nil end
function C_UnitAuras.GetBuffDataByIndex() return nil end
function C_UnitAuras.GetDebuffDataByIndex() return nil end
function C_UnitAuras.GetAuraDataBySpellName() return nil end
function C_UnitAuras.GetPlayerAuraBySpellID() return nil end
function C_UnitAuras.GetAuraDataByAuraInstanceID() return nil end
C_NamePlate = C_NamePlate or {}
function C_NamePlate.GetNamePlates() return {} end
function C_NamePlate.GetNamePlateForUnit() return nil end
C_FriendList = C_FriendList or {}
function C_FriendList.IsFriend() return false end
function C_FriendList.GetNumFriends() return 0 end
C_Reputation = C_Reputation or {}
function C_Reputation.GetWatchedFactionData() return nil end
C_PvP = C_PvP or {}
function C_PvP.IsPVPMap() return false end
function C_PvP.IsWarModeDesired() return false end
C_DateAndTime = C_DateAndTime or {}
function C_DateAndTime.GetCurrentCalendarTime()
	local d = date("*t")
	return { year = d.year, month = d.month, monthDay = d.day, weekday = d.wday, hour = d.hour, minute = d.min }
end
function C_DateAndTime.GetServerTimeLocal() return time() end
C_CVar = C_CVar or {}
C_CVar.GetCVar, C_CVar.SetCVar, C_CVar.GetCVarBool, C_CVar.RegisterCVar, C_CVar.GetCVarDefault = GetCVar, SetCVar, GetCVarBool, RegisterCVar, GetCVarDefault
C_Texture = C_Texture or {}
function C_Texture.GetAtlasInfo(a) return { width = 32, height = 32, file = a, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end
function SIM.atlasSize(a) return 32, 32 end
C_Seasons = C_Seasons or {}
function C_Seasons.HasActiveSeason() return false end
function C_Seasons.GetActiveSeason() return 0 end
C_GameRules = C_GameRules or {}
function C_GameRules.IsHardcoreActive() return false end
C_EncodingUtil = C_EncodingUtil or {}

Enum = Enum or {}
PLAYER_FACTION_COLOR_HORDE = CreateColor(0.9, 0.05, 0.07)
PLAYER_FACTION_COLOR_ALLIANCE = CreateColor(0.29, 0.33, 0.91)

-- A few of the client's GlobalStrings that addons use most (the full table
-- is generated by the client and not in the UI source mirror).
local GS = {
	ITEM_LEVEL = "Item Level %d", LEVEL = "Level", NAME = "Name", ITEM_QUALITY0_DESC = "Poor", ITEM_QUALITY1_DESC = "Common",
	ITEM_QUALITY2_DESC = "Uncommon", ITEM_QUALITY3_DESC = "Rare", ITEM_QUALITY4_DESC = "Epic", ITEM_QUALITY5_DESC = "Legendary",
	ITEM_QUALITY6_DESC = "Artifact", ITEM_QUALITY7_DESC = "Heirloom", ITEM_SOULBOUND = "Soulbound", ITEM_BIND_ON_EQUIP = "Binds when equipped",
	ITEM_BIND_ON_PICKUP = "Binds when picked up", ITEM_UNIQUE = "Unique", ITEM_SPELL_TRIGGER_ONUSE = "Use:", ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:",
	SPELL_PASSIVE = "Passive", COMBAT = "Combat", GENERAL = "General", GUILD = "Guild", PARTY = "Party", RAID = "Raid", SAY = "Say",
	YELL = "Yell", WHISPER = "Whisper", EMOTE = "Emote", CHANNEL = "Channel", TRADE = "Trade", LOOT = "Loot", BAGSLOT = "Bag",
	BACKPACK_TOOLTIP = "Backpack", BANK = "Bank", MONEY = "Money", GOLD_AMOUNT = "%d Gold", SILVER_AMOUNT = "%d Silver",
	COPPER_AMOUNT = "%d Copper", GOLD_AMOUNT_TEXTURE = "%d|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t",
	SILVER_AMOUNT_TEXTURE = "%d|TInterface\MoneyFrame\UI-SilverIcon:0:0:2:0|t", COPPER_AMOUNT_TEXTURE = "%d|TInterface\MoneyFrame\UI-CopperIcon:0:0:2:0|t",
	SPELL_FAILED_NOT_READY = "Not yet recovered", ERR_NOT_IN_COMBAT = "You can't do that while in combat",
	ERR_OUT_OF_RANGE = "Out of range.", TOOLTIP_UNIT_LEVEL = "Level %s", TOOLTIP_UNIT_LEVEL_TYPE = "Level %s (%s)",
	UNIT_LEVEL_TEMPLATE = "Level %d", FRIENDS = "Friends", IGNORE = "Ignore", QUESTS_LABEL = "Quests", QUEST_LOG = "Quest Log",
	COMPLETE = "Complete", FAILED = "Failed", TRACK_QUEST = "Track Quest", ABANDON_QUEST = "Abandon Quest", SHARE_QUEST = "Share Quest",
	KEY_BINDINGS = "Key Bindings", INTERFACE_OPTIONS = "Interface Options", ADDONS = "AddOns", SOUND = "Sound", VIDEO = "Video",
	SPELLBOOK = "Spellbook", TALENTS = "Talents", MINIMAP_LABEL = "Minimap", WORLD_MAP = "World Map", ALL = "All", FILTER = "Filter",
	SEARCH = "Search", RESET_TO_DEFAULT = "Reset to Default", APPLY = "Apply", SAVE = "Save", DELETE = "Delete", REMOVE = "Remove",
	ADD = "Add", EDIT = "Edit", NEW = "New", BACK = "Back", NEXT = "Next", PREV = "Prev", CONTINUE = "Continue", HELP_LABEL = "Help",
	TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage", ROLE = "Role", CLASS = "Class", RACE = "Race", ZONE = "Zone", TIME_LABEL = "Time:",
	DAMAGE = "Damage", HEALTH = "Health", MANA = "Mana", RAGE = "Rage", ENERGY = "Energy", FOCUS = "Focus", ARMOR = "Armor",
	LOCKED = "Locked", UNLOCK = "Unlock", LOCK = "Lock", SHOW = "Show", HIDE = "Hide", NOT_APPLICABLE = "N/A", UNKNOWNOBJECT = "Unknown",
	PLAYER = "Player", TARGET = "Target", PET = "Pet", FOCUS_LABEL = "Focus", EXPANSION_NAME0 = "Classic", SPELL_RECAST_TIME_MIN = "%.3g min cooldown",
	SPELL_RECAST_TIME_SEC = "%.3g sec cooldown", MINUTES_ABBR = "%d min", SECONDS_ABBR = "%d sec", HOURS_ABBR = "%d hr", DAYS_ABBR = "%d day",
	TOOLTIP_TALENT_LEARN = "Click to learn", AUCTION_HOUSE = "Auction House", VENDOR = "Vendor", REPAIR_ALL_ITEMS = "Repair All Items",
	ITEM_CLASSES_ALLOWED = "Classes: %s", ITEM_MIN_LEVEL = "Requires Level %d", DURABILITY_TEMPLATE = "Durability %d / %d",
	ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online.", ERR_FRIEND_OFFLINE_S = "%s has gone offline.",
	LFG_TYPE_DUNGEON = "Dungeon", INSTANCE = "Instance", DUNGEONS = "Dungeons", RAIDS = "Raids", EXPERIENCE_COLON = "Experience:",
	XP = "XP", REPUTATION = "Reputation", HONOR = "Honor", CURRENCY = "Currency", MAIL_LABEL = "Mail", INBOX = "Inbox",
}
for k, v in pairs(GS) do if rawget(_G, k) == nil then _G[k] = v end end
