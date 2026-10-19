-- WowSim: stand-ins for the default Blizzard UI frames addons poke at
-- (Minimap, PlayerFrame, WorldMapFrame, ...) plus common FrameXML helpers.
-- Stand-ins are "permissive": unknown methods are no-ops and unknown child
-- keys become further stand-in frames, so addons that hook them keep going.

local SIM = __SIM
local S = SIM.S
local type, pairs, ipairs, select = type, pairs, ipairs, select

local VERB = { "Get", "Set", "Is", "Has", "Enable", "Disable", "Update", "Show", "Hide", "Refresh", "Clear", "Add",
	"Remove", "On", "Can", "Should", "Toggle", "Register", "Unregister", "Acquire", "Release", "Reset", "Init",
	"Open", "Close", "Apply", "Create", "Find", "Play", "Stop", "Select", "Load", "Save", "Navigate", "Zoom",
	"Pan", "Request", "Evaluate", "Layout", "Mark", "Process", "Begin", "End", "Start", "Lock", "Unlock",
	"Hook", "Notify", "Trigger", "Cancel", "Enumerate", "Pin", "Expand", "Collapse", "Scroll", "Move" }
local function verbish(k)
	for _, v in ipairs(VERB) do if k:sub(1, #v) == v then return true end end
	return false
end

local permMeta = {}
local stubFns = {}
local function permissive(class)
	if permMeta[class] then return permMeta[class] end
	local m = SIM.Methods[class]
	local meta = {
		__index = function(t, k)
			local v = m[k]
			if v ~= nil then return v end
			if type(k) ~= "string" or not k:match("^%u") then return nil end
			if verbish(k) then
				local f = stubFns[k]
				if not f then
					f = function() SIM.noteStub("BlizzardUI:" .. k) end
					stubFns[k] = f
				end
				return f
			end
			local child = SIM.blizz(nil, "Frame", t)
			rawset(t, k, child)
			return child
		end,
		__tostring = SIM.Meta[class].__tostring,
	}
	permMeta[class] = meta
	return meta
end

function SIM.blizz(name, ftype, parent, setup)
	local f = CreateFrame(ftype or "Frame", name, parent or UIParent)
	setmetatable(f, permissive(S[f].class))
	S[f].blizzard = true
	if setup then setup(f, S[f]) end
	return f
end
local B = SIM.blizz

local function hidden(name, ftype, parent)
	local f = B(name, ftype, parent)
	f:Hide()
	return f
end

local function label(f, text)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fs:SetPoint("CENTER")
	fs:SetText(text)
	fs:SetAlpha(0.8)
	return fs
end

-- Visible placeholders for the default UI, so addon frames can be judged in context.
SIM.blizzardPlaceholders = {}
local function placeholder(f, text)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropColor(0, 0, 0, 0.25)
	f:SetBackdropBorderColor(1, 1, 1, 0.12)
	label(f, text)
	f:SetFrameStrata("BACKGROUND")
	table.insert(SIM.blizzardPlaceholders, f)
	return f
end

MinimapCluster = B("MinimapCluster")
MinimapCluster:SetSize(192, 192)
MinimapCluster:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
Minimap = B("Minimap", "Frame", MinimapCluster)
Minimap:SetSize(140, 140)
Minimap:SetPoint("CENTER", MinimapCluster, "TOP", 9, -92)
do
	S[Minimap].skin = "minimap"
	label(Minimap, "Minimap")
	Minimap:SetFrameStrata("LOW")
	table.insert(SIM.blizzardPlaceholders, MinimapCluster)
	local zoom = 0
	Minimap.GetZoom = function() return zoom end
	Minimap.SetZoom = function(_, z) zoom = z end
	Minimap.GetZoomLevels = function() return 6 end
	Minimap.SetMaskTexture = function() end
	Minimap.SetBlipTexture = function() end
	Minimap.SetPlayerTexture = function() end
	Minimap.GetPingPosition = function() return 0, 0 end
	Minimap.PingLocation = function() end
	Minimap.UpdateBlips = function() end
	Minimap.SetArchBlobRingScalar = function() end
	Minimap.SetQuestBlobRingScalar = function() end
	Minimap.SetTaskBlobRingScalar = function() end
end
MinimapBackdrop = B("MinimapBackdrop", "Frame", MinimapCluster)
MinimapBackdrop:SetAllPoints(Minimap)
MinimapZoneText = MinimapCluster:CreateFontString("MinimapZoneText", "OVERLAY", "GameFontNormalSmall")
MinimapZoneText:SetPoint("TOP", MinimapCluster, "TOP", 9, -4)
MinimapZoneText:SetText(SIM.profile.subZone ~= "" and SIM.profile.subZone or SIM.profile.zone)
MinimapZoneTextButton = B("MinimapZoneTextButton", "Button", MinimapCluster)
MinimapZoomIn = B("MinimapZoomIn", "Button", Minimap)
MinimapZoomOut = B("MinimapZoomOut", "Button", Minimap)
MiniMapTracking = B("MiniMapTracking", "Frame", MinimapCluster)
MiniMapMailFrame = hidden("MiniMapMailFrame", "Frame", MinimapCluster)
GameTimeFrame = B("GameTimeFrame", "Button", MinimapCluster)
TimeManagerClockButton = B("TimeManagerClockButton", "Button", MinimapCluster)
QueueStatusButton = hidden("QueueStatusButton", "Button")
MinimapCompassTexture = Minimap:CreateTexture("MinimapCompassTexture", "OVERLAY")
ExpansionLandingPageMinimapButton = hidden("ExpansionLandingPageMinimapButton", "Button", Minimap)
GarrisonLandingPageMinimapButton = hidden("GarrisonLandingPageMinimapButton", "Button", Minimap)
MiniMapWorldMapButton = B("MiniMapWorldMapButton", "Button", MinimapCluster)
function GetMinimapShape() return "ROUND" end

PlayerFrame = placeholder(B("PlayerFrame", "Button"), "PlayerFrame")
PlayerFrame:SetSize(232, 100)
PlayerFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4)
TargetFrame = placeholder(B("TargetFrame", "Button"), "TargetFrame")
TargetFrame:SetSize(232, 100)
TargetFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 250, -4)
TargetFrame:Hide()
TargetFrameToT = hidden("TargetFrameToT", "Button", TargetFrame)
FocusFrame = hidden("FocusFrame", "Button")
PetFrame = hidden("PetFrame", "Button")
PartyFrame = B("PartyFrame")
for i = 1, 4 do
	local pf = B("PartyMemberFrame" .. i, "Button", PartyFrame)
	pf:Hide()
	PartyFrame["MemberFrame" .. i] = pf
end
CompactRaidFrameManager = hidden("CompactRaidFrameManager")
CompactRaidFrameContainer = hidden("CompactRaidFrameContainer")
PlayerCastingBarFrame = hidden("PlayerCastingBarFrame", "StatusBar")
CastingBarFrame = PlayerCastingBarFrame
TargetFrameSpellBar = hidden("TargetFrameSpellBar", "StatusBar", TargetFrame)

MainMenuBar = placeholder(B("MainMenuBar"), "Action bar")
MainMenuBar:SetSize(510, 44)
MainMenuBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 6)
MainActionBar = MainMenuBar
MainMenuBarArtFrame = B("MainMenuBarArtFrame", "Frame", MainMenuBar)
MicroButtonAndBagsBar = B("MicroButtonAndBagsBar")
MicroButtonAndBagsBar:SetSize(298, 88)
MicroButtonAndBagsBar:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
StatusTrackingBarManager = B("StatusTrackingBarManager")
for i = 1, 12 do
	local b = B("ActionButton" .. i, "CheckButton", MainMenuBar)
	b:SetSize(36, 36)
	b:SetPoint("LEFT", MainMenuBar, "LEFT", 6 + (i - 1) * 42, 0)
	S[b].skin = "slot"
	b.icon = b:CreateTexture("ActionButton" .. i .. "Icon", "BACKGROUND")
	b.icon:SetAllPoints()
	b.cooldown = CreateFrame("Cooldown", "ActionButton" .. i .. "Cooldown", b)
	b.cooldown:SetAllPoints()
	b.HotKey = b:CreateFontString("ActionButton" .. i .. "HotKey", "OVERLAY", "NumberFontNormalSmallGray")
	b.HotKey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -3)
	b.HotKey:SetText(i == 10 and "0" or (i == 11 and "-" or (i == 12 and "=" or tostring(i))))
	b.action = i
end
for _, bar in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }) do
	local f = hidden(bar)
	for i = 1, 12 do B(bar .. "Button" .. i, "CheckButton", f) end
end
StanceBar = hidden("StanceBar")
PetActionBar = hidden("PetActionBar")
PossessActionBar = hidden("PossessActionBar")
ExtraActionBarFrame = hidden("ExtraActionBarFrame")

BuffFrame = B("BuffFrame")
BuffFrame:SetSize(300, 40)
BuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -13)
DebuffFrame = B("DebuffFrame")
ObjectiveTrackerFrame = B("ObjectiveTrackerFrame")
ObjectiveTrackerFrame:SetSize(235, 500)
ObjectiveTrackerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -85, -260)
QuestWatchFrame = ObjectiveTrackerFrame

UIErrorsFrame = CreateFrame("MessageFrame", "UIErrorsFrame", UIParent)
UIErrorsFrame:SetSize(512, 60)
UIErrorsFrame:SetPoint("TOP", UIParent, "TOP", 0, -122)
UIErrorsFrame:SetFontObject(ErrorFont)
UIErrorsFrame:SetJustifyH("CENTER")
UIErrorsFrame:SetFrameStrata("DIALOG")
UIErrorsFrame:SetTimeVisible(2)
UIErrorsFrame:SetInsertMode("TOP")
RaidWarningFrame = CreateFrame("MessageFrame", "RaidWarningFrame", UIParent)
RaidWarningFrame:SetSize(800, 70)
RaidWarningFrame:SetPoint("TOP", UIParent, "TOP", 0, -260)
RaidWarningFrame:SetFontObject(GameFontNormalHuge)
RaidWarningFrame:SetJustifyH("CENTER")
RaidWarningFrame:SetTimeVisible(4)
RaidBossEmoteFrame = RaidWarningFrame
ZoneTextFrame = hidden("ZoneTextFrame")
SubZoneTextFrame = hidden("SubZoneTextFrame")
ActionStatus = hidden("ActionStatus")

for _, n in ipairs({ "WorldMapFrame", "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "PlayerTalentFrame", "TalentFrame",
	"GameMenuFrame", "FriendsFrame", "QuestLogFrame", "QuestFrame", "GossipFrame", "MerchantFrame", "MailFrame", "BankFrame",
	"LootFrame", "TradeFrame", "CollectionsJournal", "PVEFrame", "LFGListFrame", "KeyBindingFrame", "MacroFrame",
	"InspectFrame", "ClassTrainerFrame", "TaxiFrame", "FlightMapFrame", "AuctionHouseFrame", "AuctionFrame",
	"ProfessionsFrame", "TradeSkillFrame", "GuildFrame", "CommunitiesFrame", "EncounterJournal", "AchievementFrame",
	"BattlefieldMapFrame", "PetStableFrame", "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame",
	"ReadyCheckFrame", "LFGDungeonReadyPopup", "ColorPickerFrame", "OpacitySliderFrame", "HelpFrame", "ScriptErrorsFrame",
	"EventTraceFrame", "ChatConfigFrame", "ReputationFrame", "TokenFrame", "SkillFrame", "HonorFrame", "PaperDollFrame",
	"CharacterModelScene", "DressUpFrame", "WardrobeFrame", "QuestMapFrame", "ContainerFrameCombinedBags", "EditModeManagerFrame",
	"CinematicFrame", "MovieFrame", "StoreFrame", "BagsBar", "TutorialFrame", "SplashFrame", "QuickJoinToastButton",
	"ChatFrameMenuButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "GeneralDockManager",
	"FriendsMicroButton", "ChatAlertFrame", "AlertFrame", "TalkingHeadFrame", "BossBanner", "LevelUpDisplay",
	"NamePlateDriverFrame", "UIWidgetTopCenterContainerFrame", "UIWidgetBelowMinimapContainerFrame", "DurabilityFrame",
	"VehicleSeatIndicator", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "AddonCompartmentFrame",
	"ProfessionsBookFrame", "SpellFlyout", "PetBattleFrame", "OverrideActionBar", "ArenaEnemyFramesContainer",
	"GameMenuButtonContinue", "LFDQueueFrame", "RaidFrame", "WorldStateScoreFrame", "SettingsPanelContainer" }) do
	if not _G[n] then hidden(n) end
end
for i = 1, 13 do hidden("ContainerFrame" .. i) end
ChatFrameChannelButton = B("ChatFrameChannelButton", "Button")
ChatFrameChannelButton:Hide()
AddonList = hidden("AddonList")
AddonList.ForceLoad = CreateFrame("CheckButton", "AddonListForceLoad", AddonList)
AddonListForceLoad = AddonList.ForceLoad
GameTooltipStatusBar = CreateFrame("StatusBar", "GameTooltipStatusBar", GameTooltip)
GameTooltipStatusBar:Hide()
WorldMapFrame.ScrollContainer = B(nil, "ScrollFrame", WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = B(nil, "Frame", WorldMapFrame.ScrollContainer)
WorldMapFrame.ScrollContainer.Child:SetSize(1002, 668)
WorldMapFrame.GetMapID = function() return 1429 end
WorldMapFrame.GetCanvas = function() return WorldMapFrame.ScrollContainer.Child end
WorldMapFrame.GetCanvasContainer = function() return WorldMapFrame.ScrollContainer end
WorldMapFrame.EnumeratePinsByTemplate = function() return function() end end
WorldMapFrame.AddDataProvider = function() end
WorldMapFrame.RemoveDataProvider = function() end
WorldMapFrame.AcquirePin = function() return B(nil, "Frame", WorldMapFrame.ScrollContainer.Child) end
WorldMapFrame.pinPools = {}
WorldMapFrame.dataProviders = {}
WorldMapFrame:SetSize(1002, 668)
WorldMapFrame.ScrollContainer:SetAllPoints()
WorldMapFrame.ScrollContainer.Child:SetPoint("TOPLEFT")
ColorPickerFrame.SetupColorPickerAndShow = function(self, info)
	SIM.chat("[Sim] Color picker requested (not simulated) - keeping current color", 1, 0.6, 0.2)
end
ColorPickerFrame.GetColorRGB = function() return 1, 1, 1 end
ColorPickerFrame.GetColorAlpha = function() return 1 end
EditModeManagerFrame.IsEditModeActive = function() return false end
EditModeManagerFrame.RegisterSystemFrame = function() end
EditModeManagerFrame.UseRaidStylePartyFrames = function() return false end

-- Keep the placeholders in step with the fake game state.
local lastTarget
SIM.blizzardTick = function()
	local exists = SIM.profile.target and SIM.profile.target.exists
	if exists ~= lastTarget then
		lastTarget = exists
		TargetFrame:SetShown(exists and true or false)
	end
end
local oldAfter = SIM.afterTick
SIM.afterTick = function(dt)
	if oldAfter then oldAfter(dt) end
	SIM.blizzardTick()
end
function SIM.setBlizzardVisible(flag)
	for _, f in ipairs(SIM.blizzardPlaceholders) do
		if f == TargetFrame then f:SetShown(flag and SIM.profile.target.exists) else f:SetShown(flag) end
	end
	MainMenuBar:SetShown(flag)
end

------------------------------------------------------------------------
-- FrameXML helpers addons commonly call
------------------------------------------------------------------------
local fading = {}
local function fadeTick(dt)
	for f, info in pairs(fading) do
		info.t = info.t + dt
		local p = info.timeToFade > 0 and math.min(1, info.t / info.timeToFade) or 1
		f:SetAlpha(info.startAlpha + (info.endAlpha - info.startAlpha) * p)
		if p >= 1 then
			fading[f] = nil
			if info.finishedFunc then SIM.pcall(info.finishedFunc, info.finishedArg1, info.finishedArg2, info.finishedArg3, info.finishedArg4) end
		end
	end
end
local oldAfter2 = SIM.afterTick
SIM.afterTick = function(dt) oldAfter2(dt) fadeTick(dt) end
function UIFrameFade(f, info)
	if not f then return end
	info.t = 0
	info.startAlpha = info.startAlpha or f:GetAlpha()
	info.endAlpha = info.endAlpha or 1
	info.timeToFade = info.timeToFade or 0.3
	if info.mode == "IN" then f:Show() end
	f:SetAlpha(info.startAlpha)
	fading[f] = info
end
function UIFrameFadeIn(f, t, a1, a2) UIFrameFade(f, { mode = "IN", timeToFade = t, startAlpha = a1, endAlpha = a2 }) end
function UIFrameFadeOut(f, t, a1, a2) UIFrameFade(f, { mode = "OUT", timeToFade = t, startAlpha = a1, endAlpha = a2 }) end
function UIFrameFadeRemoveFrame(f) fading[f] = nil end
function UIFrameIsFading(f) return fading[f] ~= nil end
function UIFrameFlash(f, fadeIn, fadeOut, duration, showWhenDone) if f then f:Show() end end
function UIFrameFlashStop(f) end
function UIFrameIsFlashing() return false end
function UIParentLoadAddOn(name) return C_AddOns.LoadAddOn(name) end
function LoadAddOnWithErrorHandling(name) return C_AddOns.LoadAddOn(name) end
function GetChannelList() return end
function GetNumDisplayChannels() return 0 end
function EnumerateServerChannels() return end
function GetChatWindowInfo(i) return "General", 14, 0, 0, 0, 1, true, false, 0 end
function GetChatWindowMessages() return end
function GetChatWindowChannels() return end
function ToggleWorldMap() WorldMapFrame:SetShown(not WorldMapFrame:IsShown()) end
function ToggleCharacter() end
function ToggleSpellBook() end
function ToggleGameMenu() end
function ToggleFriendsFrame() end
function ToggleQuestLog() end
function OpenWorldMap() end
function StaticPopup_OnShow() end
function StaticPopup_OnHide() end
function StaticPopup_OnUpdate() end
function StaticPopup_OnClick() end
function StaticPopup_OnKeyDown() end
function StaticPopup_EditBoxOnEnterPressed() end
function StaticPopup_EditBoxOnEscapePressed() end
function StaticPopup_EditBoxOnTextChanged() end
function StaticPopup_Resize() end
function CooldownFrame_Set(cd, start, duration, enable, forceShowDrawEdge, modRate)
	if enable and enable ~= 0 and start and start > 0 and duration and duration > 0 then cd:SetCooldown(start, duration, modRate)
	else cd:Clear() end
end
function CooldownFrame_Clear(cd) cd:Clear() end
function ActionButton_ShowOverlayGlow(b)
	if not b.simGlow then
		local g = b:CreateTexture(nil, "OVERLAY")
		g:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 6)
		g:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -6)
		g:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
		b.simGlow = g
	end
	b.simGlow:Show()
end
function ActionButton_HideOverlayGlow(b) if b.simGlow then b.simGlow:Hide() end end
function ActionButtonSpellAlertManager_ShowAlert(_, b) ActionButton_ShowOverlayGlow(b) end
ActionButtonSpellAlertManager = { ShowAlert = function(_, b) ActionButton_ShowOverlayGlow(b) end, HideAlert = function(_, b) ActionButton_HideOverlayGlow(b) end }
function SetItemButtonTexture(b, tex) local i = b.icon or b.Icon if i then i:SetTexture(tex) end end
function SetItemButtonCount(b, n) if b.Count then b.Count:SetText((n and n > 1) and n or "") end end
function SetItemButtonQuality() end
function SetItemButtonDesaturated(b, d) local i = b.icon or b.Icon if i then i:SetDesaturated(d) end end
function CreateSimpleTextureMarkup(file, w, h) return "|T" .. tostring(file) .. ":" .. (h or w or 0) .. ":" .. (w or 0) .. "|t" end
function PanelTemplates_SetNumTabs(f, n) f.numTabs = n end
function PanelTemplates_SetTab(f, id) f.selectedTab = id PanelTemplates_UpdateTabs(f) end
function PanelTemplates_GetSelectedTab(f) return f.selectedTab end
function PanelTemplates_UpdateTabs(f)
	if not f.numTabs then return end
	local name = f:GetName()
	for i = 1, f.numTabs do
		local tab = (f.Tabs and f.Tabs[i]) or (name and _G[name .. "Tab" .. i])
		if tab then if i == f.selectedTab then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end end
	end
end
function PanelTemplates_SelectTab(tab) S[tab].checked = true if tab.Disable then tab:Disable() end end
function PanelTemplates_DeselectTab(tab) S[tab].checked = false if tab.Enable then tab:Enable() end end
function PanelTemplates_TabResize(tab, padding, absSize) local t = tab.GetFontString and tab:GetFontString() if t then tab:SetWidth(absSize or (t:GetStringWidth() + 30 + (padding or 0))) end end
function PanelTemplates_EnableTab(f, i) end
function PanelTemplates_DisableTab(f, i) end
function PanelTemplates_ResizeTabsToFit() end
local function tabTemplate(o, s)
	s.skin = "tab"
	if not s.w then o:SetSize(100, 32) end
	local fs = o:CreateFontString(s.name and (s.name .. "Text") or nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER", o, "CENTER", 0, 2)
	o.Text = fs
	s.fontString = fs
	s.normalFont, s.highlightFont, s.disabledFont = GameFontNormalSmall, GameFontHighlightSmall, GameFontHighlightSmall
	o.Left, o.Middle, o.Right = o:CreateTexture(), o:CreateTexture(), o:CreateTexture()
end
for _, n in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate", "TabButtonTemplate", "OptionsFrameTabButtonTemplate",
	"PanelTopTabButtonTemplate", "TabSystemButtonTemplate", "MinimalTabTemplate" }) do
	SIM.templates[n] = tabTemplate
end

C_UIFileAsset = C_UIFileAsset or {}
function C_UIFileAsset.IsKnownFile(path)
	if type(path) == "number" then return true end
	return SIM.py.fileExists(tostring(path)) and true or false
end
