-- WowSim: Blizzard templates rebuilt from primitives, plus GameTooltip,
-- StaticPopup, the Settings window and UIDropDownMenu.
-- Frames with a `skin` are drawn by the browser in Blizzard style because we
-- do not have the game's art files.

local SIM = __SIM
local S = SIM.S
local type, pairs, ipairs, tostring, select, unpack = type, pairs, ipairs, tostring, select, unpack
local max, min, floor = math.max, math.min, math.floor

local T = {}
SIM.templates = T

function SIM.applyTemplate(o, list)
	if type(list) ~= "string" then return end
	for name in string.gmatch(list, "[^,%s]+") do
		local fn = T[name]
		if fn then
			fn(o, S[o])
		else
			SIM.noteStub("Template: " .. name)
		end
	end
end

local function child(o, key, obj, suffix)
	o[key] = obj
	local n = S[o].name
	if n and suffix then _G[n .. suffix] = obj end
	return obj
end

local function fstr(o, layer, font, suffix)
	local n = S[o].name
	return o:CreateFontString((n and suffix) and (n .. suffix) or nil, layer or "ARTWORK", font)
end

local function placeholder(o, key, layer)
	-- Art we cannot draw; exists so addons can :Hide() / :SetTexture() it.
	local t = o:CreateTexture(nil, layer or "BACKGROUND")
	o[key] = t
	return t
end

------------------------------------------------------------------------
-- Backdrops
------------------------------------------------------------------------
BACKDROP_TOOLTIP_16_16_5555 = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileEdge = true, tileSize = 16, edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 },
}
BACKDROP_TOOLTIP_12_12_4444 = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileEdge = true, tileSize = 12, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
BACKDROP_TOOLTIP_8_8_1111 = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileEdge = true, tileSize = 8, edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
BACKDROP_TOOLTIP_0_16 = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 }
BACKDROP_DIALOG_32_32 = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileEdge = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
BACKDROP_DARK_DIALOG_32_32 = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileEdge = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
BACKDROP_DIALOG_EDGE_32 = { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tileEdge = true, edgeSize = 32 }
BACKDROP_GOLD_DIALOG_32_32 = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
	tile = true, tileEdge = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
BACKDROP_SLIDER_8_8 = {
	bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
	tile = true, tileEdge = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 },
}
BACKDROP_TEXT_PANEL_0_16 = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tileEdge = true, edgeSize = 16 }
BACKDROP_ACHIEVEMENTS_0_64 = BACKDROP_DIALOG_EDGE_32
BACKDROP_CHARACTER_CREATE_TOOLTIP_32_32 = BACKDROP_TOOLTIP_16_16_5555
BACKDROP_CALLOUT_GLOW_0_16 = BACKDROP_TOOLTIP_16_16_5555

BackdropTemplateMixin = {}
for _, k in ipairs({ "SetBackdrop", "GetBackdrop", "SetBackdropColor", "GetBackdropColor", "SetBackdropBorderColor",
	"GetBackdropBorderColor", "ApplyBackdrop", "ClearBackdrop", "OnBackdropLoaded", "OnBackdropSizeChanged",
	"SetupTextureCoordinates", "HasBackdropInfo" }) do
	BackdropTemplateMixin[k] = function(self, ...) return SIM.Methods.Frame[k](self, ...) end
end

T.BackdropTemplate = function(o) end
local function tooltipBackdrop(o)
	o:SetBackdrop(BACKDROP_TOOLTIP_16_16_5555)
	o:SetBackdropColor(0.09, 0.09, 0.19, 0.9)
	o:SetBackdropBorderColor(1, 1, 1, 1)
end
T.TooltipBackdropTemplate = tooltipBackdrop
T.TooltipBorderedFrameTemplate = tooltipBackdrop
T.TooltipBorderBackdropTemplate = tooltipBackdrop
T.GlowBoxTemplate = tooltipBackdrop
T.TranslucentFrameTemplate = function(o)
	o:SetBackdrop(BACKDROP_DIALOG_32_32)
	o:SetBackdropColor(0, 0, 0, 0.8)
end
T.DialogBorderTemplate = function(o) o:SetBackdrop(BACKDROP_DIALOG_32_32) end
T.DialogBorderDarkTemplate = function(o) o:SetBackdrop(BACKDROP_DARK_DIALOG_32_32) end
T.DialogBorderTranslucentTemplate = T.TranslucentFrameTemplate
T.DialogBorderOpaqueTemplate = T.DialogBorderTemplate
T.ThinBorderTemplate = function(o) o:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }) o:SetBackdropBorderColor(0.4, 0.4, 0.4, 1) end
local function inset(o, s)
	s.skin = "inset"
	placeholder(o, "Bg")
end
T.InsetFrameTemplate = inset
T.InsetFrameTemplate2 = inset
T.InsetFrameTemplate3 = inset
T.InsetFrameTemplate4 = inset
T.NineSlicePanelTemplate = function() end
T.ShadowOverlayTemplate = function() end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
local function panelButton(o, s)
	s.skin = "panelbutton"
	local fs = fstr(o, "OVERLAY", "GameFontNormal", "Text")
	fs:SetPoint("CENTER", o, "CENTER", 0, 0)
	o.Text = fs
	s.fontString = fs
	s.normalFont, s.highlightFont, s.disabledFont = GameFontNormal, GameFontHighlight, GameFontDisable
	placeholder(o, "Left")
	placeholder(o, "Right")
	placeholder(o, "Middle")
	if not s.w then o:SetSize(80, 22) end
end
for _, n in ipairs({ "UIPanelButtonTemplate", "UIPanelButtonNoTooltipTemplate", "UIPanelDynamicResizeButtonTemplate",
	"GameMenuButtonTemplate", "UIMenuButtonStretchTemplate", "UIGoldBorderButtonTemplate", "SharedButtonTemplate",
	"SharedButtonSmallTemplate", "SharedButtonLargeTemplate", "MagicButtonTemplate", "UIPanelButtonGrayTemplate",
	"StaticPopupButtonTemplate", "UIPanelSquareButton", "SharedGoldRedButtonTemplate", "SharedGoldRedButtonSmallTemplate",
	"BigRedThreeSliceButtonTemplate", "UIServiceButtonTemplate", "GameMenuButtonPLNTemplate" }) do
	T[n] = panelButton
end
T.UIPanelButtonTemplate2 = panelButton

local function closeButton(o, s, noScripts)
	s.skin = "close"
	o:SetSize(24, 24)
	if not noScripts then
		o:SetScript("OnClick", function(self)
			local p = self:GetParent()
			if p then p:Hide() end
			PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
		end)
	end
end
T.UIPanelCloseButton = function(o, s) closeButton(o, s) end
T.UIPanelCloseButtonDefaultAnchors = function(o, s) closeButton(o, s) o:SetPoint("TOPRIGHT", o:GetParent(), "TOPRIGHT", 1, 0) end
T.UIPanelCloseButtonNoScripts = function(o, s) closeButton(o, s, true) end
T.SelectionFrameCancelButtonTemplate = T.UIPanelCloseButton
T.UIPanelHideButtonNoScripts = T.UIPanelCloseButtonNoScripts

local function checkButton(size, font, textXOffset)
	return function(o, s)
		s.skin = "check"
		o:SetSize(size, size)
		local fs = fstr(o, "ARTWORK", font, "Text")
		fs:SetPoint("LEFT", o, "RIGHT", textXOffset or -2, 0)
		fs:SetJustifyH("LEFT")
		o.Text, o.text = fs, fs
		s.checkText = fs
	end
end
T.UICheckButtonTemplate = checkButton(32, "GameFontNormalSmall", -2)
T.ChatConfigCheckButtonTemplate = checkButton(24, "GameFontNormalSmall", 0)
T.InterfaceOptionsCheckButtonTemplate = checkButton(26, "GameFontHighlightLeft", 2)
T.InterfaceOptionsSmallCheckButtonTemplate = checkButton(22, "GameFontHighlightSmall", 2)
T.OptionsCheckButtonTemplate = checkButton(26, "GameFontHighlightLeft", 2)
T.OptionsSmallCheckButtonTemplate = checkButton(22, "GameFontHighlightSmall", 2)
T.OptionsBaseCheckButtonTemplate = function(o, s) s.skin = "check" o:SetSize(26, 26) end
T.SettingsCheckBoxTemplate = function(o, s) s.skin = "check" o:SetSize(30, 29) end
T.SettingsCheckboxTemplate = T.SettingsCheckBoxTemplate
T.UICheckButtonArtTemplate = T.OptionsBaseCheckButtonTemplate
T.UIRadioButtonTemplate = function(o, s)
	s.skin = "radio"
	o:SetSize(16, 16)
	local fs = fstr(o, "ARTWORK", "GameFontNormalSmall", "Text")
	fs:SetPoint("LEFT", o, "RIGHT", 5, 0)
	o.text, o.Text = fs, fs
end

------------------------------------------------------------------------
-- Sliders
------------------------------------------------------------------------
local function optionsSlider(o, s)
	s.skin = "slider"
	o:SetSize(144, 17)
	s.orient = "HORIZONTAL"
	o.Text = child(o, "Text", fstr(o, "ARTWORK", "GameFontHighlight", "Text"))
	o.Text:SetPoint("BOTTOM", o, "TOP", 0, 0)
	o.Low = child(o, "Low", fstr(o, "ARTWORK", "GameFontHighlightSmall", "Low"))
	o.Low:SetPoint("TOPLEFT", o, "BOTTOMLEFT", -4, 3)
	o.High = child(o, "High", fstr(o, "ARTWORK", "GameFontHighlightSmall", "High"))
	o.High:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 4, 3)
	local thumb = o:CreateTexture(nil, "OVERLAY")
	S[thumb].isThumb = o
	thumb:SetSize(32, 32)
	s.thumb = thumb
	o.Thumb = thumb
end
T.OptionsSliderTemplate = optionsSlider
T.HorizontalSliderTemplate = function(o, s) s.skin = "slider" s.orient = "HORIZONTAL" o:SetSize(144, 17) end
T.UISliderTemplate = T.HorizontalSliderTemplate
T.UISliderTemplateWithLabels = optionsSlider
T.MinimalSliderTemplate = T.HorizontalSliderTemplate
T.MinimalSliderWithSteppersTemplate = function(o, s)
	-- This one is a Frame wrapping a Slider in game.
	s.skin = nil
	local sl = CreateFrame("Slider", nil, o, "HorizontalSliderTemplate")
	sl:SetPoint("LEFT", o, "LEFT", 20, 0)
	sl:SetPoint("RIGHT", o, "RIGHT", -20, 0)
	o.Slider = sl
	o.Label = { Left = fstr(o, "ARTWORK", "GameFontHighlightSmall"), Right = fstr(o, "ARTWORK", "GameFontHighlightSmall") }
	o.Label.Right:SetPoint("LEFT", o, "RIGHT", 4, 0)
	o.Init = function(self, value, lo, hi, steps, formatters)
		sl:SetMinMaxValues(lo, hi)
		sl:SetValueStep((hi - lo) / max(1, steps or 1))
		sl:SetValue(value)
	end
	o.SetValue = function(self, v) sl:SetValue(v) end
	o.GetValue = function() return sl:GetValue() end
	o.RegisterCallback = function(self, ev, fn, owner)
		sl:HookScript("OnValueChanged", function(_, v) fn(owner, v) end)
	end
	if not s.w then o:SetSize(250, 20) end
end

------------------------------------------------------------------------
-- Scroll frames
------------------------------------------------------------------------
local function makeScrollBar(sf, s, name)
	local sb = CreateFrame("Slider", name and (name .. "ScrollBar") or nil, sf)
	S[sb].skin = "scrollbar"
	S[sb].orient = "VERTICAL"
	sb:SetWidth(16)
	sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, -16)
	sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 16)
	sb:SetMinMaxValues(0, 0)
	sb:SetValueStep(1)
	sb:SetValue(0)
	sb:SetScript("OnValueChanged", function(self, v) sf:SetVerticalScroll(v) end)
	local up = CreateFrame("Button", name and (name .. "ScrollBarScrollUpButton") or nil, sb)
	S[up].skin = "scrollup"
	up:SetSize(16, 16)
	up:SetPoint("BOTTOM", sb, "TOP", 0, 0)
	up:SetScript("OnClick", function() sb:SetValue(sb:GetValue() - max(16, sb:GetHeight() / 4)) end)
	local down = CreateFrame("Button", name and (name .. "ScrollBarScrollDownButton") or nil, sb)
	S[down].skin = "scrolldown"
	down:SetSize(16, 16)
	down:SetPoint("TOP", sb, "BOTTOM", 0, 0)
	down:SetScript("OnClick", function() sb:SetValue(sb:GetValue() + max(16, sb:GetHeight() / 4)) end)
	sb.ScrollUpButton, sb.ScrollDownButton = up, down
	sf.ScrollBar = sb
	if name then _G[name .. "ScrollBar"] = sb end
	sf:EnableMouseWheel(true)
	sf:SetScript("OnScrollRangeChanged", function(self, xr, yr)
		yr = yr or self:GetVerticalScrollRange()
		sb:SetMinMaxValues(0, yr)
		if sb:GetValue() > yr then sb:SetValue(yr) end
		if self.scrollBarHideable then sb:SetShown(yr > 0) end
	end)
	sf:SetScript("OnVerticalScroll", function(self, offset)
		if sb:GetValue() ~= offset then sb:SetValue(offset) end
	end)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local step = self.scrollStep or max(16, sb:GetHeight() / 2)
		sb:SetValue(sb:GetValue() - delta * step)
	end)
	return sb
end
T.UIPanelScrollFrameTemplate = function(o, s) makeScrollBar(o, s, s.name) end
T.UIPanelScrollFrameTemplate2 = T.UIPanelScrollFrameTemplate
T.ScrollFrameTemplate = T.UIPanelScrollFrameTemplate
T.FauxScrollFrameTemplate = T.UIPanelScrollFrameTemplate
T.UIPanelScrollFrameCodeTemplate = T.UIPanelScrollFrameTemplate
T.InputScrollFrameTemplate = function(o, s)
	makeScrollBar(o, s, s.name)
	local eb = CreateFrame("EditBox", s.name and (s.name .. "EditBox") or nil, o)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	eb:SetFontObject(ChatFontNormal)
	eb:SetWidth(100)
	o.EditBox = eb
	o:SetScrollChild(eb)
	o.CharCount = fstr(o, "OVERLAY", "GameFontDisableLarge")
	o.CharCount:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -6, 0)
	o.CharCount:Hide()
	o.Instructions = fstr(eb, "ARTWORK", "GameFontNormalSmall")
end
function ScrollFrame_OnLoad(self) end
function ScrollFrame_OnScrollRangeChanged(self, xr, yr) if self.ScrollBar then self.ScrollBar:SetMinMaxValues(0, yr or self:GetVerticalScrollRange()) end end
function ScrollFrame_OnVerticalScroll(self, offset) if self.ScrollBar then self.ScrollBar:SetValue(offset) end end
function ScrollFrameTemplate_OnMouseWheel(self, delta)
	local sb = self.ScrollBar
	if sb then sb:SetValue(sb:GetValue() - delta * max(16, sb:GetHeight() / 2)) end
end
UIPanelScrollFrame_OnMouseWheel = ScrollFrameTemplate_OnMouseWheel
function ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
function ScrollingEdit_OnTextChanged(self, scrollFrame) end
function ScrollingEdit_OnUpdate(self, elapsed, scrollFrame) end
function ScrollingEdit_OnLoad(self) end
function FauxScrollFrame_Update(frame, numItems, numToDisplay, buttonHeight)
	local sb = frame.ScrollBar
	local range = max(0, (numItems - numToDisplay) * buttonHeight)
	if sb then sb:SetMinMaxValues(0, range) end
	return numItems > numToDisplay
end
function FauxScrollFrame_GetOffset(frame) return frame.offset or 0 end
function FauxScrollFrame_SetOffset(frame, o) frame.offset = o end
function FauxScrollFrame_OnVerticalScroll(self, value, itemHeight, updateFunction)
	self.offset = floor(value / itemHeight + 0.5)
	if updateFunction then updateFunction(self) end
end

------------------------------------------------------------------------
-- Panels / windows
------------------------------------------------------------------------
local function basicFrame(withInset, titleOffset)
	return function(o, s)
		s.skin = "dialog"
		o.TitleBg = placeholder(o, "TitleBg")
		o.Bg = placeholder(o, "Bg")
		local title = fstr(o, "OVERLAY", "GameFontNormal", "TitleText")
		title:SetPoint("TOP", o, "TOP", 0, -5)
		title:SetPoint("LEFT", o, "LEFT", 60, 0)
		title:SetPoint("RIGHT", o, "RIGHT", -60, 0)
		title:SetHeight(14)
		o.TitleText = title
		o.title = title
		local cb = CreateFrame("Button", s.name and (s.name .. "CloseButton") or nil, o, "UIPanelCloseButton")
		cb:SetPoint("TOPRIGHT", o, "TOPRIGHT", 1, 1)
		o.CloseButton = cb
		if withInset then
			local i = CreateFrame("Frame", s.name and (s.name .. "Inset") or nil, o, "InsetFrameTemplate")
			i:SetPoint("TOPLEFT", o, "TOPLEFT", 4, -24)
			i:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -6, 4)
			o.Inset = i
			o.InsetBg = i.Bg
		end
		o.SetTitle = function(self, t) self.TitleText:SetText(t) end
		o.SetTitleFormatted = function(self, fmt, ...) self.TitleText:SetFormattedText(fmt, ...) end
		o.GetTitleText = function(self) return self.TitleText end
		o.SetPortraitToAsset = function() end
		o.SetPortraitTextureRaw = function() end
		o.SetPortraitToUnit = function() end
		o.SetPortraitShown = function() end
		o.SetBorder = function() end
		o.SetTitleOffsets = function() end
		o.PortraitContainer = { portrait = placeholder(o, "portraitPlaceholder") }
	end
end
T.BasicFrameTemplate = basicFrame(false)
T.BasicFrameTemplateWithInset = basicFrame(true)
T.PortraitFrameTemplate = basicFrame(false)
T.PortraitFrameTemplateNoCloseButton = basicFrame(false)
T.ButtonFrameTemplate = basicFrame(true)
T.ButtonFrameTemplateMinimizable = basicFrame(true)
T.DefaultPanelTemplate = basicFrame(false)
T.DefaultPanelFlatTemplate = basicFrame(false)
T.DefaultPanelBaseTemplate = basicFrame(false)
T.SimplePanelTemplate = basicFrame(false)
T.PortraitFrameFlatTemplate = basicFrame(false)
T.SettingsFrameTemplate = basicFrame(false)
function ButtonFrameTemplate_HidePortrait() end
function ButtonFrameTemplate_HideButtonBar() end
function ButtonFrameTemplate_HideAttic() end

------------------------------------------------------------------------
-- Edit boxes
------------------------------------------------------------------------
local function inputBox(o, s)
	s.skin = "input"
	o:SetFontObject(ChatFontNormal)
	s.insets = s.insets or { 6, 6, 0, 0 }
	placeholder(o, "Left")
	placeholder(o, "Right")
	placeholder(o, "Middle")
	o:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	o:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
	o:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
end
T.InputBoxTemplate = inputBox
T.InputBoxScriptTemplate = function(o) o:SetScript("OnEscapePressed", function(self) self:ClearFocus() end) end
T.InputBoxInstructionsTemplate = function(o, s)
	inputBox(o, s)
	local ins = fstr(o, "ARTWORK", "GameFontDisableSmall")
	ins:SetPoint("LEFT", o, "LEFT", 6, 0)
	o.Instructions = ins
	o:HookScript("OnTextChanged", function(self) ins:SetShown(self:GetText() == "") end)
end
T.SearchBoxTemplate = T.InputBoxInstructionsTemplate
T.LargeInputBoxTemplate = inputBox
T.AutoCompleteEditBoxTemplate = function() end
function EditBox_ClearFocus(self) self:ClearFocus() end
function EditBox_HighlightText(self) self:HighlightText() end
function EditBox_ClearHighlight(self) self:HighlightText(0, 0) end
function InputBoxInstructions_OnTextChanged(self) if self.Instructions then self.Instructions:SetShown(self:GetText() == "") end end

------------------------------------------------------------------------
-- Action / item buttons
------------------------------------------------------------------------
local function actionButton(o, s)
	if not s.w then o:SetSize(36, 36) end
	local n = s.name
	local icon = o:CreateTexture(n and (n .. "Icon") or nil, "BACKGROUND")
	icon:SetAllPoints(o)
	o.icon, o.Icon = icon, icon
	local cd = CreateFrame("Cooldown", n and (n .. "Cooldown") or nil, o, "CooldownFrameTemplate")
	cd:SetAllPoints(o)
	o.cooldown, o.Cooldown = cd, cd
	o.Count = o:CreateFontString(n and (n .. "Count") or nil, "OVERLAY", "NumberFontNormal")
	o.Count:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", -2, 2)
	o.HotKey = o:CreateFontString(n and (n .. "HotKey") or nil, "OVERLAY", "NumberFontNormalSmallGray")
	o.HotKey:SetPoint("TOPRIGHT", o, "TOPRIGHT", -1, -3)
	o.Name = o:CreateFontString(n and (n .. "Name") or nil, "OVERLAY", "GameFontHighlightSmallOutline")
	o.Name:SetPoint("BOTTOM", o, "BOTTOM", 0, 2)
	o.Border = placeholder(o, "Border", "OVERLAY")
	o.Flash = placeholder(o, "Flash", "OVERLAY")
	o.Flash:Hide()
	o:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	o:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	s.skin = "slot"
end
T.ActionButtonTemplate = actionButton
T.ItemButtonTemplate = actionButton
T.SecureActionButtonTemplate = function(o, s) s.secure = true end
T.SecureUnitButtonTemplate = function(o, s) s.secure = true end
T.SecureHandlerBaseTemplate = function(o, s) s.secure = true end
T.SecureHandlerStateTemplate = T.SecureHandlerBaseTemplate
T.SecureHandlerClickTemplate = T.SecureHandlerBaseTemplate
T.SecureHandlerAttributeTemplate = T.SecureHandlerBaseTemplate
T.SecureHandlerShowHideTemplate = T.SecureHandlerBaseTemplate
T.SecureHandlerEnterLeaveTemplate = T.SecureHandlerBaseTemplate
T.SecureFrameTemplate = T.SecureHandlerBaseTemplate
T.SecureGroupHeaderTemplate = T.SecureHandlerBaseTemplate
T.CooldownFrameTemplate = function(o, s) end
T.SpellBookSkillLineTabTemplate = function() end
T.UIPanelInfoButton = function(o, s) s.skin = "info" o:SetSize(16, 16) end
T.CommunitiesGuildFinderFrameTemplate = function() end

function SIM.secureClick(f, button)
	local s = S[f]
	local a = s.attrs
	if not a then return end
	local t = a.type or a["type1"] or a["*type1"]
	if not t then return end
	local what = a.spell or a.item or a.macrotext or a.macro or a.unit or ""
	SIM.chat("[Sim] secure " .. tostring(t) .. ": " .. tostring(what), 0.5, 0.8, 1)
end

------------------------------------------------------------------------
-- GameTooltip
------------------------------------------------------------------------
local Tooltip = SIM.defclass("GameTooltip", "Frame")
SIM.FRAME_TYPES.GameTooltip = "GameTooltip"

local function ttLine(tt, i, side)
	local s = S[tt]
	s.lines = s.lines or {}
	s.lines[i] = s.lines[i] or {}
	local L = s.lines[i]
	if not L[side] then
		local n = s.name or ("Tooltip" .. s.id)
		local fs = tt:CreateFontString(n .. "Text" .. side .. i, "ARTWORK", i == 1 and "GameTooltipHeaderText" or "GameTooltipText")
		fs:SetJustifyH(side == "Left" and "LEFT" or "RIGHT")
		L[side] = fs
	end
	return L[side]
end

local function ttLayout(tt)
	local s = S[tt]
	local n = s.numLines or 0
	local y = -10
	local widest = s.minWidth or 0
	for i = 1, n do
		local L, R = ttLine(tt, i, "Left"), ttLine(tt, i, "Right")
		L:ClearAllPoints()
		L:SetPoint("TOPLEFT", tt, "TOPLEFT", 10, y)
		local wrap = s.lines[i].wrap
		L:SetWidth(0)
		local lw = L:GetStringWidth()
		if wrap and lw > 280 then L:SetWidth(280) lw = 280 end
		local rw = (R:IsShown() and (R:GetText() or "") ~= "") and R:GetStringWidth() or 0
		local w = lw + (rw > 0 and (rw + 24) or 0)
		if w > widest then widest = w end
		local h = L:GetStringHeight()
		if h < 1 then h = (i == 1) and 14 or 12 end
		R:ClearAllPoints()
		R:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -10, y)
		y = y - h - 2
	end
	tt:SetSize(max(widest + 20, 40), max(-y + 8, 20))
end

local function ttAnchor(tt)
	local s = S[tt]
	local owner, anchor = s.owner, s.anchor or "ANCHOR_NONE"
	local x, y = s.ax or 0, s.ay or 0
	if anchor == "ANCHOR_NONE" or anchor == "ANCHOR_PRESERVE" or not owner then return end
	tt:ClearAllPoints()
	if anchor == "ANCHOR_CURSOR" or anchor == "ANCHOR_CURSOR_RIGHT" or anchor == "ANCHOR_CURSOR_LEFT" then
		tt:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SIM.cursor.x + 12 + x, SIM.cursor.y + 12 + y)
		s.followCursor = true
		return
	end
	s.followCursor = nil
	local map = {
		ANCHOR_RIGHT = { "BOTTOMLEFT", "TOPRIGHT" }, ANCHOR_LEFT = { "BOTTOMRIGHT", "TOPLEFT" },
		ANCHOR_TOP = { "BOTTOM", "TOP" }, ANCHOR_BOTTOM = { "TOP", "BOTTOM" },
		ANCHOR_TOPLEFT = { "BOTTOMLEFT", "TOPLEFT" }, ANCHOR_TOPRIGHT = { "BOTTOMRIGHT", "TOPRIGHT" },
		ANCHOR_BOTTOMLEFT = { "TOPRIGHT", "BOTTOMLEFT" }, ANCHOR_BOTTOMRIGHT = { "TOPLEFT", "BOTTOMRIGHT" },
	}
	local m = map[anchor] or map.ANCHOR_RIGHT
	tt:SetPoint(m[1], owner, m[2], x, y)
end

function Tooltip:SetOwner(owner, anchor, x, y)
	local s = SIM.st(self)
	s.owner, s.anchor, s.ax, s.ay = owner, anchor or "ANCHOR_LEFT", x, y
	self:ClearLines()
end
function Tooltip:GetOwner() return S[self].owner end
function Tooltip:IsOwned(f) return S[self].owner == f end
function Tooltip:SetAnchorType(a, x, y) local s = S[self] s.anchor, s.ax, s.ay = a, x, y end
function Tooltip:GetAnchorType() return S[self].anchor end
function Tooltip:ClearLines()
	local s = S[self]
	if s.lines then
		for _, L in pairs(s.lines) do
			if L.Left then L.Left:SetText("") L.Left:Hide() end
			if L.Right then L.Right:SetText("") L.Right:Hide() end
		end
	end
	s.numLines = 0
end
function Tooltip:AddLine(text, r, g, b, wrap)
	local s = S[self]
	s.numLines = (s.numLines or 0) + 1
	local i = s.numLines
	local L = ttLine(self, i, "Left")
	ttLine(self, i, "Right"):Hide()
	L:SetText(text or "")
	if r then L:SetTextColor(r, g or 1, b or 1) else L:SetTextColor(1, 0.82, 0) end
	L:Show()
	s.lines[i].wrap = (wrap == true or wrap == 1)
	if s.shown then ttLayout(self) ttAnchor(self) end
end
function Tooltip:AddDoubleLine(lt, rt, lr, lg, lb, rr, rg, rb)
	self:AddLine(lt, lr, lg, lb)
	local s = S[self]
	local R = ttLine(self, s.numLines, "Right")
	R:SetText(rt or "")
	if rr then R:SetTextColor(rr, rg or 1, rb or 1) else R:SetTextColor(1, 0.82, 0) end
	R:Show()
	if s.shown then ttLayout(self) end
end
function Tooltip:SetText(text, r, g, b, a, wrap)
	self:ClearLines()
	self:AddLine(text, r or 1, g or 1, b or 1, wrap)
	self:Show()
end
function Tooltip:AppendText(t)
	local L = ttLine(self, 1, "Left")
	L:SetText((L:GetText() or "") .. (t or ""))
end
function Tooltip:NumLines() return S[self].numLines or 0 end
function Tooltip:SetMinimumWidth(w) S[self].minWidth = w end
function Tooltip:GetMinimumWidth() return S[self].minWidth or 0 end
function Tooltip:SetPadding() end
function Tooltip:GetPadding() return 0, 0, 0, 0 end
function Tooltip:AddTexture() end
function Tooltip:AddSpellByID(id) self:AddLine((GetSpellInfo(id))) end
function Tooltip:Show()
	ttLayout(self)
	ttAnchor(self)
	SIM.setShown(self, true)
end
function Tooltip:FadeOut() self:Hide() end
function Tooltip:SetSpellByID(id)
	local name = GetSpellInfo(id)
	self:ClearLines()
	self:AddLine(name or ("Spell " .. tostring(id)), 1, 1, 1)
	self:AddLine("Spell ID " .. tostring(id), 0.6, 0.6, 0.6)
	self:Show()
end
Tooltip.SetSpell = Tooltip.SetSpellByID
function Tooltip:SetSpellBookItem(i)
	local n = GetSpellBookItemName(i)
	self:SetText(n or "Spell")
end
function Tooltip:SetUnit(unit)
	if not UnitExists(unit) then return end
	self:ClearLines()
	local name = UnitName(unit)
	local _, class = UnitClass(unit)
	local c = RAID_CLASS_COLORS[class]
	self:AddLine(name, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	self:AddLine("Level " .. UnitLevel(unit) .. " " .. (UnitClass(unit) or ""), 1, 1, 1)
	self:Show()
	SIM.runScript(self, "OnTooltipSetUnit")
end
function Tooltip:GetUnit() return nil end
function Tooltip:GetSpell() return nil end
function Tooltip:GetItem() return nil end
function Tooltip:SetHyperlink(link)
	local kind, id = string.match(tostring(link), "|?H?(%a+):(%d+)")
	self:ClearLines()
	if kind == "spell" then return self:SetSpellByID(tonumber(id)) end
	self:AddLine((kind or "link") .. " " .. tostring(id or link), 1, 1, 1)
	self:Show()
end
function Tooltip:SetItemByID(id) self:SetText("Item " .. tostring(id)) end
function Tooltip:SetInventoryItem() self:SetText("Inventory item") return false end
function Tooltip:SetBagItem() self:SetText("Bag item") end
function Tooltip:SetAction() self:SetText("Action") end
function Tooltip:SetUnitAura() self:SetText("Aura") end
function Tooltip:SetUnitBuff() self:SetText("Buff") end
function Tooltip:SetUnitDebuff() self:SetText("Debuff") end
function Tooltip:SetQuestLogItem() self:SetText("Quest item") end
function Tooltip:SetTalent() self:SetText("Talent") end
function Tooltip:SetPetAction() self:SetText("Pet action") end
function Tooltip:SetShapeshift() self:SetText("Shapeshift") end
function Tooltip:SetMerchantItem() self:SetText("Merchant item") end
function Tooltip:SetLootItem() self:SetText("Loot item") end
function Tooltip:SetTradeSkillItem() self:SetText("Tradeskill item") end
function Tooltip:SetCurrencyToken() self:SetText("Currency") end
function Tooltip:IsUnit() return false end
function Tooltip:SetCustomLineSpacing() end
function Tooltip:GetTooltipData() return nil end
function Tooltip:ProcessInfo() return false end

local function makeTooltip(o, s)
	tooltipBackdrop(o)
	o:SetFrameStrata("TOOLTIP")
	o:SetClampedToScreen(true)
	s.numLines = 0
	o:Hide()
end
T.GameTooltipTemplate = makeTooltip
T.SharedTooltipTemplate = makeTooltip
T.SharedNoHeaderTooltipTemplate = makeTooltip
T.TooltipTemplate = makeTooltip

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent, "GameTooltipTemplate")
ShoppingTooltip1 = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent, "GameTooltipTemplate")
ShoppingTooltip2 = CreateFrame("GameTooltip", "ShoppingTooltip2", UIParent, "GameTooltipTemplate")
EmbeddedItemTooltip = CreateFrame("GameTooltip", "EmbeddedItemTooltip", UIParent, "GameTooltipTemplate")
function GameTooltip_SetDefaultAnchor(tt, parent)
	tt:SetOwner(parent, "ANCHOR_NONE")
	tt:ClearAllPoints()
	tt:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -13 - 100, 100)
end
function GameTooltip_Hide() GameTooltip:Hide() end
function GameTooltip_AddNormalLine(tt, t, wrap) tt:AddLine(t, 1, 0.82, 0, wrap) end
function GameTooltip_AddHighlightLine(tt, t, wrap) tt:AddLine(t, 1, 1, 1, wrap) end
function GameTooltip_AddInstructionLine(tt, t, wrap) tt:AddLine(t, 0.1, 1, 0.1, wrap) end
function GameTooltip_AddErrorLine(tt, t, wrap) tt:AddLine(t, 1, 0.1, 0.1, wrap) end
function GameTooltip_AddColoredLine(tt, t, c, wrap) tt:AddLine(t, c.r, c.g, c.b, wrap) end
function GameTooltip_AddBlankLineToTooltip(tt) tt:AddLine(" ") end
function GameTooltip_SetTitle(tt, t, c, wrap) tt:SetText(t, c and c.r or 1, c and c.g or 1, c and c.b or 1, 1, wrap) end
TooltipDataProcessor = { AddTooltipPostCall = function() end, AddLinePostCall = function() end, AllTypes = "ALL" }
SIM.afterTick = function()
	for _, tt in ipairs({ GameTooltip }) do
		local s = S[tt]
		if s.followCursor and s.shown then
			tt:ClearAllPoints()
			tt:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SIM.cursor.x + 12, SIM.cursor.y + 12)
		end
		if s.shown and s.owner and S[s.owner] and not SIM.isVisible(s.owner) then tt:Hide() end
	end
end

------------------------------------------------------------------------
-- StaticPopup
------------------------------------------------------------------------
StaticPopupDialogs = StaticPopupDialogs or {}
STATICPOPUP_NUMDIALOGS = 4
local popups = {}

local function popupFrame(i)
	if popups[i] then return popups[i] end
	local f = CreateFrame("Frame", "StaticPopup" .. i, UIParent)
	f:SetBackdrop(BACKDROP_DIALOG_32_32)
	f:SetFrameStrata("DIALOG")
	f:SetSize(320, 100)
	f:EnableMouse(true)
	f:Hide()
	local text = f:CreateFontString("StaticPopup" .. i .. "Text", "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOP", f, "TOP", 0, -16)
	text:SetWidth(290)
	f.text, f.Text = text, text
	local eb = CreateFrame("EditBox", "StaticPopup" .. i .. "EditBox", f, "InputBoxTemplate")
	eb:SetSize(240, 32)
	eb:SetAutoFocus(false)
	eb:Hide()
	f.editBox, f.EditBox = eb, eb
	f.GetEditBox = function(self) return self.editBox end
	f.GetTextFontString = function(self) return self.text end
	for b = 1, 3 do
		local btn = CreateFrame("Button", "StaticPopup" .. i .. "Button" .. b, f, "UIPanelButtonTemplate")
		btn:SetSize(128, 21)
		f["button" .. b] = btn
		btn:SetScript("OnClick", function() SIM.popupClick(f, b) end)
	end
	f.GetButton = function(self, n) return self["button" .. n] end
	f.GetButton1 = function(self) return self.button1 end
	f.GetButton2 = function(self) return self.button2 end
	eb:SetScript("OnEnterPressed", function(self)
		local d = StaticPopupDialogs[f.which]
		if d and d.EditBoxOnEnterPressed then SIM.pcall(d.EditBoxOnEnterPressed, self, f.data)
		else SIM.popupClick(f, 1) end
	end)
	eb:SetScript("OnEscapePressed", function(self)
		local d = StaticPopupDialogs[f.which]
		if d and d.EditBoxOnEscapePressed then SIM.pcall(d.EditBoxOnEscapePressed, self, f.data)
		else f:Hide() end
	end)
	eb:SetScript("OnTextChanged", function(self, user)
		local d = StaticPopupDialogs[f.which]
		if d and d.EditBoxOnTextChanged then SIM.pcall(d.EditBoxOnTextChanged, self, f.data) end
	end)
	f:SetScript("OnHide", function(self)
		local d = StaticPopupDialogs[self.which]
		if d and d.OnHide then SIM.pcall(d.OnHide, self, self.data) end
	end)
	popups[i] = f
	return f
end

function SIM.popupClick(f, b)
	local d = StaticPopupDialogs[f.which]
	if not d then f:Hide() return end
	local keep
	if b == 1 and d.OnAccept then keep = SIM.pcall(d.OnAccept, f, f.data, f.data2) and nil end
	if b == 1 and d.OnAccept then
		-- OnAccept returning true keeps the dialog open.
	end
	if b == 2 and d.OnCancel then SIM.pcall(d.OnCancel, f, f.data, "clicked") end
	if b == 3 and d.OnAlt then SIM.pcall(d.OnAlt, f, f.data, "clicked") end
	f:Hide()
end

function StaticPopup_Show(which, a1, a2, data, insertedFrame)
	local d = StaticPopupDialogs[which]
	if not d then return nil end
	if d.exclusive or true then
		for _, p in ipairs(popups) do if p:IsShown() and p.which == which then p:Hide() end end
	end
	local f
	for i = 1, STATICPOPUP_NUMDIALOGS do
		local p = popupFrame(i)
		if not p:IsShown() then f = p break end
	end
	if not f then return nil end
	f.which, f.data, f.data2 = which, data, nil
	local txt = d.text or ""
	local ok, formatted = pcall(string.format, txt, a1 or "", a2 or "")
	f.text:SetText(ok and formatted or txt)
	local h = 32 + f.text:GetStringHeight()
	if d.hasEditBox then
		f.editBox:Show()
		f.editBox:ClearAllPoints()
		f.editBox:SetPoint("TOP", f.text, "BOTTOM", 0, -8)
		f.editBox:SetText("")
		if d.maxLetters then f.editBox:SetMaxLetters(d.maxLetters) end
		h = h + 40
	else
		f.editBox:Hide()
	end
	local buttons = {}
	for b = 1, 3 do
		local label = d["button" .. b]
		local btn = f["button" .. b]
		if label then btn:SetText(label) btn:Show() buttons[#buttons + 1] = btn else btn:Hide() end
	end
	local total = #buttons * 128 + (#buttons - 1) * 12
	for i, btn in ipairs(buttons) do
		btn:ClearAllPoints()
		btn:SetPoint("BOTTOMLEFT", f, "BOTTOM", -total / 2 + (i - 1) * 140, 16)
	end
	if #buttons > 0 then h = h + 36 end
	f:SetHeight(max(h, 80))
	f:ClearAllPoints()
	local idx = 0
	for i, p in ipairs(popups) do if p == f then idx = i end end
	f:SetPoint("TOP", UIParent, "TOP", 0, -135 - (idx - 1) * 110)
	f:Show()
	if d.OnShow then SIM.pcall(d.OnShow, f, data) end
	if d.hasEditBox and d.autoFocus ~= false then f.editBox:SetFocus() end
	if d.timeout and d.timeout > 0 then
		C_Timer.After(d.timeout, function() if f:IsShown() and f.which == which then f:Hide() end end)
	end
	return f
end
function StaticPopup_Hide(which, data)
	for _, p in ipairs(popups) do
		if p:IsShown() and p.which == which and (data == nil or p.data == data) then p:Hide() end
	end
end
function StaticPopup_Visible(which)
	for i, p in ipairs(popups) do if p:IsShown() and p.which == which then return p:GetName(), p end end
end
function StaticPopup_FindVisible(which, data)
	for _, p in ipairs(popups) do if p:IsShown() and p.which == which and (data == nil or p.data == data) then return p end end
end
function StaticPopup_HideAll() for _, p in ipairs(popups) do p:Hide() end end
function StaticPopup_EscapePressed() for i = #popups, 1, -1 do if popups[i]:IsShown() then popups[i]:Hide() return true end end end
StaticPopupDialogs.SIM_MESSAGE = { text = "%s", button1 = OKAY, timeout = 0, whileDead = true }
function SIM.showMessage(text) StaticPopup_Show("SIM_MESSAGE", text) end

------------------------------------------------------------------------
-- Settings window (Settings.* and the legacy InterfaceOptions API)
------------------------------------------------------------------------
SIM.optionCategories = {}
local settingsFrame, contentFrame, listButtons = nil, nil, {}

local function ensureSettingsFrame()
	if settingsFrame then return settingsFrame end
	local f = CreateFrame("Frame", "SettingsPanel", UIParent, "BasicFrameTemplate")
	f:SetSize(920, 660)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.TitleText:SetText("Options")
	f:Hide()
	tinsert(UISpecialFrames, "SettingsPanel")
	local list = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	list:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
	list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 40)
	list:SetWidth(200)
	f.List = list
	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
	content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 40)
	f.Container = content
	contentFrame = content
	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(96, 22)
	close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
	close:SetText(CLOSE)
	close:SetScript("OnClick", function() f:Hide() end)
	f:SetScript("OnHide", function()
		for _, c in ipairs(SIM.optionCategories) do
			if c.frame and c.frame:IsShown() then
				if c.frame.okay then SIM.pcall(c.frame.okay, c.frame) end
				if c.frame.OnCommit then SIM.pcall(c.frame.OnCommit, c.frame) end
			end
		end
	end)
	settingsFrame = f
	return f
end

local function refreshList()
	local f = ensureSettingsFrame()
	local y = -8
	local idx = 0
	for _, c in ipairs(SIM.optionCategories) do
		idx = idx + 1
		local b = listButtons[idx]
		if not b then
			b = CreateFrame("Button", nil, f.List)
			b:SetHeight(20)
			b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
			b.text:SetJustifyH("LEFT")
			b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
			b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
			b.sel = b:CreateTexture(nil, "BACKGROUND")
			b.sel:SetAllPoints()
			b.sel:SetColorTexture(1, 0.82, 0, 0.18)
			listButtons[idx] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", f.List, "TOPLEFT", 4 + (c.parentCat and 12 or 0), y)
		b:SetPoint("RIGHT", f.List, "RIGHT", -4, 0)
		b.text:SetText(c.name)
		b.text:SetFontObject(c.parentCat and GameFontHighlightSmall or GameFontNormal)
		b.sel:SetShown(SIM.currentCategory == c)
		b:SetScript("OnClick", function() SIM.selectCategory(c) end)
		b:Show()
		y = y - 22
	end
	for i = idx + 1, #listButtons do listButtons[i]:Hide() end
end

function SIM.selectCategory(c)
	ensureSettingsFrame()
	for _, other in ipairs(SIM.optionCategories) do
		if other ~= c and other.frame then other.frame:Hide() end
	end
	SIM.currentCategory = c
	if c.build and not c.frame then c.frame = c.build() end
	local fr = c.frame
	if fr then
		fr:SetParent(contentFrame)
		fr:ClearAllPoints()
		fr:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
		fr:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
		fr:Show()
		if fr.refresh then SIM.pcall(fr.refresh, fr) end
		if fr.OnRefresh then SIM.pcall(fr.OnRefresh, fr) end
	end
	refreshList()
end

local Category = {}
Category.__index = Category
function Category:GetID() return self.ID end
function Category:GetName() return self.name end
function Category:GetParentCategory() return self.parentCat end
function Category:SetParentCategory(p) self.parentCat = p end
function Category:HasParentCategory() return self.parentCat ~= nil end
function Category:GetSubcategories() return self.subs or {} end
function Category:SetShouldSortAlphabetically() end
function Category:GetOrder() return 0 end
function Category:SetOrder() end

local nextCatId = 1000
local function newCategory(frame, name, parent)
	nextCatId = nextCatId + 1
	local c = setmetatable({ ID = nextCatId, name = name or (frame and frame.name) or "AddOn", frame = frame, parentCat = parent }, Category)
	if parent then parent.subs = parent.subs or {} table.insert(parent.subs, c) end
	if frame then
		frame:Hide()
		frame:SetParent(SIM.hiddenParent)
	end
	return c
end

local function registerCategory(c)
	for _, x in ipairs(SIM.optionCategories) do if x == c then return end end
	if c.parentCat then
		local idx
		for i, x in ipairs(SIM.optionCategories) do if x == c.parentCat or x.parentCat == c.parentCat then idx = i end end
		if idx then table.insert(SIM.optionCategories, idx + 1, c) else table.insert(SIM.optionCategories, c) end
	else
		table.insert(SIM.optionCategories, c)
	end
	if settingsFrame then refreshList() end
end

local function findCategory(id)
	for _, c in ipairs(SIM.optionCategories) do
		if c == id or c.ID == id or c.name == id or c.frame == id then return c end
	end
end

-- Vertical layout categories: controls built from registered settings.
local function buildVertical(c)
	local f = CreateFrame("Frame", nil, SIM.hiddenParent)
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
	title:SetText(c.name)
	local y = -50
	for _, init in ipairs(c.initializers or {}) do
		local setting = init.setting
		if init.kind == "header" then
			local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
			h:SetPoint("TOPLEFT", f, "TOPLEFT", 14, y)
			h:SetText(init.text)
			y = y - 30
		elseif init.kind == "checkbox" then
			local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			label:SetPoint("TOPLEFT", f, "TOPLEFT", 30, y - 6)
			label:SetText(setting.name)
			local cb = CreateFrame("CheckButton", nil, f, "SettingsCheckBoxTemplate")
			cb:SetPoint("TOPLEFT", f, "TOPLEFT", 300, y)
			cb:SetChecked(setting:GetValue())
			cb:SetScript("OnClick", function(self) setting:SetValue(self:GetChecked()) end)
			setting.control = cb
			y = y - 34
		elseif init.kind == "slider" then
			local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			label:SetPoint("TOPLEFT", f, "TOPLEFT", 30, y - 4)
			label:SetText(setting.name)
			local o = init.options or {}
			local sl = CreateFrame("Slider", nil, f, "HorizontalSliderTemplate")
			sl:SetPoint("TOPLEFT", f, "TOPLEFT", 300, y)
			sl:SetWidth(220)
			sl:SetMinMaxValues(o.minValue or 0, o.maxValue or 1)
			sl:SetValueStep(o.steps and ((o.maxValue - o.minValue) / o.steps) or o.step or 1)
			sl:SetObeyStepOnDrag(true)
			sl:SetValue(setting:GetValue() or o.minValue or 0)
			local val = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			val:SetPoint("LEFT", sl, "RIGHT", 10, 0)
			local function fmt(v)
				local lf = o.formatters and (o.formatters[2] or o.formatters[1])
				if lf then local ok, r = pcall(lf, v) if ok then return r end end
				return string.format("%g", floor(v * 100 + 0.5) / 100)
			end
			val:SetText(fmt(sl:GetValue()))
			sl:SetScript("OnValueChanged", function(self, v, user) val:SetText(fmt(v)) if user then setting:SetValue(v) end end)
			y = y - 34
		elseif init.kind == "dropdown" then
			local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			label:SetPoint("TOPLEFT", f, "TOPLEFT", 30, y - 6)
			label:SetText(setting.name)
			local dd = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
			dd:SetPoint("TOPLEFT", f, "TOPLEFT", 284, y + 2)
			UIDropDownMenu_SetWidth(dd, 180)
			UIDropDownMenu_Initialize(dd, function(self, level)
				local opts = init.options
				if type(opts) == "function" then opts = opts() end
				local list = opts and opts.GetData and opts:GetData() or opts or {}
				for _, opt in ipairs(list) do
					local info = UIDropDownMenu_CreateInfo()
					info.text = opt.label or opt.text or tostring(opt.value)
					info.value = opt.value
					info.checked = (setting:GetValue() == opt.value)
					info.func = function() setting:SetValue(opt.value) UIDropDownMenu_SetText(dd, info.text) end
					UIDropDownMenu_AddButton(info, level)
					if info.checked then UIDropDownMenu_SetText(dd, info.text) end
				end
			end)
			y = y - 38
		elseif init.kind == "button" then
			local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
			b:SetPoint("TOPLEFT", f, "TOPLEFT", 300, y)
			b:SetSize(160, 22)
			b:SetText(init.text)
			b:SetScript("OnClick", function() if init.click then SIM.pcall(init.click) end end)
			local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			label:SetPoint("TOPLEFT", f, "TOPLEFT", 30, y - 4)
			label:SetText(init.label or "")
			y = y - 32
		end
	end
	return f
end

local Setting = {}
Setting.__index = Setting
function Setting:GetValue()
	if self.getter then return self.getter() end
	if self.tbl then
		local v = self.tbl[self.key]
		if v == nil then return self.default end
		return v
	end
	return self.value
end
function Setting:SetValue(v)
	if self.setter then self.setter(v)
	elseif self.tbl then self.tbl[self.key] = v
	else self.value = v end
	for _, cb in ipairs(self.callbacks or {}) do SIM.pcall(cb.fn, cb.owner or self, self, v) end
	if self.control and self.control.SetChecked and type(v) == "boolean" then self.control:SetChecked(v) end
end
function Setting:GetVariable() return self.variable end
function Setting:GetName() return self.name end
function Setting:GetDefaultValue() return self.default end
function Setting:SetValueToDefault() self:SetValue(self.default) end
function Setting:SetValueChangedCallback(fn, owner)
	self.callbacks = self.callbacks or {}
	table.insert(self.callbacks, { fn = fn, owner = owner })
end
function Setting:NotifyUpdate() end
function Setting:HasCommitFlag() return false end
function Setting:SetCommitFlags() end

Settings = {
	VarType = { Boolean = "boolean", Number = "number", String = "string" },
	Default = { True = true, False = false },
	CommitFlag = { None = 0, Apply = 1, Revertable = 2 },
}
function Settings.RegisterCanvasLayoutCategory(frame, name, group)
	return newCategory(frame, name)
end
function Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
	return newCategory(frame, name, parent)
end
function Settings.RegisterVerticalLayoutCategory(name)
	local c = newCategory(nil, name)
	c.initializers = {}
	c.build = function() return buildVertical(c) end
	local layout = { AddInitializer = function(_, init) table.insert(c.initializers, init) end }
	c.layout = layout
	return c, layout
end
function Settings.RegisterVerticalLayoutSubcategory(parent, name)
	local c, layout = Settings.RegisterVerticalLayoutCategory(name)
	c.parentCat = parent
	parent.subs = parent.subs or {}
	table.insert(parent.subs, c)
	return c, layout
end
function Settings.RegisterAddOnCategory(c)
	registerCategory(c)
	if c.subs then for _, s in ipairs(c.subs) do registerCategory(s) end end
end
function Settings.OpenToCategory(id)
	local c = findCategory(id) or SIM.optionCategories[1]
	if not c then return false end
	ensureSettingsFrame():Show()
	SIM.selectCategory(c)
	return true
end
function Settings.GetCategory(id) return findCategory(id) end
function Settings.RegisterAddOnSetting(category, variable, key, tbl, vtype, name, default)
	-- Older form: (category, name, variable, vtype, default)
	if type(tbl) ~= "table" then
		local s = setmetatable({ variable = variable, name = name or key, default = default, value = default }, Setting)
		if type(key) == "string" and type(variable) == "string" and tbl and type(tbl) ~= "table" then
			s.name, s.variable, s.default = variable, key, default
		end
		return s
	end
	return setmetatable({ variable = variable, key = key, tbl = tbl, vtype = vtype, name = name, default = default }, Setting)
end
function Settings.RegisterProxySetting(category, variable, vtype, name, default, getter, setter)
	return setmetatable({ variable = variable, name = name, default = default, getter = getter, setter = setter }, Setting)
end
local function addInit(category, init)
	if category and category.initializers then table.insert(category.initializers, init) end
	init.GetSetting = function() return init.setting end
	init.SetParentInitializer = function() end
	init.AddSearchTags = function() end
	init.AddShownPredicate = function() end
	init.AddModifyPredicate = function() end
	init.GetData = function() return init end
	return init
end
function Settings.CreateCheckbox(category, setting, tooltip) return addInit(category, { kind = "checkbox", setting = setting, tooltip = tooltip }) end
Settings.CreateCheckBox = Settings.CreateCheckbox
function Settings.CreateSlider(category, setting, options, tooltip) return addInit(category, { kind = "slider", setting = setting, options = options, tooltip = tooltip }) end
function Settings.CreateDropdown(category, setting, options, tooltip) return addInit(category, { kind = "dropdown", setting = setting, options = options, tooltip = tooltip }) end
Settings.CreateDropDown = Settings.CreateDropdown
function Settings.CreateCheckboxWithOptions(category, setting, options, tooltip) return Settings.CreateCheckbox(category, setting, tooltip) end
function Settings.CreateSliderOptions(minValue, maxValue, step)
	local o = { minValue = minValue, maxValue = maxValue, step = step }
	o.SetLabelFormatter = function(self, label, fn) self.formatters = self.formatters or {} self.formatters[label or 1] = fn end
	return o
end
function Settings.CreateControlTextContainer()
	local c = { data = {} }
	function c:Add(value, label, tooltip) table.insert(self.data, { value = value, label = label, tooltip = tooltip }) end
	function c:GetData() return self.data end
	return c
end
function Settings.CreateElementInitializer(template, data) return { kind = "custom", data = data } end
function Settings.SetOnValueChangedCallback(variable, fn, owner) end
function Settings.GetValue() return nil end
function Settings.SetValue() end
function Settings.NotifyUpdate() end
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
function CreateSettingsListSectionHeaderInitializer(text) return { kind = "header", text = text } end
function CreateSettingsButtonInitializer(label, text, click, tooltip) return { kind = "button", label = label, text = text, click = click } end
SettingsPanel_Show = function() ensureSettingsFrame():Show() end

-- Legacy InterfaceOptions.
function InterfaceOptions_AddCategory(panel)
	local parent
	if panel.parent then
		for _, c in ipairs(SIM.optionCategories) do if c.name == panel.parent then parent = c end end
	end
	local c = newCategory(panel, panel.name, parent)
	registerCategory(c)
	return c
end
function InterfaceOptionsFrame_OpenToCategory(panel)
	if type(panel) == "string" then return Settings.OpenToCategory(panel) end
	local c = findCategory(panel)
	if c then return Settings.OpenToCategory(c) end
end
InterfaceOptionsFrame_Show = function() ensureSettingsFrame():Show() end
InterfaceAddOnsList_Update = function() end
InterfaceOptionsFramePanelContainer = UIParent
InterfaceOptionsFrame = { Show = function() ensureSettingsFrame():Show() end, Hide = function() if settingsFrame then settingsFrame:Hide() end end, IsShown = function() return settingsFrame and settingsFrame:IsShown() end }

function SIM.listCategories()
	local out = {}
	for i, c in ipairs(SIM.optionCategories) do out[i] = { name = c.name, sub = c.parentCat ~= nil } end
	return out
end

------------------------------------------------------------------------
-- UIDropDownMenu (classic dropdowns)
------------------------------------------------------------------------
UIDROPDOWNMENU_MAXLEVELS = 3
UIDROPDOWNMENU_MAXBUTTONS = 32
UIDROPDOWNMENU_MENU_LEVEL = 1
UIDROPDOWNMENU_MENU_VALUE = nil
UIDROPDOWNMENU_OPEN_MENU = nil
UIDROPDOWNMENU_INIT_MENU = nil
local ddLists = {}
local collecting -- non-nil while running an initialize function

local function ddList(level)
	if ddLists[level] then return ddLists[level] end
	local f = CreateFrame("Button", "DropDownList" .. level, UIParent)
	f:SetBackdrop(BACKDROP_TOOLTIP_16_16_5555)
	f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:Hide()
	f.buttons = {}
	f:SetScript("OnHide", function() for l = level + 1, UIDROPDOWNMENU_MAXLEVELS do if ddLists[l] then ddLists[l]:Hide() end end end)
	ddLists[level] = f
	return f
end

local function ddButton(list, i)
	local b = list.buttons[i]
	if b then return b end
	b = CreateFrame("Button", list:GetName() .. "Button" .. i, list)
	b:SetHeight(16)
	b.check = b:CreateTexture(nil, "ARTWORK")
	b.check:SetSize(10, 10)
	b.check:SetPoint("LEFT", b, "LEFT", 2, 0)
	b.check:SetColorTexture(1, 0.82, 0, 1)
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmallLeft")
	b.text:SetPoint("LEFT", b, "LEFT", 18, 0)
	b.arrow = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	b.arrow:SetPoint("RIGHT", b, "RIGHT", -2, 0)
	b.arrow:SetText(">")
	b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	b:GetHighlightTexture():SetVertexColor(0.3, 0.5, 1, 0.35)
	list.buttons[i] = b
	return b
end

function UIDropDownMenu_CreateInfo() return {} end

function UIDropDownMenu_AddButton(info, level)
	level = level or 1
	if collecting then
		if collecting.level == level then table.insert(collecting.items, CopyTable(info, true)) end
		return
	end
end
function UIDropDownMenu_AddSeparator(level) UIDropDownMenu_AddButton({ isSeparator = true, notCheckable = true, text = "" }, level) end
function UIDropDownMenu_AddSpace(level) UIDropDownMenu_AddButton({ isSeparator = true, notCheckable = true, text = "" }, level) end

local function collect(frame, level, value, menuList)
	local items = {}
	if not frame or not frame.initialize then return items end
	local prev = collecting
	collecting = { level = level, items = items }
	UIDROPDOWNMENU_MENU_LEVEL, UIDROPDOWNMENU_MENU_VALUE, UIDROPDOWNMENU_INIT_MENU = level, value, frame
	SIM.pcall(frame.initialize, frame, level, menuList)
	collecting = prev
	return items
end

local function isChecked(info)
	local c = info.checked
	if type(c) == "function" then local ok, r = pcall(c, info) return ok and r end
	return c
end

function UIDropDownMenu_Initialize(frame, fn, displayMode, level, menuList)
	frame.initialize = fn
	frame.displayMode = displayMode
	frame.menuList = menuList
	-- Run once so selected text can be filled in, like the real one.
	local items = collect(frame, level or 1, nil, menuList)
	if frame.selectedValue ~= nil or frame.selectedID or frame.selectedName then
		for i, info in ipairs(items) do
			if (frame.selectedValue ~= nil and info.value == frame.selectedValue) or frame.selectedID == i or (frame.selectedName and info.text == frame.selectedName) then
				UIDropDownMenu_SetText(frame, info.text)
			end
		end
	end
end
function UIDropDownMenu_Refresh(frame) UIDropDownMenu_Initialize(frame, frame.initialize, frame.displayMode) end
function UIDropDownMenu_SetInitializeFunction(frame, fn) frame.initialize = fn end
function UIDropDownMenu_SetDisplayMode(frame, mode) frame.displayMode = mode end

function CloseDropDownMenus(level)
	for l = level or 1, UIDROPDOWNMENU_MAXLEVELS do if ddLists[l] then ddLists[l]:Hide() end end
end

function ToggleDropDownMenu(level, value, frame, anchorName, xOffset, yOffset, menuList, button, autoHideDelay)
	level = level or 1
	local list = ddList(level)
	if level == 1 and list:IsShown() and UIDROPDOWNMENU_OPEN_MENU == frame then list:Hide() return end
	if level == 1 then UIDROPDOWNMENU_OPEN_MENU = frame end
	frame = frame or UIDROPDOWNMENU_OPEN_MENU
	if not frame then return end
	local items = collect(frame, level, value, menuList)
	local width = 80
	for _, info in ipairs(items) do
		local w = SIM.rawWidth(SIM.plainText(info.text or ""), "Fonts\\FRIZQT__.TTF", 10) + 40
		if w > width then width = w end
	end
	for i, info in ipairs(items) do
		local b = ddButton(list, i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", list, "TOPLEFT", 12, -12 - (i - 1) * 16)
		b:SetWidth(width)
		b.text:SetText((info.colorCode or "") .. (info.text or ""))
		b.text:SetFontObject(info.isTitle and GameFontNormalSmall or (info.disabled and GameFontDisableSmall or GameFontHighlightSmallLeft))
		b.check:SetShown(not info.notCheckable and isChecked(info) and true or false)
		b.arrow:SetShown(info.hasArrow and true or false)
		b.value, b.arg1, b.arg2, b.checked = info.value, info.arg1, info.arg2, isChecked(info)
		local clickable = not info.isTitle and not info.disabled and not info.isSeparator
		b:SetEnabled(clickable)
		b:SetScript("OnClick", function(self)
			if not clickable then return end
			local checked = isChecked(info)
			if not info.notCheckable and info.isNotRadio then checked = not checked end
			if info.func then SIM.pcall(info.func, self, info.arg1, info.arg2, checked) end
			if not info.keepShownOnClick then CloseDropDownMenus() end
		end)
		b:SetScript("OnEnter", function(self)
			CloseDropDownMenus(level + 1)
			if info.hasArrow then
				ToggleDropDownMenu(level + 1, info.value, frame, nil, nil, nil, info.menuList)
				local sub = ddLists[level + 1]
				if sub then sub:ClearAllPoints() sub:SetPoint("TOPLEFT", self, "TOPRIGHT", 10, 12) end
			end
		end)
		b:Show()
	end
	for i = #items + 1, #list.buttons do list.buttons[i]:Hide() end
	list:SetSize(width + 24, #items * 16 + 24)
	list:ClearAllPoints()
	if level == 1 then
		local anchor = (anchorName == "cursor") and nil or (type(anchorName) == "table" and anchorName or (type(anchorName) == "string" and _G[anchorName]) or frame)
		if anchor and S[anchor] then
			list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (xOffset or 0) + (anchor == frame and 16 or 0), (yOffset or 0) + (anchor == frame and 4 or 0))
		else
			list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", SIM.cursor.x + (xOffset or 0), SIM.cursor.y + (yOffset or 0))
		end
	end
	list:Show()
	list:Raise()
end

function UIDropDownMenu_SetText(frame, text) if frame.Text then frame.Text:SetText(text) end frame.selectedText = text end
function UIDropDownMenu_GetText(frame) return frame.Text and frame.Text:GetText() end
function UIDropDownMenu_SetWidth(frame, w, padding)
	frame:SetWidth(w + (padding or 25) + 25)
	frame.dropdownWidth = w
end
function UIDropDownMenu_SetButtonWidth() end
function UIDropDownMenu_JustifyText(frame, j) if frame.Text then frame.Text:SetJustifyH(j) end end
function UIDropDownMenu_SetSelectedValue(frame, v, useValue)
	frame.selectedValue, frame.selectedID, frame.selectedName = v, nil, nil
	if frame.initialize then UIDropDownMenu_Initialize(frame, frame.initialize, frame.displayMode) end
end
function UIDropDownMenu_GetSelectedValue(frame) return frame.selectedValue end
function UIDropDownMenu_SetSelectedID(frame, id) frame.selectedID, frame.selectedValue, frame.selectedName = id, nil, nil if frame.initialize then UIDropDownMenu_Initialize(frame, frame.initialize, frame.displayMode) end end
function UIDropDownMenu_GetSelectedID(frame) return frame.selectedID end
function UIDropDownMenu_SetSelectedName(frame, n) frame.selectedName, frame.selectedValue, frame.selectedID = n, nil, nil UIDropDownMenu_SetText(frame, n) end
function UIDropDownMenu_GetSelectedName(frame) return frame.selectedName end
function UIDropDownMenu_EnableDropDown(frame) if frame.Button then frame.Button:Enable() end S[frame].disabled = nil end
function UIDropDownMenu_DisableDropDown(frame) if frame.Button then frame.Button:Disable() end S[frame].disabled = true end
function UIDropDownMenu_IsEnabled(frame) return not S[frame].disabled end
function UIDropDownMenu_SetAnchor(frame, x, y, point, rel, relPoint) end
function UIDropDownMenu_GetCurrentDropDown() return UIDROPDOWNMENU_OPEN_MENU end
function UIDropDownMenu_SetFrameStrata() end
function UIDropDownMenu_HandleGlobalMouseEvent() end
function EasyMenu(menuList, frame, anchor, x, y, displayMode, autoHide)
	frame.initialize = function(self, level, ml)
		for _, info in ipairs(ml or menuList) do UIDropDownMenu_AddButton(info, level) end
	end
	ToggleDropDownMenu(1, nil, frame, anchor, x, y, menuList)
end

T.UIDropDownMenuTemplate = function(o, s)
	s.skin = "dropdown"
	if not s.w then o:SetSize(150, 32) end
	local n = s.name
	o.Text = o:CreateFontString(n and (n .. "Text") or nil, "ARTWORK", "GameFontHighlightSmall")
	o.Text:SetPoint("RIGHT", o, "RIGHT", -43, 2)
	o.Text:SetPoint("LEFT", o, "LEFT", 27, 2)
	o.Text:SetJustifyH("RIGHT")
	o.Text:SetWordWrap(false)
	o.Left, o.Middle, o.Right = placeholder(o, "Left"), placeholder(o, "Middle"), placeholder(o, "Right")
	o.Icon = placeholder(o, "Icon", "OVERLAY")
	local b = CreateFrame("Button", n and (n .. "Button") or nil, o)
	S[b].skin = "ddbutton"
	b:SetSize(24, 24)
	b:SetPoint("TOPRIGHT", o, "TOPRIGHT", -16, -4)
	b:SetScript("OnClick", function() ToggleDropDownMenu(1, nil, o, o, 0, 0) PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end)
	o.Button = b
	o:EnableMouse(true)
	o:SetScript("OnMouseDown", function() if not S[o].disabled then ToggleDropDownMenu(1, nil, o, o, 0, 0) end end)
end
T.UIDropDownListTemplate = function() end
T.UIDropDownCustomMenuEntryTemplate = function() end

-- Modern dropdown/menu: minimal so addons do not explode.
MenuUtil = {}
function MenuUtil.CreateContextMenu(owner, generator)
	SIM.chat("[Sim] context menus (MenuUtil) are not simulated yet", 1, 0.6, 0.2)
end
function MenuUtil.CreateButtonMenu() end
function MenuUtil.CreateCheckboxMenu() end
function MenuUtil.CreateRadioMenu() end
T.WowStyle1DropdownTemplate = function(o, s)
	s.skin = "dropdown"
	if not s.w then o:SetSize(150, 26) end
	o.Text = o:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	o.Text:SetPoint("LEFT", o, "LEFT", 12, 0)
	o.SetupMenu = function(self, gen) self.menuGenerator = gen end
	o.SetDefaultText = function(self, t) self.Text:SetText(t) end
	o.GenerateMenu = function() end
	o.SetText = function(self, t) self.Text:SetText(t) end
	o.OverrideText = o.SetText
	o.SetSelectionTranslator = function() end
	o.SetWidth = function(self, w) SIM.Methods.Frame.SetWidth(self, w) end
end
T.WowStyle2DropdownTemplate = T.WowStyle1DropdownTemplate
T.WowStyle1FilterDropdownTemplate = T.WowStyle1DropdownTemplate
