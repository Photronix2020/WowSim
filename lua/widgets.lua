-- WowSim: widget objects, layout, scripts, events, input and scene export.

local SIM = __SIM
local type, pairs, ipairs, tostring, select, unpack, next = type, pairs, ipairs, tostring, select, unpack, next
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local sgsub, sformat, sfind, ssub, slower, supper = string.gsub, string.format, string.find, string.sub, string.lower, string.upper
local tsort, tconcat = table.sort, table.concat

local S = {}                -- object -> internal state
SIM.S = S
local byId = {}             -- id -> object
SIM.byId = byId
local frames = {}           -- every frame, creation order
SIM.frames = frames
local nextId = 0
local stamp = 1             -- layout invalidation counter
SIM.now = 0
SIM.screenW, SIM.screenH = 1365, 768
SIM.docMethods = SIM.docMethods or {}
SIM.mods = { shift = false, ctrl = false, alt = false }
SIM.cursor = { x = 0, y = 0 }

local function invalidate() stamp = stamp + 1 end
SIM.invalidate = invalidate

------------------------------------------------------------------------
-- Error capture / safe calls
------------------------------------------------------------------------
SIM.errors, SIM.errorSeq = {}, 0
local function traceback(err)
	local msg = tostring(err)
	local stack = debug.traceback("", 2) or ""
	stack = sgsub(stack, "^\nstack traceback:\n", "")
	return { msg = msg, stack = stack }
end

function SIM.reportError(info)
	-- Collapse repeats of the same error (OnUpdate errors fire every frame).
	for i = #SIM.errors, max(1, #SIM.errors - 20), -1 do
		local e = SIM.errors[i]
		if e.msg == info.msg then
			e.count = e.count + 1
			e.time = SIM.now
			SIM.errorSeq = SIM.errorSeq + 1
			e.seq = SIM.errorSeq
			return
		end
	end
	SIM.errorSeq = SIM.errorSeq + 1
	info.count, info.time, info.seq = 1, SIM.now, SIM.errorSeq
	SIM.errors[#SIM.errors + 1] = info
	if #SIM.errors > 200 then table.remove(SIM.errors, 1) end
end

local errorHandler = function(err) return traceback(err) end
SIM.errorHandlerFn = nil -- addon-set handler via seterrorhandler

function SIM.pcall(fn, ...)
	local n = select("#", ...)
	local args = { ... }
	local res = { xpcall(function() return fn(unpack(args, 1, n)) end, errorHandler) }
	if not res[1] then
		SIM.reportError(res[2])
		return false
	end
	return unpack(res)
end
local pcallSafe = SIM.pcall

------------------------------------------------------------------------
-- Stub accounting (APIs we only pretend to have)
------------------------------------------------------------------------
SIM.stubs, SIM.stubSeq = {}, 0
function SIM.noteStub(name)
	local s = SIM.stubs[name]
	if s then s.count = s.count + 1 return end
	SIM.stubSeq = SIM.stubSeq + 1
	SIM.stubs[name] = { count = 1, seq = SIM.stubSeq }
end

------------------------------------------------------------------------
-- Classes
------------------------------------------------------------------------
local Methods, Meta = {}, {}
SIM.Methods = Methods
local stubCache = {}

local function defclass(name, ...)
	local m = {}
	local parents = { ... }
	-- Like the client, getmetatable(frame).__index is a plain method table;
	-- inheritance and documented-but-unimplemented methods hang off its metatable.
	setmetatable(m, { __index = function(_, k)
		for i = 1, #parents do
			local v = Methods[parents[i]][k]
			if v ~= nil then return v end
		end
		if type(k) == "string" and SIM.docMethods[k] then
			local st = stubCache[k]
			if not st then
				st = function() SIM.noteStub("Widget:" .. k) end
				stubCache[k] = st
			end
			return st
		end
	end })
	Methods[name] = m
	Meta[name] = {
		__index = m,
		__tostring = function(t)
			local s = S[t]
			return s and (s.otype .. ":" .. (s.name or ("#" .. s.id))) or "?"
		end,
	}
	return m
end
SIM.Meta = Meta
SIM.defclass = defclass

local function newObject(class, otype, name, parent)
	nextId = nextId + 1
	local o = setmetatable({}, Meta[class])
	o[0] = newproxy()
	local s = {
		id = nextId, class = class, otype = otype, parent = parent,
		shown = true, alpha = 1, scale = 1, points = {}, scripts = {},
	}
	S[o] = s
	byId[nextId] = o
	if name and name ~= "" then
		if parent and sfind(name, "$parent", 1, true) then
			local pn = S[parent] and S[parent].name or ""
			name = sgsub(name, "%$parent", pn)
		end
		s.name = name
		_G[name] = o
	end
	return o, s
end
SIM.newObject = newObject

local function st(o)
	local s = S[o]
	if not s then error("Usage: method called on a non-widget (did you use '.' instead of ':'?)", 3) end
	return s
end
SIM.st = st

------------------------------------------------------------------------
-- Object
------------------------------------------------------------------------
local Object = defclass("Object")
function Object:GetName() return st(self).name end
function Object:GetDebugName() local s = st(self) return s.name or (s.otype .. "#" .. s.id) end
function Object:GetParent() return st(self).parent end
function Object:GetObjectType() return st(self).otype end
function Object:IsObjectType(t)
	local s = st(self)
	if s.otype == t then return true end
	local chain = SIM.typeChain[s.otype]
	return chain and chain[t] or false
end
function Object:IsForbidden() return false end
function Object:SetForbidden() end
function Object:GetParentKey() return st(self).parentKey end
function Object:SetParentKey(k) st(self).parentKey = k end
function Object:ClearParentKey() st(self).parentKey = nil end

SIM.typeChain = {
	Frame = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	Button = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	CheckButton = { Object = true, Region = true, ScriptRegion = true, Frame = true, Button = true },
	EditBox = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	Slider = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	StatusBar = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	ScrollFrame = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	Cooldown = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	GameTooltip = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	MessageFrame = { Object = true, Region = true, ScriptRegion = true, Frame = true },
	ScrollingMessageFrame = { Object = true, Region = true, ScriptRegion = true, Frame = true, MessageFrame = true },
	Texture = { Object = true, Region = true, ScriptRegion = true, LayeredRegion = true },
	MaskTexture = { Object = true, Region = true, ScriptRegion = true, LayeredRegion = true, Texture = true },
	Line = { Object = true, Region = true, ScriptRegion = true, LayeredRegion = true, Texture = true },
	FontString = { Object = true, Region = true, ScriptRegion = true, LayeredRegion = true },
	Font = { Object = true },
	AnimationGroup = { Object = true },
}

------------------------------------------------------------------------
-- Scripts
------------------------------------------------------------------------
local ScriptObject = defclass("ScriptObject", "Object")

local function runScript(o, script, ...)
	local s = S[o]
	if not s then return end
	local h = s.scripts[script]
	if h then pcallSafe(h, o, ...) end
	local hooks = s.hooks and s.hooks[script]
	if hooks then
		for i = 1, #hooks do pcallSafe(hooks[i], o, ...) end
	end
end
SIM.runScript = runScript

local updateList = {}
local function trackUpdate(o, s)
	if (s.scripts.OnUpdate or (s.hooks and s.hooks.OnUpdate)) then updateList[o] = true else updateList[o] = nil end
end

function ScriptObject:SetScript(script, fn)
	local s = st(self)
	s.scripts[script] = fn
	if s.hooks then s.hooks[script] = nil end
	if script == "OnUpdate" then trackUpdate(self, s) end
	if script == "OnLoad" and fn then pcallSafe(fn, self) end
end
function ScriptObject:GetScript(script) return st(self).scripts[script] end
function ScriptObject:HasScript(script) return true end
function ScriptObject:HookScript(script, fn)
	local s = st(self)
	if not s.scripts[script] then
		s.scripts[script] = fn
	else
		s.hooks = s.hooks or {}
		s.hooks[script] = s.hooks[script] or {}
		local list = s.hooks[script]
		list[#list + 1] = fn
	end
	if script == "OnUpdate" then trackUpdate(self, s) end
end

------------------------------------------------------------------------
-- Region: anchors, size, visibility
------------------------------------------------------------------------
local Region = defclass("Region", "ScriptObject")

local PX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local PY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
SIM.PX, SIM.PY = PX, PY

local function resolveRel(rel)
	if type(rel) == "string" then
		local o = _G[rel]
		return o
	end
	return rel
end

function Region:SetPoint(point, a2, a3, a4, a5)
	local s = st(self)
	point = supper(tostring(point))
	if not PX[point] then error("SetPoint: invalid point '" .. tostring(point) .. "'", 2) end
	local rel, relPoint, x, y
	if type(a2) == "number" then
		x, y = a2, a3
		rel = s.parent
		relPoint = point
	else
		if a2 == nil and a3 == nil and a4 == nil then rel = s.parent
		else rel = resolveRel(a2) end
		if type(a3) == "number" then
			x, y, relPoint = a3, a4, point
		else
			relPoint = a3 and supper(a3) or point
			x, y = a4, a5
		end
	end
	if rel == self then error("SetPoint: cannot anchor to itself", 2) end
	local pts = s.points
	for i = 1, #pts do
		if pts[i].p == point then table.remove(pts, i) break end
	end
	pts[#pts + 1] = { p = point, rel = rel, rp = relPoint or point, x = x or 0, y = y or 0 }
	invalidate()
end

function Region:SetAllPoints(rel, doResize)
	local s = st(self)
	rel = resolveRel(rel) or s.parent
	s.points = {
		{ p = "TOPLEFT", rel = rel, rp = "TOPLEFT", x = 0, y = 0 },
		{ p = "BOTTOMRIGHT", rel = rel, rp = "BOTTOMRIGHT", x = 0, y = 0 },
	}
	invalidate()
end

function Region:ClearAllPoints()
	st(self).points = {}
	invalidate()
end

function Region:ClearPoint(point)
	local pts = st(self).points
	point = supper(point)
	for i = 1, #pts do if pts[i].p == point then table.remove(pts, i) break end end
	invalidate()
end

function Region:ClearPointsOffset()
	for _, p in ipairs(st(self).points) do p.x, p.y = 0, 0 end
	invalidate()
end

function Region:AdjustPointsOffset(dx, dy)
	for _, p in ipairs(st(self).points) do p.x, p.y = p.x + dx, p.y + dy end
	invalidate()
end

function Region:GetNumPoints() return #st(self).points end

function Region:GetPoint(i)
	local s = st(self)
	local p
	if type(i) == "string" then
		for _, q in ipairs(s.points) do if q.p == supper(i) then p = q end end
	else
		p = s.points[i or 1]
	end
	if p then return p.p, p.rel, p.rp, p.x, p.y end
end
Region.GetPointByName = Region.GetPoint

function Region:SetSize(w, h)
	local s = st(self)
	s.w, s.h = w, h or w
	invalidate()
end
function Region:SetWidth(w) st(self).w = w invalidate() end
function Region:SetHeight(h) st(self).h = h invalidate() end

local computeRect -- forward

function Region:GetWidth()
	local s = st(self)
	local l, b, r, t = computeRect(self)
	if l then return (r - l) / SIM.escale(self) end
	return s.w or 0
end
function Region:GetHeight()
	local s = st(self)
	local l, b, r, t = computeRect(self)
	if l then return (t - b) / SIM.escale(self) end
	return s.h or 0
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end

local function edges(self)
	local l, b, r, t = computeRect(self)
	if not l then return end
	local es = SIM.escale(self)
	return l / es, b / es, r / es, t / es
end
function Region:GetLeft() local l = edges(self) return l end
function Region:GetBottom() local _, b = edges(self) return b end
function Region:GetRight() local _, _, r = edges(self) return r end
function Region:GetTop() local _, _, _, t = edges(self) return t end
function Region:GetCenter()
	local l, b, r, t = edges(self)
	if l then return (l + r) / 2, (b + t) / 2 end
end
function Region:GetRect()
	local l, b, r, t = edges(self)
	if l then return l, b, r - l, t - b end
end
function Region:GetScaledRect()
	local l, b, r, t = computeRect(self)
	if l then return l, b, r - l, t - b end
end
function Region:IsRectValid() return computeRect(self) ~= nil end
function Region:IsAnchoringRestricted() return false end
function Region:IsDragging() return SIM.drag and SIM.drag.frame == self or false end
function Region:GetSourceLocation() return nil end

-- Visibility -----------------------------------------------------------
local function isVisible(o)
	local s = S[o]
	while s do
		if not s.shown then return false end
		if s.isRoot then return true end
		local p = s.parent
		if not p then return true end
		s = S[p]
	end
	return true
end
SIM.isVisible = isVisible

local function propagateVisibility(o, visible)
	local s = S[o]
	if s.isFrame then
		runScript(o, visible and "OnShow" or "OnHide")
		if not visible and SIM.focus == o then SIM.setFocus(nil) end
		if not visible and SIM.hover == o then SIM.hover = nil runScript(o, "OnLeave") end
		if s.children then
			for i = 1, #s.children do
				local c = s.children[i]
				if S[c].shown then propagateVisibility(c, visible) end
			end
		end
	end
end

local function setShown(o, flag)
	local s = st(o)
	flag = not not flag
	if s.shown == flag then return end
	local was = isVisible(o)
	s.shown = flag
	invalidate()
	local now = isVisible(o)
	if was ~= now then propagateVisibility(o, now) end
end
SIM.setShown = setShown

function Region:Show() setShown(self, true) end
function Region:Hide() setShown(self, false) end
function Region:SetShown(f) setShown(self, f) end
function Region:IsShown() return st(self).shown end
function Region:IsVisible() return isVisible(self) end

function Region:SetAlpha(a) st(self).alpha = max(0, min(1, tonumber(a) or 1)) end
function Region:GetAlpha() return st(self).alpha end
function Region:GetEffectiveAlpha()
	local a, o = 1, self
	while o do
		local s = S[o]
		a = a * s.alpha * ((s.anim and s.anim.alpha) or 1)
		if s.ignoreParentAlpha then break end
		o = s.parent
	end
	return a
end
function Region:SetIgnoreParentAlpha(f) st(self).ignoreParentAlpha = f end
function Region:IsIgnoringParentAlpha() return st(self).ignoreParentAlpha or false end
function Region:SetIgnoreParentScale(f) st(self).ignoreParentScale = f invalidate() end
function Region:IsIgnoringParentScale() return st(self).ignoreParentScale or false end
function Region:SetScale(sc) st(self).scale = (sc and sc > 0) and sc or 1 invalidate() end
function Region:GetScale() return st(self).scale end
function Region:GetEffectiveScale() return SIM.escale(self) end

function Region:IsMouseOver(top, bottom, left, right)
	local l, b, r, t = computeRect(self)
	if not l then return false end
	local es = SIM.escale(self)
	local x, y = SIM.cursor.x, SIM.cursor.y
	return x >= l - (left or 0) * es and x <= r + (right or 0) * es
		and y >= b - (bottom or 0) * es and y <= t + (top or 0) * es
end
function Region:IsMouseMotionFocus() return SIM.hover == self end

local function detach(o)
	local s = S[o]
	local p = s.parent and S[s.parent]
	if not p then return end
	local list = s.isFrame and p.children or p.regions
	if list then
		for i = 1, #list do if list[i] == o then table.remove(list, i) break end end
	end
end
local function attach(o, parent)
	local s = S[o]
	s.parent = parent
	if not parent then return end
	local p = S[parent]
	if s.isFrame then
		p.children = p.children or {}
		p.children[#p.children + 1] = o
	else
		p.regions = p.regions or {}
		p.regions[#p.regions + 1] = o
	end
end
SIM.attach = attach

function Region:SetParent(parent)
	local s = st(self)
	parent = resolveRel(parent)
	if parent == s.parent then return end
	local was = isVisible(self)
	detach(self)
	attach(self, parent)
	invalidate()
	local now = isVisible(self)
	if s.isFrame and was ~= now then propagateVisibility(self, now) end
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
local function escale(o)
	local s = S[o]
	if s.esStamp == stamp then return s.es end
	local e = s.scale or 1
	if not s.isFrame then e = 1 end
	if s.parent and not s.ignoreParentScale and not s.isRoot then e = e * escale(s.parent) end
	if s.isRoot then e = 1 end
	s.es, s.esStamp = e, stamp
	return e
end
SIM.escale = escale

local measureText -- forward (text layout)

computeRect = function(o)
	local s = S[o]
	if not s then return end
	if s.rectStamp == stamp then
		if s.l then return s.l, s.b, s.r, s.t end
		return
	end
	if s.isRoot then
		s.l, s.b, s.r, s.t, s.rectStamp = 0, 0, SIM.screenW, SIM.screenH, stamp
		return 0, 0, SIM.screenW, SIM.screenH
	end
	if s.computing then return end
	s.computing = true
	local es = escale(o)
	local L, R, CX, B, T, CY
	local pts = s.points
	local ok = #pts > 0
	for i = 1, #pts do
		local p = pts[i]
		local rel = p.rel
		local rl, rb, rr, rt
		if rel == nil then
			rl, rb, rr, rt = 0, 0, SIM.screenW, SIM.screenH
		else
			rl, rb, rr, rt = computeRect(rel)
		end
		if not rl then ok = false break end
		local x = rl + PX[p.rp] * (rr - rl) + p.x * es
		local y = rb + PY[p.rp] * (rt - rb) + p.y * es
		local hx, vy = PX[p.p], PY[p.p]
		if hx == 0 then L = x elseif hx == 1 then R = x else CX = x end
		if vy == 0 then B = y elseif vy == 1 then T = y else CY = y end
	end
	if s.scrollParent then
		local sl, sb, sr, sttop = computeRect(s.scrollParent)
		if sl then
			local ps = S[s.scrollParent]
			local w = (s.w and s.w > 0) and s.w * es or ((L and R) and (R - L)) or (sr - sl)
			local h = (s.h and s.h > 0) and s.h * es or ((T and B) and (T - B)) or 0
			L = sl - (ps.hscroll or 0) * es
			T = sttop + (ps.vscroll or 0) * es
			R, B, CX, CY = L + w, T - h, nil, nil
			ok = true
		end
	end
	if ok then
		local w, h
		if not (L and R) then
			w = s.w
			if (not w or w == 0) and s.isText then w = measureText(o, nil) end
			w = (w or 0) * es
			if L then R = L + w elseif R then L = R - w elseif CX then L = CX - w / 2; R = L + w else ok = false end
		end
		if ok and not (T and B) then
			h = s.h
			if (not h or h == 0) and s.isText then
				local _, th = measureText(o, (R - L) / es)
				h = th
			end
			h = (h or 0) * es
			if T then B = T - h elseif B then T = B + h elseif CY then B = CY - h / 2; T = B + h else ok = false end
		end
	end
	if ok and s.anim then
		local a = s.anim
		if a.dx then L, R = L + a.dx * es, R + a.dx * es end
		if a.dy then B, T = B + a.dy * es, T + a.dy * es end
		if a.sx and (a.sx ~= 1 or a.sy ~= 1) then
			local cx, cy = (L + R) / 2, (B + T) / 2
			L, R = cx - (cx - L) * a.sx, cx + (R - cx) * a.sx
			B, T = cy - (cy - B) * a.sy, cy + (T - cy) * a.sy
		end
	end
	s.computing = false
	s.rectStamp = stamp
	if ok then
		s.l, s.b, s.r, s.t = L, B, R, T
		return L, B, R, T
	end
	s.l, s.b, s.r, s.t = nil, nil, nil, nil
end
SIM.computeRect = computeRect

------------------------------------------------------------------------
-- Text measurement
------------------------------------------------------------------------
local measureCache = {}
local measureCount = 0
local function rawWidth(text, font, size)
	local key = font .. "\1" .. size .. "\1" .. text
	local w = measureCache[key]
	if w then return w end
	w = SIM.py.measure(text, font, size) or (#text * size * 0.55)
	measureCount = measureCount + 1
	if measureCount > 20000 then measureCache = {} measureCount = 0 end
	measureCache[key] = w
	return w
end
SIM.rawWidth = rawWidth

local function plainText(t)
	t = sgsub(t, "||", "\1")
	t = sgsub(t, "|c%x%x%x%x%x%x%x%x", "")
	t = sgsub(t, "|cn[^:]-:", "")
	t = sgsub(t, "|r", "")
	t = sgsub(t, "|H.-|h", "")
	t = sgsub(t, "|h", "")
	t = sgsub(t, "|T.-|t", "\2")
	t = sgsub(t, "|A.-|a", "\2")
	t = sgsub(t, "|K.-|k", "")
	t = sgsub(t, "|n", "\n")
	t = sgsub(t, "\1", "|")
	return t
end
SIM.plainText = plainText

local function lineWidth(line, font, size)
	local icons = 0
	line = sgsub(line, "\2", function() icons = icons + 1 return "" end)
	return rawWidth(line, font, size) + icons * size
end

-- Returns width, height (in the region's own units); wraps at maxW if given.
measureText = function(o, maxW)
	local s = S[o]
	local text = s.text
	if not text or text == "" then return 0, 0 end
	local font, size = SIM.fontOf(s)
	local spacing = s.spacing or 0
	local lineH = size
	local plain = plainText(text)
	local cacheKey = plain .. "\1" .. font .. size .. "\1" .. tostring(maxW) .. tostring(s.wrap) .. (s.maxLines or 0)
	if s.mKey == cacheKey then return s.mW, s.mH, s.mLines end
	local widest, lines = 0, 0
	local wrap = maxW and maxW > 0 and s.wrap ~= false
	for para in string.gmatch(plain .. "\n", "(.-)\n") do
		if not wrap then
			lines = lines + 1
			local w = lineWidth(para, font, size)
			if w > widest then widest = w end
		else
			local cur = ""
			local n = 0
			for word in string.gmatch(para, "%S+") do
				local try = (cur == "") and word or (cur .. " " .. word)
				if cur ~= "" and lineWidth(try, font, size) > maxW + 0.5 then
					n = n + 1
					local w = lineWidth(cur, font, size)
					if w > widest then widest = w end
					cur = word
				else
					cur = try
				end
			end
			n = n + 1
			local w = lineWidth(cur, font, size)
			if w > widest then widest = w end
			lines = lines + n
		end
	end
	if s.maxLines and s.maxLines > 0 and lines > s.maxLines then lines = s.maxLines end
	local h = lines * lineH + (lines - 1) * spacing
	s.mKey, s.mW, s.mH, s.mLines = cacheKey, widest, h, lines
	return widest, h, lines
end
SIM.measureText = measureText

------------------------------------------------------------------------
-- Layered regions, textures, font strings
------------------------------------------------------------------------
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
SIM.LAYERS = LAYERS

local LayeredRegion = defclass("LayeredRegion", "Region")
function LayeredRegion:SetDrawLayer(layer, sub)
	local s = st(self)
	if layer and LAYERS[layer] then s.layer = layer end
	if sub then s.sublevel = sub end
end
function LayeredRegion:GetDrawLayer() local s = st(self) return s.layer, s.sublevel or 0 end
function LayeredRegion:SetVertexColor(r, g, b, a)
	if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
	st(self).vc = { r or 1, g or 1, b or 1, a or 1 }
end
function LayeredRegion:GetVertexColor()
	local v = st(self).vc or { 1, 1, 1, 1 }
	return v[1], v[2], v[3], v[4]
end

local Texture = defclass("Texture", "LayeredRegion")
function Texture:SetTexture(tex, wrapH, wrapV, filter)
	local s = st(self)
	s.color, s.atlas, s.grad = nil, nil, nil
	if tex == nil or tex == "" then s.tex = nil return true end
	s.tex = tex
	return true
end
function Texture:GetTexture() local s = st(self) return s.tex or (s.color and "Color") end
Texture.GetTextureFileID = Texture.GetTexture
Texture.GetTextureFilePath = Texture.GetTexture
function Texture:SetColorTexture(r, g, b, a)
	local s = st(self)
	s.tex, s.atlas, s.grad = nil, nil, nil
	s.color = { r or 1, g or 1, b or 1, a or 1 }
end
function Texture:SetAtlas(atlas, useSize)
	local s = st(self)
	s.atlas, s.tex, s.color = atlas, nil, nil
	if useSize then local w, h = SIM.atlasSize(atlas) if w then s.w, s.h = w, h invalidate() end end
end
function Texture:GetAtlas() return st(self).atlas end
function Texture:SetTexCoord(...)
	local n = select("#", ...)
	local s = st(self)
	if n == 4 then
		local l, r, t, b = ...
		s.tc = { l, r, t, b }
	elseif n == 8 then
		local ulx, uly, llx, lly, urx, ury, lrx, lry = ...
		s.tc = { min(ulx, llx), max(urx, lrx), min(uly, ury), max(lly, lry) }
	end
end
function Texture:GetTexCoord()
	local tc = st(self).tc or { 0, 1, 0, 1 }
	return tc[1], tc[3], tc[1], tc[4], tc[2], tc[3], tc[2], tc[4]
end
function Texture:SetDesaturated(f) st(self).desat = f and 1 or nil end
function Texture:SetDesaturation(v) st(self).desat = (v and v > 0) and v or nil end
function Texture:IsDesaturated() return st(self).desat ~= nil end
function Texture:GetDesaturation() return st(self).desat or 0 end
function Texture:SetBlendMode(m) st(self).blend = m end
function Texture:GetBlendMode() return st(self).blend or "BLEND" end
function Texture:SetRotation(r) st(self).rot = r end
function Texture:GetRotation() return st(self).rot or 0 end
function Texture:SetGradient(orient, c1, c2, ...)
	local s = st(self)
	if type(c1) ~= "table" then -- old signature (orient, r1,g1,b1, r2,g2,b2)
		local a = { c1, c2, ... }
		c1 = { r = a[1], g = a[2], b = a[3], a = 1 }
		c2 = { r = a[4], g = a[5], b = a[6], a = 1 }
	end
	s.grad = { o = orient, a = { c1.r, c1.g, c1.b, c1.a or 1 }, b = { c2.r, c2.g, c2.b, c2.a or 1 } }
end
function Texture:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
	st(self).grad = { o = orient, a = { r1, g1, b1, a1 }, b = { r2, g2, b2, a2 } }
end
function Texture:SetHorizTile(f) st(self).htile = f end
function Texture:SetVertTile(f) st(self).vtile = f end
function Texture:GetHorizTile() return st(self).htile or false end
function Texture:GetVertTile() return st(self).vtile or false end
function Texture:SetMask() end
function Texture:AddMaskTexture() end
function Texture:RemoveMaskTexture() end
function Texture:GetNumMaskTextures() return 0 end
function Texture:SetSnapToPixelGrid() end
function Texture:SetTexelSnappingBias() end
function Texture:SetTextureSliceMargins() end
function Texture:SetTextureSliceMode() end
function Texture:SetNonBlocking() end
function Texture:IsBlockingLoadRequested() return false end
function Texture:SetBlockingLoadsRequested() end
function Texture:ResetTexCoord() st(self).tc = nil end

local Line = defclass("Line", "Texture")
function Line:SetStartPoint(point, rel, x, y)
	if type(rel) == "number" then rel, x, y = nil, rel, x end
	st(self).lineStart = { p = supper(point), rel = resolveRel(rel) or S[self].parent, x = x or 0, y = y or 0 }
end
function Line:SetEndPoint(point, rel, x, y)
	if type(rel) == "number" then rel, x, y = nil, rel, x end
	st(self).lineEnd = { p = supper(point), rel = resolveRel(rel) or S[self].parent, x = x or 0, y = y or 0 }
end
function Line:SetThickness(t) st(self).thick = t end
function Line:GetThickness() return st(self).thick or 1 end

-- Fonts ------------------------------------------------------------------
local FontInstance = defclass("FontInstance")

function SIM.fontOf(s)
	local fs = s
	if not s.fontPath and s.fontObject then fs = S[s.fontObject] or s end
	local path = s.fontPath or fs.fontPath or "Fonts\\FRIZQT__.TTF"
	local size = s.fontSize or fs.fontSize or 12
	return path, size, s.fontFlags or fs.fontFlags or ""
end

local function fontProp(s, key, default)
	local v = s[key]
	if v ~= nil then return v end
	if s.fontObject then
		local f = S[s.fontObject]
		local depth = 0
		while f and depth < 8 do
			if f[key] ~= nil then return f[key] end
			f = f.fontObject and S[f.fontObject]
			depth = depth + 1
		end
	end
	return default
end
SIM.fontProp = fontProp

function FontInstance:SetFont(path, size, flags)
	local s = st(self)
	if type(path) ~= "string" then return false end
	s.fontPath, s.fontSize, s.fontFlags = path, tonumber(size) or 12, flags or ""
	invalidate()
	return true
end
function FontInstance:GetFont()
	local s = st(self)
	local p, sz, fl = SIM.fontOf(s)
	return p, sz, fl
end
function FontInstance:SetFontObject(obj)
	local s = st(self)
	if type(obj) == "string" then obj = _G[obj] end
	s.fontObject = obj
	-- Copy concrete settings so later SetFont on the object does not leak (WoW copies too).
	if obj and S[obj] then
		local f = S[obj]
		local p, sz, fl = SIM.fontOf(f)
		s.fontPath, s.fontSize, s.fontFlags = p, sz, fl
		s.textColor = fontProp(f, "textColor", nil) and { unpack(fontProp(f, "textColor")) } or s.textColor
		s.shadowColor = fontProp(f, "shadowColor", nil)
		s.shadowOffset = fontProp(f, "shadowOffset", nil)
		s.justifyH = s.justifyH or fontProp(f, "justifyH", nil)
	end
	invalidate()
end
function FontInstance:GetFontObject() return st(self).fontObject end
function FontInstance:SetTextColor(r, g, b, a)
	if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
	st(self).textColor = { r or 1, g or 1, b or 1, a or 1 }
end
function FontInstance:GetTextColor()
	local c = fontProp(st(self), "textColor", { 1, 1, 1, 1 })
	return c[1], c[2], c[3], c[4]
end
function FontInstance:SetShadowColor(r, g, b, a) st(self).shadowColor = { r or 0, g or 0, b or 0, a or 1 } end
function FontInstance:GetShadowColor()
	local c = fontProp(st(self), "shadowColor", { 0, 0, 0, 0 })
	return c[1], c[2], c[3], c[4]
end
function FontInstance:SetShadowOffset(x, y) st(self).shadowOffset = { x or 0, y or 0 } end
function FontInstance:GetShadowOffset()
	local o = fontProp(st(self), "shadowOffset", { 0, 0 })
	return o[1], o[2]
end
function FontInstance:SetJustifyH(j) st(self).justifyH = j and supper(j) end
function FontInstance:GetJustifyH() return fontProp(st(self), "justifyH", "CENTER") end
function FontInstance:SetJustifyV(j) st(self).justifyV = j and supper(j) end
function FontInstance:GetJustifyV() return fontProp(st(self), "justifyV", "MIDDLE") end
function FontInstance:SetSpacing(sp) st(self).spacing = sp invalidate() end
function FontInstance:GetSpacing() return st(self).spacing or 0 end
function FontInstance:SetIndentedWordWrap() end
function FontInstance:GetIndentedWordWrap() return false end
function FontInstance:SetFontHeight(h) st(self).fontSize = h invalidate() end
function FontInstance:GetFontHeight() local _, sz = SIM.fontOf(st(self)) return sz end

local Font = defclass("Font", "Object", "FontInstance")
function Font:CopyFontObject(src)
	if type(src) == "string" then src = _G[src] end
	local s, f = st(self), S[src]
	if not f then return end
	local p, sz, fl = SIM.fontOf(f)
	s.fontPath, s.fontSize, s.fontFlags = p, sz, fl
	s.textColor = fontProp(f, "textColor", nil)
	s.shadowColor = fontProp(f, "shadowColor", nil)
	s.shadowOffset = fontProp(f, "shadowOffset", nil)
	s.justifyH = fontProp(f, "justifyH", nil)
end
function Font:SetAlpha(a) st(self).alpha = a end
function Font:GetAlpha() return st(self).alpha end

function CreateFont(name)
	local o, s = newObject("Font", "Font", name)
	s.fontPath, s.fontSize = "Fonts\\FRIZQT__.TTF", 12
	return o
end

local FontString = defclass("FontString", "LayeredRegion", "FontInstance")
function FontString:SetText(t)
	local s = st(self)
	if t == nil then t = "" end
	t = tostring(t)
	if s.text ~= t then s.text = t invalidate() end
end
function FontString:GetText() local t = st(self).text if t == "" then return nil end return t end
function FontString:SetFormattedText(fmt, ...) self:SetText(sformat(fmt, ...)) end
function FontString:GetStringWidth() return (measureText(self, nil)) end
function FontString:GetUnboundedStringWidth() return (measureText(self, nil)) end
function FontString:GetStringHeight()
	local s = st(self)
	local l, b, r = computeRect(self)
	local w = l and (r - l) / escale(self) or nil
	local _, h = measureText(self, w)
	return h
end
function FontString:GetLineHeight() local _, sz = SIM.fontOf(st(self)) return sz end
function FontString:SetWordWrap(f) st(self).wrap = not not f invalidate() end
function FontString:CanWordWrap() return st(self).wrap ~= false end
function FontString:SetNonSpaceWrap(f) st(self).nonSpaceWrap = f end
function FontString:CanNonSpaceWrap() return st(self).nonSpaceWrap or false end
function FontString:SetMaxLines(n) st(self).maxLines = n invalidate() end
function FontString:GetMaxLines() return st(self).maxLines or 0 end
function FontString:GetNumLines()
	local l, b, r = computeRect(self)
	local _, _, n = measureText(self, l and (r - l) / escale(self) or nil)
	return n or 0
end
function FontString:SetTextHeight(h) st(self).fontSize = h invalidate() end
function FontString:IsTruncated()
	local s = st(self)
	local l, b, r, t = computeRect(self)
	if not l then return false end
	local w = measureText(self, nil)
	return w * escale(self) > (r - l) + 0.5
end
function FontString:SetTextScale(sc) st(self).textScale = sc end
function FontString:GetTextScale() return st(self).textScale or 1 end
function FontString:SetTextToFit(t) self:SetText(t) end
function FontString:CalculateScreenAreaFromCharacterSpan() return nil end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local Frame = defclass("Frame", "Region")
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8, BLIZZARD = 9 }
SIM.STRATA = STRATA

local function createRegion(parent, class, otype, name, layer, sub, inherits)
	local o, s = newObject(class, otype, name, parent)
	s.layer = (layer and LAYERS[layer]) and layer or "ARTWORK"
	s.sublevel = sub or 0
	attach(o, parent)
	return o, s
end
SIM.createRegion = createRegion

function Frame:CreateTexture(name, layer, inherits, sub)
	local o, s = createRegion(self, "Texture", "Texture", name, layer, sub)
	if inherits then SIM.applyTemplate(o, inherits) end
	return o
end
function Frame:CreateMaskTexture(name, layer, inherits, sub)
	local o, s = createRegion(self, "Texture", "MaskTexture", name, layer, sub)
	s.isMask = true
	return o
end
function Frame:CreateLine(name, layer, inherits, sub)
	local o, s = createRegion(self, "Line", "Line", name, layer, sub)
	s.isLine = true
	return o
end
function Frame:CreateFontString(name, layer, inherits)
	local o, s = createRegion(self, "FontString", "FontString", name, layer or "ARTWORK")
	s.isText = true
	s.text = ""
	if inherits then
		local fo = type(inherits) == "string" and _G[inherits] or inherits
		if fo and S[fo] and S[fo].otype == "Font" then o:SetFontObject(fo)
		else SIM.applyTemplate(o, inherits) end
	end
	return o
end

-- Events
SIM.eventFrames = {}
function Frame:RegisterEvent(event)
	local s = st(self)
	if type(event) ~= "string" then error("RegisterEvent: bad event", 2) end
	if SIM.knownEvents and next(SIM.knownEvents) and not SIM.knownEvents[event] then
		-- The real client errors here; we only flag it in case the docs are incomplete.
		SIM.noteStub("Unknown event registered: " .. event)
	end
	s.events = s.events or {}
	s.events[event] = true
	local list = SIM.eventFrames[event]
	if not list then list = {} SIM.eventFrames[event] = list end
	for i = 1, #list do if list[i] == self then return true end end
	list[#list + 1] = self
	return true
end
function Frame:RegisterUnitEvent(event, ...)
	self:RegisterEvent(event)
	local s = st(self)
	s.unitFilter = s.unitFilter or {}
	local units = {}
	for i = 1, select("#", ...) do local u = select(i, ...) if u then units[u] = true end end
	s.unitFilter[event] = next(units) and units or nil
	return true
end
function Frame:UnregisterEvent(event)
	local s = st(self)
	if s.events then s.events[event] = nil end
	local list = SIM.eventFrames[event]
	if list then for i = 1, #list do if list[i] == self then table.remove(list, i) break end end end
end
function Frame:UnregisterAllEvents()
	local s = st(self)
	if s.events then for e in pairs(s.events) do self:UnregisterEvent(e) end end
end
function Frame:IsEventRegistered(event) local s = st(self) return s.events and s.events[event] or false end
function Frame:RegisterAllEvents() st(self).allEvents = true end

function SIM.fireEvent(event, ...)
	local list = SIM.eventFrames[event]
	local unit = ...
	if list then
		local copy = {}
		for i = 1, #list do copy[i] = list[i] end
		for i = 1, #copy do
			local f = copy[i]
			local s = S[f]
			if s.events and s.events[event] then
				local filt = s.unitFilter and s.unitFilter[event]
				if not filt or filt[unit] then runScript(f, "OnEvent", event, ...) end
			end
		end
	end
	for _, f in ipairs(frames) do
		if S[f].allEvents then runScript(f, "OnEvent", event, ...) end
	end
	if SIM.eventCallbacks then SIM.eventCallbacks(event, ...) end
end

-- Strata / level
local function effStrata(o)
	local s = S[o]
	while s do
		if s.strata and s.strata ~= "PARENT" then return s.strata end
		if not s.parent then break end
		s = S[s.parent]
	end
	return "MEDIUM"
end
SIM.effStrata = effStrata

local function effLevel(o)
	local s = S[o]
	if s.level then return s.level end
	if s.parent and not S[s.parent].isRoot then return effLevel(s.parent) + 1 end
	return 1
end
SIM.effLevel = effLevel

function Frame:SetFrameStrata(strata)
	if strata and STRATA[strata] or strata == "PARENT" then st(self).strata = strata end
end
function Frame:GetFrameStrata() return effStrata(self) end
function Frame:SetFrameLevel(l) st(self).level = max(0, floor(tonumber(l) or 0)) end
function Frame:GetFrameLevel() return effLevel(self) end
function Frame:SetFixedFrameStrata() end
function Frame:SetFixedFrameLevel() end
function Frame:HasFixedFrameStrata() return false end
function Frame:HasFixedFrameLevel() return false end
function Frame:SetToplevel(f) st(self).toplevel = f end
function Frame:IsToplevel() return st(self).toplevel or false end
function Frame:Raise()
	local s = st(self)
	local strata, top = effStrata(self), 0
	for _, f in ipairs(frames) do
		if f ~= self and effStrata(f) == strata and isVisible(f) then
			local l = effLevel(f)
			if l > top then top = l end
		end
	end
	if effLevel(self) <= top then s.level = top + 1 end
end
function Frame:Lower() st(self).level = 1 end

-- Mouse / keyboard
function Frame:EnableMouse(f) local s = st(self) s.mouse = not not f; s.mouseClick = s.mouse; s.mouseMotion = s.mouse end
function Frame:IsMouseEnabled() return st(self).mouse or false end
function Frame:SetMouseClickEnabled(f) local s = st(self) s.mouseClick = not not f; s.mouse = s.mouseClick or s.mouseMotion end
function Frame:IsMouseClickEnabled() return st(self).mouseClick or false end
function Frame:SetMouseMotionEnabled(f) local s = st(self) s.mouseMotion = not not f; s.mouse = s.mouseClick or s.mouseMotion end
function Frame:IsMouseMotionEnabled() return st(self).mouseMotion or false end
function Frame:EnableMouseWheel(f) st(self).wheel = (f == nil) and true or not not f end
function Frame:IsMouseWheelEnabled() return st(self).wheel or false end
function Frame:SetPassThroughButtons() end
function Frame:EnableKeyboard(f) st(self).keyboard = not not f end
function Frame:IsKeyboardEnabled() return st(self).keyboard or false end
function Frame:SetPropagateKeyboardInput(f) st(self).propagateKeys = f end
function Frame:GetPropagateKeyboardInput() return st(self).propagateKeys or false end
function Frame:EnableGamePadButton() end
function Frame:EnableGamePadStick() end
function Frame:SetHitRectInsets(l, r, t, b) st(self).hitInsets = { l or 0, r or 0, t or 0, b or 0 } end
function Frame:GetHitRectInsets() local h = st(self).hitInsets or { 0, 0, 0, 0 } return h[1], h[2], h[3], h[4] end
function Frame:SetMovable(f) st(self).movable = f end
function Frame:IsMovable() return st(self).movable or false end
function Frame:SetResizable(f) st(self).resizable = f end
function Frame:IsResizable() return st(self).resizable or false end
function Frame:SetUserPlaced(f) st(self).userPlaced = f end
function Frame:IsUserPlaced() return st(self).userPlaced or false end
function Frame:SetDontSavePosition() end
function Frame:SetClampedToScreen(f) st(self).clamped = f end
function Frame:IsClampedToScreen() return st(self).clamped or false end
function Frame:SetClampRectInsets() end
function Frame:SetResizeBounds(minW, minH, maxW, maxH) st(self).bounds = { minW, minH, maxW, maxH } end
function Frame:GetResizeBounds() local b = st(self).bounds or {} return b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 0 end
function Frame:SetMinResize(w, h) local s = st(self) s.bounds = s.bounds or {} s.bounds[1], s.bounds[2] = w, h end
function Frame:SetMaxResize(w, h) local s = st(self) s.bounds = s.bounds or {} s.bounds[3], s.bounds[4] = w, h end
function Frame:RegisterForDrag(...)
	local s = st(self)
	s.dragButtons = {}
	for i = 1, select("#", ...) do
		local b = select(i, ...)
		if b then s.dragButtons[(sgsub(b, "Up$", ""))] = true end
	end
end

function Frame:StartMoving()
	local s = st(self)
	local l, b, r, t = computeRect(self)
	if not l then return end
	SIM.moving = { frame = self, mode = "move", ox = SIM.cursor.x - l, oy = SIM.cursor.y - b }
	s.userPlaced = true
end
function Frame:StartSizing(point)
	local l, b, r, t = computeRect(self)
	if not l then return end
	local p = point and supper(point) or "BOTTOMRIGHT"
	-- Pin the opposite corner so the frame grows toward the cursor.
	local es = escale(self)
	self:ClearAllPoints()
	local anchorP = (PY[p] == 1 and "BOTTOM" or "TOP") .. (PX[p] == 0 and "RIGHT" or "LEFT")
	local ax = (PX[p] == 0) and r or l
	local ay = (PY[p] == 1) and b or t
	self:SetPoint(anchorP, UIParent, "BOTTOMLEFT", ax / es, ay / es)
	SIM.moving = { frame = self, mode = "size", p = p, ax = ax, ay = ay }
end
function Frame:StopMovingOrSizing()
	if SIM.moving and SIM.moving.frame == self then SIM.moving = nil end
end

function Frame:GetChildren()
	local c = st(self).children
	if not c then return end
	return unpack(c)
end
function Frame:GetNumChildren() local c = st(self).children return c and #c or 0 end
function Frame:GetRegions()
	local r = st(self).regions
	if not r then return end
	return unpack(r)
end
function Frame:GetNumRegions() local r = st(self).regions return r and #r or 0 end
function Frame:GetAdditionalRegions() return end

function Frame:SetAttribute(k, v)
	local s = st(self)
	s.attrs = s.attrs or {}
	s.attrs[k] = v
	runScript(self, "OnAttributeChanged", k, v)
end
function Frame:GetAttribute(k) local a = st(self).attrs return a and a[k] end
function Frame:SetAttributeNoHandler(k, v) local s = st(self) s.attrs = s.attrs or {} s.attrs[k] = v end
function Frame:SetID(id) st(self).fid = id end
function Frame:GetID() return st(self).fid or 0 end
function Frame:SetClipsChildren(f) st(self).clips = f end
function Frame:DoesClipChildren() return st(self).clips or false end
function Frame:SetFlattensRenderLayers() end
function Frame:SetFrameBuffer() end
function Frame:SetIsFrameBuffer() end
function Frame:EnableDrawLayer() end
function Frame:DisableDrawLayer() end
function Frame:SetHyperlinksEnabled(f) st(self).hyperlinks = f end
function Frame:GetBoundsRect() return self:GetRect() end
function Frame:CanChangeProtectedState() return true end
function Frame:IsProtected() return false, false end
function Frame:ExecuteAttribute() end
function Frame:GetEffectiveScale() return escale(self) end
function Frame:LockHighlight() st(self).lockHL = true end
function Frame:UnlockHighlight() st(self).lockHL = nil end

-- Backdrop (we give it to every frame; BackdropTemplate just adds the mixin)
function Frame:SetBackdrop(info)
	local s = st(self)
	if not info then s.backdrop = nil return end
	local ins = info.insets or {}
	s.backdrop = {
		bg = info.bgFile, edge = info.edgeFile, tile = info.tile, tileSize = info.tileSize,
		edgeSize = info.edgeSize or 0,
		ins = { ins.left or 0, ins.right or 0, ins.top or 0, ins.bottom or 0 },
	}
	s.bdInfo = info
	s.bgColor = s.bgColor or { 1, 1, 1, 1 }
	s.bdColor = s.bdColor or { 1, 1, 1, 1 }
end
function Frame:GetBackdrop() return st(self).bdInfo end
function Frame:SetBackdropColor(r, g, b, a) st(self).bgColor = { r or 1, g or 1, b or 1, a or 1 } end
function Frame:GetBackdropColor() local c = st(self).bgColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Frame:SetBackdropBorderColor(r, g, b, a) st(self).bdColor = { r or 1, g or 1, b or 1, a or 1 } end
function Frame:GetBackdropBorderColor() local c = st(self).bdColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Frame:ApplyBackdrop()
	if self.backdropInfo then self:SetBackdrop(self.backdropInfo) end
	if self.backdropColor then
		local c = self.backdropColor
		self:SetBackdropColor(c.r, c.g, c.b, self.backdropColorAlpha or c.a or 1)
	end
	if self.backdropBorderColor then
		local c = self.backdropBorderColor
		self:SetBackdropBorderColor(c.r, c.g, c.b, self.backdropBorderColorAlpha or c.a or 1)
	end
end
function Frame:ClearBackdrop() st(self).backdrop = nil end
function Frame:OnBackdropLoaded() self:ApplyBackdrop() end
function Frame:OnBackdropSizeChanged() end
function Frame:SetupTextureCoordinates() end
function Frame:HasBackdropInfo(info) return st(self).bdInfo == info end

------------------------------------------------------------------------
-- Button / CheckButton
------------------------------------------------------------------------
local Button = defclass("Button", "Frame")

local function buttonTexture(self, role, tex, layer)
	local s = st(self)
	s.stateTex = s.stateTex or {}
	local cur = s.stateTex[role]
	if tex == nil or tex == "" then
		if cur then S[cur].roleCleared = true; S[cur].tex = nil; S[cur].color = nil end
		return
	end
	if type(tex) == "table" and S[tex] then
		if cur and cur ~= tex then S[cur].role = nil end
		cur = tex
		if S[cur].parent ~= self then cur:SetParent(self) end
		if #S[cur].points == 0 then cur:SetAllPoints(self) end
	else
		if not cur then
			cur = self:CreateTexture(nil, layer)
			cur:SetAllPoints(self)
		end
		S[cur].roleCleared = nil
		if type(tex) == "number" or type(tex) == "string" then cur:SetTexture(tex) end
	end
	S[cur].role = role
	if role == "highlight" then
		S[cur].layer = "HIGHLIGHT"
		if not S[cur].blend then S[cur].blend = "ADD" end
	end
	s.stateTex[role] = cur
	return cur
end
SIM.buttonTexture = buttonTexture

function Button:SetNormalTexture(t) buttonTexture(self, "normal", t, "ARTWORK") end
function Button:SetPushedTexture(t) buttonTexture(self, "pushed", t, "ARTWORK") end
function Button:SetDisabledTexture(t) buttonTexture(self, "disabled", t, "ARTWORK") end
function Button:SetHighlightTexture(t, mode) local x = buttonTexture(self, "highlight", t, "HIGHLIGHT") if x and mode then S[x].blend = mode end end
function Button:GetNormalTexture() local t = st(self).stateTex return t and t.normal end
function Button:GetPushedTexture() local t = st(self).stateTex return t and t.pushed end
function Button:GetDisabledTexture() local t = st(self).stateTex return t and t.disabled end
function Button:GetHighlightTexture() local t = st(self).stateTex return t and t.highlight end
function Button:SetNormalAtlas(a) local x = buttonTexture(self, "normal", "", "ARTWORK") or buttonTexture(self, "normal", 0, "ARTWORK") if x then x:SetAtlas(a) end end
function Button:SetPushedAtlas(a) local x = buttonTexture(self, "pushed", 0, "ARTWORK") if x then x:SetAtlas(a) end end
function Button:SetHighlightAtlas(a) local x = buttonTexture(self, "highlight", 0, "HIGHLIGHT") if x then x:SetAtlas(a) end end
function Button:SetDisabledAtlas(a) local x = buttonTexture(self, "disabled", 0, "ARTWORK") if x then x:SetAtlas(a) end end
function Button:ClearNormalTexture() buttonTexture(self, "normal", nil) end
function Button:ClearPushedTexture() buttonTexture(self, "pushed", nil) end
function Button:ClearHighlightTexture() buttonTexture(self, "highlight", nil) end
function Button:ClearDisabledTexture() buttonTexture(self, "disabled", nil) end

local function ensureFontString(self)
	local s = st(self)
	if s.fontString then return s.fontString end
	local fs = self:CreateFontString(nil, "OVERLAY")
	fs:SetPoint("CENTER", self, "CENTER", 0, 0)
	fs:SetFontObject(s.normalFont or GameFontNormal)
	s.fontString = fs
	return fs
end
function Button:SetText(t) ensureFontString(self):SetText(t) end
function Button:SetFormattedText(fmt, ...) ensureFontString(self):SetText(sformat(fmt, ...)) end
function Button:GetText() local fs = st(self).fontString return fs and fs:GetText() end
function Button:GetFontString() return st(self).fontString end
function Button:SetFontString(fs) local s = st(self) s.fontString = fs end
function Button:GetTextWidth() local fs = st(self).fontString return fs and fs:GetStringWidth() or 0 end
function Button:GetTextHeight() local fs = st(self).fontString return fs and fs:GetStringHeight() or 0 end
function Button:SetNormalFontObject(f)
	local s = st(self)
	if type(f) == "string" then f = _G[f] end
	s.normalFont = f
	if s.fontString then s.fontString:SetFontObject(f) end
end
function Button:GetNormalFontObject() return st(self).normalFont end
function Button:SetHighlightFontObject(f) if type(f) == "string" then f = _G[f] end st(self).highlightFont = f end
function Button:GetHighlightFontObject() return st(self).highlightFont end
function Button:SetDisabledFontObject(f) if type(f) == "string" then f = _G[f] end st(self).disabledFont = f end
function Button:GetDisabledFontObject() return st(self).disabledFont end
function Button:SetPushedTextOffset(x, y) st(self).pushOffset = { x, y } end
function Button:GetPushedTextOffset() local p = st(self).pushOffset or { 0, 0 } return p[1], p[2] end
function Button:Enable() self:SetEnabled(true) end
function Button:Disable() self:SetEnabled(false) end
function Button:SetEnabled(f)
	local s = st(self)
	f = not not f
	if s.disabled == not f then return end
	s.disabled = not f
	runScript(self, f and "OnEnable" or "OnDisable")
end
function Button:IsEnabled() return not st(self).disabled end
function Button:RegisterForClicks(...)
	local s = st(self)
	s.clicks = {}
	for i = 1, select("#", ...) do local c = select(i, ...) if c then s.clicks[c] = true end end
end
function Button:RegisterForMouse(...) end
function Button:SetButtonState(state, lock) st(self).bstate = state; st(self).bstateLock = lock end
function Button:GetButtonState() return st(self).bstate or "NORMAL" end
function Button:Click(button, down)
	SIM.doClick(self, button or "LeftButton", down or false)
end
function Button:SetMotionScriptsWhileDisabled(f) st(self).motionWhileDisabled = f end
function Button:GetMotionScriptsWhileDisabled() return st(self).motionWhileDisabled or false end

local CheckButton = defclass("CheckButton", "Button")
function CheckButton:SetChecked(f) st(self).checked = not not f end
function CheckButton:GetChecked() return st(self).checked or false end
function CheckButton:SetCheckedTexture(t) buttonTexture(self, "checked", t, "ARTWORK") end
function CheckButton:GetCheckedTexture() local t = st(self).stateTex return t and t.checked end
function CheckButton:SetDisabledCheckedTexture(t) buttonTexture(self, "disabledchecked", t, "ARTWORK") end
function CheckButton:GetDisabledCheckedTexture() local t = st(self).stateTex return t and t.disabledchecked end

------------------------------------------------------------------------
-- EditBox
------------------------------------------------------------------------
local EditBox = defclass("EditBox", "Frame", "FontInstance")
function EditBox:SetText(t)
	local s = st(self)
	t = tostring(t or "")
	if s.maxLetters and s.maxLetters > 0 and #t > s.maxLetters then t = ssub(t, 1, s.maxLetters) end
	if s.text == t then return end
	s.text = t
	s.cursorPos = #t
	s.textRev = (s.textRev or 0) + 1
	runScript(self, "OnTextChanged", false)
end
function EditBox:GetText() return st(self).text or "" end
function EditBox:Insert(t)
	local s = st(self)
	local cur = s.text or ""
	local pos = s.cursorPos or #cur
	s.text = ssub(cur, 1, pos) .. t .. ssub(cur, pos + 1)
	s.cursorPos = pos + #t
	s.textRev = (s.textRev or 0) + 1
	runScript(self, "OnTextChanged", false)
end
function EditBox:SetNumber(n) self:SetText(tostring(n)) end
function EditBox:GetNumber() return tonumber(st(self).text) or 0 end
function EditBox:SetNumeric(f) st(self).numeric = f end
function EditBox:IsNumeric() return st(self).numeric or false end
function EditBox:SetAutoFocus(f) st(self).autoFocus = f end
function EditBox:IsAutoFocus() return st(self).autoFocus ~= false end
function EditBox:SetFocus() SIM.setFocus(self) end
function EditBox:ClearFocus() if SIM.focus == self then SIM.setFocus(nil) end end
function EditBox:HasFocus() return SIM.focus == self end
function EditBox:SetMultiLine(f) st(self).multi = f end
function EditBox:IsMultiLine() return st(self).multi or false end
function EditBox:SetMaxLetters(n) st(self).maxLetters = n end
function EditBox:GetMaxLetters() return st(self).maxLetters or 0 end
function EditBox:SetMaxBytes(n) st(self).maxLetters = n end
function EditBox:GetNumLetters() return #(st(self).text or "") end
function EditBox:HighlightText(a, b) st(self).highlightReq = { a or 0, b or -1 } end
function EditBox:ClearHighlightText() end
function EditBox:SetCursorPosition(p) st(self).cursorPos = p end
function EditBox:GetCursorPosition() return st(self).cursorPos or 0 end
function EditBox:SetTextInsets(l, r, t, b) st(self).insets = { l or 0, r or 0, t or 0, b or 0 } end
function EditBox:GetTextInsets() local i = st(self).insets or { 0, 0, 0, 0 } return i[1], i[2], i[3], i[4] end
function EditBox:SetPassword(f) st(self).password = f end
function EditBox:IsPassword() return st(self).password or false end
function EditBox:SetBlinkSpeed() end
function EditBox:SetAltArrowKeyMode() end
function EditBox:SetHistoryLines() end
function EditBox:AddHistoryLine() end
function EditBox:SetCountInvisibleLetters() end
function EditBox:Enable() st(self).disabled = nil end
function EditBox:Disable() st(self).disabled = true; self:ClearFocus() end
function EditBox:SetEnabled(f) if f then self:Enable() else self:Disable() end end
function EditBox:IsEnabled() return not st(self).disabled end
function EditBox:IsInIMECompositionMode() return false end
function EditBox:GetInputLanguage() return "ROMAN" end
function EditBox:SetSecureText(t) self:SetText(t) end
function EditBox:SetVisibleTextByteLimit() end

function SIM.setFocus(o)
	local old = SIM.focus
	if old == o then return end
	SIM.focus = o
	if old then runScript(old, "OnEditFocusLost") end
	if o then runScript(o, "OnEditFocusGained") end
end

------------------------------------------------------------------------
-- Slider / StatusBar
------------------------------------------------------------------------
local Slider = defclass("Slider", "Frame")
local function setRangeValue(self, v, user)
	local s = st(self)
	local lo, hi = s.min or 0, s.max or 0
	v = tonumber(v) or 0
	if v < lo then v = lo end
	if v > hi then v = hi end
	if user and s.step and s.step > 0 and s.obeyStep ~= false then
		v = lo + floor((v - lo) / s.step + 0.5) * s.step
		if v > hi then v = hi end
	end
	if s.value == v then return end
	s.value = v
	invalidate()
	runScript(self, "OnValueChanged", v, user or false)
end
SIM.setRangeValue = setRangeValue
function Slider:SetMinMaxValues(lo, hi)
	local s = st(self)
	s.min, s.max = lo, hi
	runScript(self, "OnMinMaxChanged", lo, hi)
	if s.value then
		if s.value < lo then setRangeValue(self, lo) elseif s.value > hi then setRangeValue(self, hi) end
	end
	invalidate()
end
function Slider:GetMinMaxValues() local s = st(self) return s.min or 0, s.max or 0 end
function Slider:SetValue(v, treatAsMouse) setRangeValue(self, v, treatAsMouse) end
function Slider:GetValue() return st(self).value or 0 end
function Slider:SetValueStep(v) st(self).step = v end
function Slider:GetValueStep() return st(self).step or 0 end
function Slider:SetObeyStepOnDrag(f) st(self).obeyStep = f end
function Slider:GetObeyStepOnDrag() return st(self).obeyStep or false end
function Slider:SetStepsPerPage(n) st(self).stepsPerPage = n end
function Slider:GetStepsPerPage() return st(self).stepsPerPage or 1 end
function Slider:SetOrientation(o) st(self).orient = o end
function Slider:GetOrientation() return st(self).orient or "HORIZONTAL" end
function Slider:SetThumbTexture(t)
	local s = st(self)
	if type(t) == "table" and S[t] then s.thumb = t
	else
		if not s.thumb then s.thumb = self:CreateTexture(nil, "OVERLAY") s.thumb:SetSize(32, 32) end
		s.thumb:SetTexture(t)
	end
	S[s.thumb].isThumb = self
end
function Slider:GetThumbTexture() return st(self).thumb end
function Slider:Enable() st(self).disabled = nil end
function Slider:Disable() st(self).disabled = true end
function Slider:SetEnabled(f) st(self).disabled = not f end
function Slider:IsEnabled() return not st(self).disabled end
function Slider:IsDraggingThumb() return SIM.sliderDrag == self end

local StatusBar = defclass("StatusBar", "Frame")
function StatusBar:SetMinMaxValues(lo, hi) local s = st(self) s.min, s.max = lo, hi end
function StatusBar:GetMinMaxValues() local s = st(self) return s.min or 0, s.max or 1 end
function StatusBar:SetValue(v)
	local s = st(self)
	v = tonumber(v) or 0
	if s.value ~= v then s.value = v runScript(self, "OnValueChanged", v) end
end
function StatusBar:GetValue() return st(self).value or 0 end
local function barTex(self)
	local s = st(self)
	if not s.barTex then
		s.barTex = self:CreateTexture(nil, "ARTWORK")
		S[s.barTex].isBarFill = self
	end
	return s.barTex
end
function StatusBar:SetStatusBarTexture(t, layer)
	local s = st(self)
	if type(t) == "table" and S[t] then
		s.barTex = t
		S[t].isBarFill = self
	else
		local tx = barTex(self)
		if t then tx:SetTexture(t) end
	end
	if layer then S[s.barTex].layer = layer end
end
function StatusBar:SetStatusBarAtlas(a) barTex(self):SetAtlas(a) end
function StatusBar:GetStatusBarTexture() return barTex(self) end
function StatusBar:SetStatusBarColor(r, g, b, a)
	if type(r) == "table" then r, g, b, a = r.r, r.g, r.b, r.a end
	barTex(self):SetVertexColor(r, g, b, a)
end
function StatusBar:GetStatusBarColor() return barTex(self):GetVertexColor() end
function StatusBar:SetOrientation(o) st(self).orient = o end
function StatusBar:GetOrientation() return st(self).orient or "HORIZONTAL" end
function StatusBar:SetReverseFill(f) st(self).reverse = f end
function StatusBar:GetReverseFill() return st(self).reverse or false end
function StatusBar:SetFillStyle(f) st(self).reverse = (f == "REVERSE") end
function StatusBar:SetRotatesTexture() end
function StatusBar:SetColorFill(r, g, b, a) barTex(self):SetColorTexture(r, g, b, a) end
function StatusBar:SetTimerDuration() end
function StatusBar:SetToTargetValue(v) self:SetValue(v) end
function StatusBar:IsInterpolating() return false end

------------------------------------------------------------------------
-- ScrollFrame
------------------------------------------------------------------------
local ScrollFrame = defclass("ScrollFrame", "Frame")
function ScrollFrame:SetScrollChild(child)
	local s = st(self)
	if s.scrollChild and S[s.scrollChild] then S[s.scrollChild].scrollParent = nil end
	s.scrollChild = child
	if child then
		if S[child].parent ~= self then child:SetParent(self) end
		S[child].scrollParent = self
	end
	invalidate()
end
function ScrollFrame:GetScrollChild() return st(self).scrollChild end
local function scrollRange(self, vertical)
	local s = st(self)
	local c = s.scrollChild
	if not c then return 0 end
	local cl, cb, cr, ct = computeRect(c)
	local l, b, r, t = computeRect(self)
	if not cl or not l then return 0 end
	local es = escale(self)
	if vertical then return max(0, ((ct - cb) - (t - b)) / es) end
	return max(0, ((cr - cl) - (r - l)) / es)
end
function ScrollFrame:GetVerticalScrollRange() return scrollRange(self, true) end
function ScrollFrame:GetHorizontalScrollRange() return scrollRange(self, false) end
function ScrollFrame:SetVerticalScroll(v)
	local s = st(self)
	v = tonumber(v) or 0
	s.vscroll = v
	invalidate()
	runScript(self, "OnVerticalScroll", v)
end
function ScrollFrame:GetVerticalScroll() return st(self).vscroll or 0 end
function ScrollFrame:SetHorizontalScroll(v)
	local s = st(self)
	s.hscroll = tonumber(v) or 0
	invalidate()
	runScript(self, "OnHorizontalScroll", s.hscroll)
end
function ScrollFrame:GetHorizontalScroll() return st(self).hscroll or 0 end
function ScrollFrame:UpdateScrollChildRect() invalidate() end

------------------------------------------------------------------------
-- Cooldown
------------------------------------------------------------------------
local Cooldown = defclass("Cooldown", "Frame")
function Cooldown:SetCooldown(start, duration, modRate)
	local s = st(self)
	if not duration or duration <= 0 then s.cdStart, s.cdDur = nil, nil return end
	s.cdStart, s.cdDur = start, duration
	s.cdPaused = nil
	if not s.shown then setShown(self, true) end
end
function Cooldown:SetCooldownDuration(d, modRate) self:SetCooldown(SIM.now, d) end
function Cooldown:SetCooldownUNIX(start, duration) self:SetCooldown(start - time() + SIM.now, duration) end
function Cooldown:SetCooldownFromDurationObject(d)
	if type(d) == "table" and d.GetStartTime then self:SetCooldown(d:GetStartTime(), d:GetTotalDuration()) end
end
function Cooldown:SetCooldownFromExpirationTime(exp, dur) self:SetCooldown(exp - dur, dur) end
function Cooldown:GetCooldownTimes() local s = st(self) return (s.cdStart or 0) * 1000, (s.cdDur or 0) * 1000 end
function Cooldown:GetCooldownDuration() local s = st(self) return (s.cdDur or 0) * 1000 end
function Cooldown:Clear() local s = st(self) s.cdStart, s.cdDur = nil, nil end
function Cooldown:Pause() st(self).cdPaused = SIM.now end
function Cooldown:Resume()
	local s = st(self)
	if s.cdPaused and s.cdStart then s.cdStart = s.cdStart + (SIM.now - s.cdPaused) end
	s.cdPaused = nil
end
function Cooldown:IsPaused() return st(self).cdPaused ~= nil end
function Cooldown:SetReverse(f) st(self).cdReverse = f end
function Cooldown:GetReverse() return st(self).cdReverse or false end
function Cooldown:SetDrawSwipe(f) st(self).cdNoSwipe = not f end
function Cooldown:GetDrawSwipe() return not st(self).cdNoSwipe end
function Cooldown:SetDrawEdge(f) st(self).cdEdge = f end
function Cooldown:SetDrawBling(f) end
function Cooldown:SetSwipeColor(r, g, b, a) st(self).cdColor = { r, g, b, a or 0.8 } end
function Cooldown:SetSwipeTexture() end
function Cooldown:SetHideCountdownNumbers(f) st(self).cdHideNumbers = f end
function Cooldown:SetCountdownFont() end
function Cooldown:SetEdgeTexture() end
function Cooldown:SetBlingTexture() end
function Cooldown:SetUseCircularEdge() end
function Cooldown:SetCountdownAbbrevThreshold() end
function Cooldown:SetMinimumCountdownDuration() end
function Cooldown:IsCooldownActive()
	local s = st(self)
	return s.cdStart ~= nil and SIM.now < s.cdStart + s.cdDur
end

------------------------------------------------------------------------
-- Message frames
------------------------------------------------------------------------
local MessageFrame = defclass("MessageFrame", "Frame", "FontInstance")
function MessageFrame:AddMessage(text, r, g, b, id, holdTime)
	local s = st(self)
	s.messages = s.messages or {}
	local msgs = s.messages
	msgs[#msgs + 1] = { t = tostring(text), c = { r or 1, g or 1, b or 1 }, at = SIM.now }
	local cap = s.maxLines or 128
	while #msgs > cap do table.remove(msgs, 1) end
	if s.isChat then SIM.chat(tostring(text), r, g, b, s.name) end
end
function MessageFrame:Clear() st(self).messages = {} end
function MessageFrame:SetFading(f) st(self).fading = f end
function MessageFrame:GetFading() return st(self).fading ~= false end
function MessageFrame:SetTimeVisible(t) st(self).timeVisible = t end
function MessageFrame:GetTimeVisible() return st(self).timeVisible or 10 end
function MessageFrame:SetFadeDuration(t) st(self).fadeDuration = t end
function MessageFrame:SetInsertMode(m) st(self).insertMode = m end
function MessageFrame:GetInsertMode() return st(self).insertMode or "BOTTOM" end
function MessageFrame:SetMaxLines(n) st(self).maxLines = n end
function MessageFrame:GetMaxLines() return st(self).maxLines or 128 end
function MessageFrame:GetNumMessages() local m = st(self).messages return m and #m or 0 end
function MessageFrame:ScrollUp() end
function MessageFrame:ScrollDown() end
function MessageFrame:ScrollToBottom() end
function MessageFrame:ScrollToTop() end
function MessageFrame:PageUp() end
function MessageFrame:PageDown() end
function MessageFrame:SetScrollOffset() end
function MessageFrame:GetScrollOffset() return 0 end
function MessageFrame:AtBottom() return true end
function MessageFrame:BackFillMessage(...) self:AddMessage(...) end
function MessageFrame:RemoveMessagesByPredicate() end
function MessageFrame:SetIndentedWordWrap() end
function MessageFrame:SetOnDisplayRefreshedCallback() end
function MessageFrame:AddMsg(...) self:AddMessage(...) end
defclass("ScrollingMessageFrame", "MessageFrame")

------------------------------------------------------------------------
-- Animation groups
------------------------------------------------------------------------
local AnimGroup = defclass("AnimationGroup", "ScriptObject")
local Anim = defclass("Animation", "ScriptObject")
local playing = {}
SIM.playingAnims = playing

function Region:CreateAnimationGroup(name, inherits)
	local o, s = newObject("AnimationGroup", "AnimationGroup", name, self)
	s.anims, s.looping = {}, "NONE"
	local ps = st(self)
	ps.animGroups = ps.animGroups or {}
	ps.animGroups[#ps.animGroups + 1] = o
	return o
end
function Region:GetAnimationGroups() local g = st(self).animGroups if g then return unpack(g) end end
function Region:StopAnimating()
	local g = st(self).animGroups
	if g then for _, a in ipairs(g) do a:Stop() end end
end

function AnimGroup:CreateAnimation(atype, name, inherits)
	local o, s = newObject("Animation", atype or "Animation", name, self)
	s.atype = atype or "Animation"
	s.duration, s.delay, s.endDelay, s.order = 0, 0, 0, 1
	local gs = st(self)
	gs.anims[#gs.anims + 1] = o
	return o
end
function AnimGroup:GetAnimations() return unpack(st(self).anims) end
function AnimGroup:SetLooping(l) st(self).looping = l or "NONE" end
function AnimGroup:GetLooping() return st(self).looping end
function AnimGroup:SetToFinalAlpha(f) st(self).toFinal = f end
function AnimGroup:IsSetToFinalAlpha() return st(self).toFinal or false end
function AnimGroup:IsPlaying() return playing[self] ~= nil and not st(self).paused end
function AnimGroup:IsPaused() return st(self).paused or false end
function AnimGroup:IsDone() return st(self).done or false end
function AnimGroup:IsPendingFinish() return false end
function AnimGroup:IsReverse() return st(self).reverse or false end
function AnimGroup:SetPlaying(f) if f then self:Play() else self:Stop() end end
function AnimGroup:GetDuration()
	local total, orders = 0, {}
	for _, a in ipairs(st(self).anims) do
		local as = S[a]
		local d = as.delay + as.duration + as.endDelay
		orders[as.order] = max(orders[as.order] or 0, d)
	end
	for _, d in pairs(orders) do total = total + d end
	return total
end
function AnimGroup:GetProgress()
	local s = st(self)
	local d = self:GetDuration()
	if d <= 0 or not s.t then return 0 end
	return min(1, s.t / d)
end
function AnimGroup:GetElapsed() return st(self).t or 0 end
function AnimGroup:Play(reverse, offset)
	local s = st(self)
	if s.paused then s.paused = nil return end
	s.t, s.done, s.reverse, s.bounceBack = offset or 0, false, reverse, false
	playing[self] = true
	runScript(self, "OnPlay")
	SIM.applyGroup(self)
end
function AnimGroup:Restart(reverse, offset) self:Stop() self:Play(reverse, offset) end
function AnimGroup:Pause() st(self).paused = true end
function AnimGroup:Stop()
	if not playing[self] then return end
	playing[self] = nil
	SIM.clearGroup(self)
	runScript(self, "OnStop", false)
end
function AnimGroup:Finish()
	if not playing[self] then return end
	playing[self] = nil
	SIM.clearGroup(self, true)
	st(self).done = true
	runScript(self, "OnFinished", false)
end
function AnimGroup:RemoveAnimations() st(self).anims = {} end
function AnimGroup:SetAnimationSpeedMultiplier() end
function AnimGroup:GetAnimationSpeedMultiplier() return 1 end

function Anim:SetDuration(d) st(self).duration = d or 0 end
function Anim:GetDuration() return st(self).duration end
function Anim:SetStartDelay(d) st(self).delay = d or 0 end
function Anim:GetStartDelay() return st(self).delay end
function Anim:SetEndDelay(d) st(self).endDelay = d or 0 end
function Anim:GetEndDelay() return st(self).endDelay end
function Anim:SetOrder(o) st(self).order = o or 1 end
function Anim:GetOrder() return st(self).order end
function Anim:SetSmoothing(sm) st(self).smoothing = sm end
function Anim:GetSmoothing() return st(self).smoothing or "NONE" end
function Anim:SetSmoothProgress() end
function Anim:SetTarget(t) st(self).target = t end
function Anim:GetTarget() local s = st(self) return s.target or S[s.parent].parent end
function Anim:SetTargetKey(k) local s = st(self) local owner = S[s.parent].parent s.target = owner and owner[k] end
function Anim:SetChildKey(k) self:SetTargetKey(k) end
function Anim:SetTargetName(n) st(self).target = _G[n] end
function Anim:SetTargetParent() local s = st(self) local owner = S[s.parent].parent s.target = owner and S[owner].parent end
function Anim:GetProgress() return st(self).progress or 0 end
function Anim:GetSmoothProgress() return st(self).progress or 0 end
function Anim:GetElapsed() return 0 end
function Anim:IsPlaying() return (st(self).progress or 0) > 0 and (st(self).progress or 0) < 1 end
function Anim:IsDone() return (st(self).progress or 0) >= 1 end
function Anim:IsStopped() return not playing[S[self].parent] end
function Anim:IsDelaying() return false end
function Anim:Play() local g = S[self].parent if g then g:Play() end end
function Anim:Stop() end
function Anim:Pause() end
function Anim:GetRegionParent() local s = st(self) return S[s.parent].parent end
-- Alpha
function Anim:SetFromAlpha(a) st(self).fromA = a end
function Anim:SetToAlpha(a) st(self).toA = a end
function Anim:GetFromAlpha() return st(self).fromA or 0 end
function Anim:GetToAlpha() return st(self).toA or 1 end
function Anim:SetChange(c) local s = st(self) s.fromA, s.toA = 1, 1 + c end
-- Translation
function Anim:SetOffset(x, y) local s = st(self) s.ox, s.oy = x or 0, y or 0 end
function Anim:GetOffset() local s = st(self) return s.ox or 0, s.oy or 0 end
-- Scale
function Anim:SetScale(x, y) local s = st(self) s.fromS, s.toS = { 1, 1 }, { x or 1, y or x or 1 } end
function Anim:SetScaleFrom(x, y) st(self).fromS = { x or 1, y or x or 1 } end
function Anim:SetScaleTo(x, y) st(self).toS = { x or 1, y or x or 1 } end
Anim.SetFromScale = Anim.SetScaleFrom
Anim.SetToScale = Anim.SetScaleTo
function Anim:SetOrigin() end
function Anim:GetScale() local s = st(self) local t = s.toS or { 1, 1 } return t[1], t[2] end
-- Rotation
function Anim:SetDegrees(d) st(self).deg = d end
function Anim:GetDegrees() return st(self).deg or 0 end
function Anim:SetRadians(r) st(self).deg = math.deg(r) end
function Anim:GetRadians() return math.rad(st(self).deg or 0) end
-- Vertex color
function Anim:SetStartColor(c) st(self).startColor = c end
function Anim:SetEndColor(c) st(self).endColor = c end
-- Flipbook etc: harmless defaults come from doc stubs.

local function ease(sm, p)
	if sm == "IN" then return p * p
	elseif sm == "OUT" then return 1 - (1 - p) * (1 - p)
	elseif sm == "IN_OUT" then return p < 0.5 and 2 * p * p or 1 - 2 * (1 - p) * (1 - p) end
	return p
end

function SIM.clearGroup(g, final)
	local gs = S[g]
	for _, a in ipairs(gs.anims) do
		local as = S[a]
		local target = a:GetTarget()
		if target and S[target] then
			local ts = S[target]
			if final and gs.toFinal and as.atype == "Alpha" and as.toA then
				ts.alpha = as.toA
			end
			ts.anim = nil
		end
		as.progress = 0
	end
	invalidate()
end

function SIM.applyGroup(g)
	local gs = S[g]
	local targets = {}
	-- order -> {start, length}
	local orders, keys = {}, {}
	for _, a in ipairs(gs.anims) do
		local as = S[a]
		local d = as.delay + as.duration + as.endDelay
		if not orders[as.order] then orders[as.order] = 0 keys[#keys + 1] = as.order end
		orders[as.order] = max(orders[as.order], d)
	end
	tsort(keys)
	local starts, acc = {}, 0
	for _, k in ipairs(keys) do starts[k] = acc acc = acc + orders[k] end
	local t = gs.t or 0
	if gs.reverse or gs.bounceBack then t = acc - t end
	for _, a in ipairs(gs.anims) do
		local as = S[a]
		local target = a:GetTarget()
		if target and S[target] then
			local local_t = t - starts[as.order] - as.delay
			local p
			if local_t < 0 then p = nil
			elseif as.duration <= 0 then p = 1
			else p = min(1, local_t / as.duration) end
			local prevProgress = as.progress or 0
			as.progress = p or 0
			if p then
				p = ease(as.smoothing, p)
				local ts = S[target]
				local an = targets[target]
				if not an then an = { alpha = 1, dx = 0, dy = 0, sx = 1, sy = 1, rot = 0 } targets[target] = an end
				local at = as.atype
				if at == "Alpha" then
					local from, to = as.fromA or 0, as.toA or 1
					an.alpha = an.alpha * (from + (to - from) * p) / max(ts.alpha, 0.0001)
				elseif at == "Translation" then
					an.dx = an.dx + (as.ox or 0) * p
					an.dy = an.dy + (as.oy or 0) * p
				elseif at == "Scale" then
					local f, to = as.fromS or { 1, 1 }, as.toS or { 1, 1 }
					an.sx = an.sx * (f[1] + (to[1] - f[1]) * p)
					an.sy = an.sy * (f[2] + (to[2] - f[2]) * p)
				elseif at == "Rotation" then
					an.rot = an.rot + math.rad(as.deg or 0) * p
				end
				if prevProgress < 1 and (as.progress or 0) >= 1 then runScript(a, "OnFinished") end
			end
		end
	end
	for target, an in pairs(targets) do S[target].anim = an end
	invalidate()
	return acc
end

local function tickAnims(dt)
	for g in pairs(playing) do
		local gs = S[g]
		if not gs.paused then
			gs.t = (gs.t or 0) + dt
			local total = g:GetDuration()
			if gs.t >= total then
				if gs.looping == "REPEAT" then
					gs.t = (total > 0) and (gs.t % total) or 0
					runScript(g, "OnLoop", "FORWARD")
				elseif gs.looping == "BOUNCE" then
					gs.t = (total > 0) and (gs.t % total) or 0
					gs.bounceBack = not gs.bounceBack
					runScript(g, "OnLoop", gs.bounceBack and "REVERSE" or "FORWARD")
				else
					gs.t = total
					SIM.applyGroup(g)
					playing[g] = nil
					SIM.clearGroup(g, true)
					gs.done = true
					runScript(g, "OnFinished", false)
				end
			end
			if playing[g] then
				SIM.applyGroup(g)
				runScript(g, "OnUpdate", dt)
			end
		end
	end
end

------------------------------------------------------------------------
-- CreateFrame
------------------------------------------------------------------------
local FRAME_TYPES = {
	Frame = "Frame", Button = "Button", CheckButton = "CheckButton", EditBox = "EditBox",
	Slider = "Slider", StatusBar = "StatusBar", ScrollFrame = "ScrollFrame", Cooldown = "Cooldown",
	GameTooltip = "GameTooltip", MessageFrame = "MessageFrame", ScrollingMessageFrame = "ScrollingMessageFrame",
	Model = "Frame", PlayerModel = "Frame", DressUpModel = "Frame", ModelScene = "Frame", CinematicModel = "Frame",
	ColorSelect = "Frame", SimpleHTML = "Frame", Browser = "Frame", Minimap = "Frame", MovieFrame = "Frame",
	OffScreenFrame = "Frame", ArchaeologyDigSiteFrame = "Frame", QuestPOIFrame = "Frame", ScenarioPOIFrame = "Frame",
	UnitPositionFrame = "Frame", FogOfWarFrame = "Frame", TabardModel = "Frame", ItemButton = "Button",
	ContainedAlertFrame = "Frame", DropdownButton = "Button", EventFrame = "Frame", EventButton = "Button",
	EventEditBox = "EditBox", EventScrollFrame = "ScrollFrame", Line = "Frame", ScrollingMessageFrame2 = "ScrollingMessageFrame",
	CheckBox = "CheckButton",
}
SIM.FRAME_TYPES = FRAME_TYPES

function CreateFrame(ftype, name, parent, template, id)
	if type(ftype) ~= "string" then error("CreateFrame: Unknown frame type '" .. tostring(ftype) .. "'", 2) end
	local norm
	for k, v in pairs(FRAME_TYPES) do if slower(k) == slower(ftype) then norm = k break end end
	if not norm then error("CreateFrame: Unknown frame type '" .. ftype .. "'", 2) end
	local class = FRAME_TYPES[norm]
	if type(parent) == "string" then parent = _G[parent] end
	if parent ~= nil and not S[parent] then error("CreateFrame: parent is not a frame", 2) end
	local o, s = newObject(class, norm, name, parent)
	s.isFrame = true
	frames[#frames + 1] = o
	attach(o, parent)
	if class == "Button" or class == "CheckButton" or class == "EditBox" or class == "Slider" then
		s.mouse, s.mouseClick, s.mouseMotion = true, true, true
	end
	if class == "EditBox" then
		s.text, s.autoFocus = "", true
		s.fontObject = ChatFontNormal
	end
	if class == "Slider" then s.min, s.max, s.value = 0, 0, 0 end
	if class == "StatusBar" then s.min, s.max, s.value = 0, 1, 0 end
	if id then s.fid = id end
	if template then SIM.applyTemplate(o, template) end
	invalidate()
	if class == "EditBox" and s.autoFocus ~= false and isVisible(o) and SIM.loadingDone then
		-- WoW focuses auto-focus edit boxes when shown; skip during load to avoid stealing.
	end
	pcallSafe(function() if s.scripts.OnLoad then end end)
	return o
end

function SIM.createRoot(name)
	local o, s = newObject("Frame", "Frame", name, nil)
	s.isFrame, s.isRoot = true, true
	frames[#frames + 1] = o
	return o
end

------------------------------------------------------------------------
-- Tick: timers, OnUpdate, animations, cooldown finish
------------------------------------------------------------------------
SIM.timers = {}
function SIM.addTimer(t)
	SIM.timers[#SIM.timers + 1] = t
end

local function tickTimers()
	local now = SIM.now
	local due = {}
	local keep = {}
	for _, t in ipairs(SIM.timers) do
		if t.cancelled then
		elseif t.at <= now then due[#due + 1] = t
		else keep[#keep + 1] = t end
	end
	SIM.timers = keep
	tsort(due, function(a, b) return a.at < b.at end)
	for _, t in ipairs(due) do
		if not t.cancelled then
			pcallSafe(t.fn, t.handle)
			if t.iterations then
				t.iterations = t.iterations - 1
				if t.iterations > 0 and not t.cancelled then
					t.at = now + t.interval
					SIM.timers[#SIM.timers + 1] = t
				else
					t.cancelled = true
				end
			elseif t.interval and not t.cancelled then
				t.at = now + t.interval
				SIM.timers[#SIM.timers + 1] = t
			else
				t.cancelled = true
			end
		end
	end
end

local scrollRanges = {}
function SIM.tick(dt)
	if dt > 0.5 then dt = 0.5 end
	SIM.now = SIM.now + dt
	tickTimers()
	local list = {}
	for o in pairs(updateList) do list[#list + 1] = o end
	tsort(list, function(a, b) return S[a].id < S[b].id end)
	for i = 1, #list do
		local o = list[i]
		if updateList[o] and isVisible(o) then runScript(o, "OnUpdate", dt) end
	end
	tickAnims(dt)
	-- Cooldown completion and scroll range notifications.
	for _, f in ipairs(frames) do
		local s = S[f]
		if s.cdStart and not s.cdPaused and SIM.now >= s.cdStart + s.cdDur then
			s.cdStart, s.cdDur = nil, nil
			runScript(f, "OnCooldownDone")
		end
		if s.scrollChild and isVisible(f) then
			local yr = scrollRange(f, true)
			local xr = scrollRange(f, false)
			local key = xr .. ":" .. yr
			if scrollRanges[f] ~= key then
				scrollRanges[f] = key
				runScript(f, "OnScrollRangeChanged", xr, yr)
			end
		end
	end
	if SIM.afterTick then SIM.afterTick(dt) end
end

------------------------------------------------------------------------
-- Clicking, hit testing, input
------------------------------------------------------------------------
local function sortedVisibleFrames()
	local list = {}
	for _, f in ipairs(frames) do
		local s = S[f]
		if not s.isRoot and isVisible(f) then list[#list + 1] = f end
	end
	local keyS, keyL = {}, {}
	for _, f in ipairs(list) do keyS[f] = STRATA[effStrata(f)] or 3; keyL[f] = effLevel(f) end
	tsort(list, function(a, b)
		if keyS[a] ~= keyS[b] then return keyS[a] < keyS[b] end
		if keyL[a] ~= keyL[b] then return keyL[a] < keyL[b] end
		return S[a].id < S[b].id
	end)
	return list
end
SIM.sortedVisibleFrames = sortedVisibleFrames

-- Clip rect inherited from scroll frames / clipping parents.
local function clipOf(o, cache)
	local s = S[o]
	local c = cache[o]
	if c ~= nil then return c or nil end
	local result = false
	local p = s.parent
	if p and not S[p].isRoot then
		local pc = clipOf(p, cache)
		local ps = S[p]
		if ps.otype == "ScrollFrame" or ps.clips then
			local l, b, r, t = computeRect(p)
			if l then
				if pc then
					l, b, r, t = max(l, pc[1]), max(b, pc[2]), min(r, pc[3]), min(t, pc[4])
				end
				result = { l, b, r, t }
			else
				result = pc or false
			end
		else
			result = pc or false
		end
	end
	cache[o] = result
	return result or nil
end
SIM.clipOf = clipOf

local function hitTest(x, y, filter)
	local list = sortedVisibleFrames()
	local cache = {}
	for i = #list, 1, -1 do
		local f = list[i]
		local s = S[f]
		if filter(f, s) then
			local l, b, r, t = computeRect(f)
			if l then
				local es = escale(f)
				local h = s.hitInsets
				if h then l, r, t, b = l + h[1] * es, r - h[2] * es, t - h[3] * es, b + h[4] * es end
				local c = clipOf(f, cache)
				if c then l, b, r, t = max(l, c[1]), max(b, c[2]), min(r, c[3]), min(t, c[4]) end
				if x >= l and x <= r and y >= b and y <= t then return f end
			end
		end
	end
end
SIM.hitTest = hitTest

local function mouseFilter(f, s) return s.mouse and (s.mouseMotion ~= false or s.mouseClick) end
local function wheelFilter(f, s) return s.wheel end

function SIM.doClick(f, button, down)
	local s = S[f]
	if s.disabled then return end
	if s.otype == "CheckButton" then s.checked = not s.checked end
	runScript(f, "PreClick", button, down)
	runScript(f, "OnClick", button, down)
	if SIM.secureClick then SIM.secureClick(f, button) end
	runScript(f, "PostClick", button, down)
end

local function clickAllowed(s, button, down)
	local c = s.clicks
	if not c then return (button == "LeftButton") and not down end
	if c.AnyUp and not down then return true end
	if c.AnyDown and down then return true end
	return c[button .. (down and "Down" or "Up")] or false
end

local function setHover(f)
	if SIM.hover == f then return end
	local old = SIM.hover
	SIM.hover = f
	if old and S[old] then
		local os_ = S[old]
		if not os_.disabled or os_.motionWhileDisabled or os_.otype ~= "Button" then runScript(old, "OnLeave", true) end
	end
	if f then
		local fs = S[f]
		if not fs.disabled or fs.motionWhileDisabled or (fs.otype ~= "Button" and fs.otype ~= "CheckButton") then
			runScript(f, "OnEnter", true)
		end
	end
end

local function sliderSetFromCursor(f)
	local s = S[f]
	local l, b, r, t = computeRect(f)
	if not l then return end
	local lo, hi = s.min or 0, s.max or 0
	local frac
	if (s.orient or "HORIZONTAL") == "VERTICAL" then
		frac = (t - SIM.cursor.y) / max(1, t - b)
	else
		frac = (SIM.cursor.x - l) / max(1, r - l)
	end
	frac = max(0, min(1, frac))
	setRangeValue(f, lo + (hi - lo) * frac, true)
end

function SIM.mouseMove(x, y)
	SIM.cursor.x, SIM.cursor.y = x, y
	local mv = SIM.moving
	if mv and S[mv.frame] then
		local f = mv.frame
		local es = escale(f)
		if mv.mode == "move" then
			local l, b, r, t = computeRect(f)
			local w, h = l and (r - l) or 0, l and (t - b) or 0
			local nl, nb = x - mv.ox, y - mv.oy
			if S[f].clamped then
				nl = max(0, min(SIM.screenW - w, nl))
				nb = max(0, min(SIM.screenH - h, nb))
			end
			f:ClearAllPoints()
			f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nl / es, nb / es)
		else
			local s = S[f]
			local w = abs(x - mv.ax) / es
			local h = abs(y - mv.ay) / es
			local bd = s.bounds or {}
			if bd[1] and bd[1] > 0 then w = max(w, bd[1]) end
			if bd[2] and bd[2] > 0 then h = max(h, bd[2]) end
			if bd[3] and bd[3] > 0 then w = min(w, bd[3]) end
			if bd[4] and bd[4] > 0 then h = min(h, bd[4]) end
			f:SetSize(w, h)
			runScript(f, "OnSizeChanged", w, h)
		end
	end
	if SIM.sliderDrag and S[SIM.sliderDrag] then sliderSetFromCursor(SIM.sliderDrag) end
	local pd = SIM.pendingDrag
	if pd and not SIM.drag then
		if abs(x - pd.x) + abs(y - pd.y) > 4 then
			SIM.drag = { frame = pd.frame, button = pd.button }
			SIM.pendingDrag = nil
			runScript(pd.frame, "OnDragStart", pd.button)
		end
	end
	if not SIM.mouseState or SIM.drag then
		setHover(hitTest(x, y, mouseFilter))
	end
end

function SIM.mouseDown(x, y, button)
	SIM.mouseMove(x, y)
	local f = hitTest(x, y, mouseFilter)
	SIM.mouseState = { frame = f, button = button }
	if SIM.focus and SIM.focus ~= f then SIM.setFocus(nil) end
	if not f then return end
	local s = S[f]
	runScript(f, "OnMouseDown", button)
	if s.otype == "Button" or s.otype == "CheckButton" then
		if not s.disabled then s.pushed = true end
		if clickAllowed(s, button, true) then SIM.doClick(f, button, true) end
	elseif s.otype == "EditBox" then
		if not s.disabled then SIM.setFocus(f) end
	elseif s.otype == "Slider" and not s.disabled then
		SIM.sliderDrag = f
		sliderSetFromCursor(f)
	end
	if s.dragButtons and s.dragButtons[button] then
		SIM.pendingDrag = { frame = f, button = button, x = x, y = y }
	end
end

function SIM.mouseUp(x, y, button)
	SIM.cursor.x, SIM.cursor.y = x, y
	local md = SIM.mouseState
	SIM.mouseState = nil
	SIM.pendingDrag = nil
	SIM.sliderDrag = nil
	if SIM.drag then
		local d = SIM.drag
		SIM.drag = nil
		runScript(d.frame, "OnDragStop")
		if SIM.moving and SIM.moving.frame == d.frame then SIM.moving = nil end
		if md and md.frame and S[md.frame] then S[md.frame].pushed = nil runScript(md.frame, "OnMouseUp", button, true) end
		setHover(hitTest(x, y, mouseFilter))
		return
	end
	local f = md and md.frame
	if f and S[f] then
		local s = S[f]
		local wasPushed = s.pushed
		s.pushed = nil
		local over = hitTest(x, y, mouseFilter) == f
		runScript(f, "OnMouseUp", button, over)
		if (s.otype == "Button" or s.otype == "CheckButton") and over and clickAllowed(s, button, false) then
			SIM.doClick(f, button, false)
		end
	end
	setHover(hitTest(x, y, mouseFilter))
end

function SIM.mouseWheel(x, y, delta)
	SIM.cursor.x, SIM.cursor.y = x, y
	local f = hitTest(x, y, wheelFilter)
	if f then runScript(f, "OnMouseWheel", delta) end
end

-- Keyboard: keys arrive as WoW names (ENTER, ESCAPE, TAB, A, ...)
SIM.specialFrames = {}
function SIM.keyDown(key)
	local fo = SIM.focus
	if fo and S[fo] then
		if key == "ENTER" then
			if not S[fo].multi then runScript(fo, "OnEnterPressed") end
			return
		elseif key == "ESCAPE" then
			runScript(fo, "OnEscapePressed")
			return
		elseif key == "TAB" then
			runScript(fo, "OnTabPressed")
			return
		elseif key == "SPACE" then
			runScript(fo, "OnSpacePressed")
		end
		runScript(fo, "OnKeyDown", key)
		return
	end
	local list = sortedVisibleFrames()
	for i = #list, 1, -1 do
		local f = list[i]
		if S[f].keyboard then
			runScript(f, "OnKeyDown", key)
			if not S[f].propagateKeys then return end
		end
	end
	if key == "ESCAPE" then
		if SIM.closeSpecialFrames then SIM.closeSpecialFrames() end
	end
end
function SIM.keyUp(key)
	local fo = SIM.focus
	if fo and S[fo] then runScript(fo, "OnKeyUp", key) return end
	local list = sortedVisibleFrames()
	for i = #list, 1, -1 do
		local f = list[i]
		if S[f].keyboard then
			runScript(f, "OnKeyUp", key)
			if not S[f].propagateKeys then return end
		end
	end
end

-- Text typed into a focused edit box from the browser.
function SIM.editText(id, text, cursor)
	local f = byId[id]
	if not f or not S[f] then return end
	local s = S[f]
	if s.numeric then text = sgsub(text, "[^%d]", "") end
	if s.maxLetters and s.maxLetters > 0 and #text > s.maxLetters then text = ssub(text, 1, s.maxLetters) end
	local old = s.text or ""
	if old == text then return end
	if #text == #old + 1 then
		local ch = ssub(text, (cursor or #text), (cursor or #text))
		runScript(f, "OnChar", ch)
	end
	s.text = text
	s.cursorPos = cursor or #text
	runScript(f, "OnTextChanged", true)
end
