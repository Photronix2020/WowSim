-- WowSim: turns the live frame tree into a flat, ordered draw list for the browser.

local SIM = __SIM
local S = SIM.S
local computeRect, escale, isVisible, clipOf = SIM.computeRect, SIM.escale, SIM.isVisible, SIM.clipOf
local LAYERS = SIM.LAYERS
local max, min, floor = math.max, math.min, math.floor
local tsort, ipairs, pairs, type = table.sort, ipairs, pairs, type

local function effAlpha(o)
	local a = 1
	while o do
		local s = S[o]
		a = a * s.alpha * ((s.anim and s.anim.alpha) or 1)
		if s.ignoreParentAlpha or s.isRoot then break end
		o = s.parent
	end
	return a
end
SIM.effAlpha = effAlpha

local function r1(v) return floor(v * 10 + 0.5) / 10 end

local function box(item, l, b, r, t)
	local H = SIM.screenH
	item.x, item.y, item.w, item.h = r1(l), r1(H - t), r1(r - l), r1(t - b)
	return item
end

local function clipArr(c)
	if not c then return nil end
	local H = SIM.screenH
	return { r1(c[1]), r1(H - c[4]), r1(c[3] - c[1]), r1(c[4] - c[2]) }
end

-- Which state textures of a button are showing right now.
local function roleVisible(f, fs, role)
	local tex = fs.stateTex or {}
	local hovered = (SIM.hover == f) or fs.lockHL
	local pushed = fs.pushed or fs.bstate == "PUSHED"
	if role == "normal" then
		if fs.disabled and tex.disabled and not S[tex.disabled].roleCleared then return false end
		if pushed and tex.pushed and not S[tex.pushed].roleCleared then return false end
		return true
	elseif role == "pushed" then return pushed and not fs.disabled
	elseif role == "disabled" then return fs.disabled
	elseif role == "highlight" then return hovered and not fs.disabled
	elseif role == "checked" then
		if not fs.checked then return false end
		if fs.disabled and tex.disabledchecked then return false end
		return true
	elseif role == "disabledchecked" then return fs.checked and fs.disabled
	end
	return true
end

local function fontColor(f, fs, rs)
	-- Buttons swap font objects with state.
	if fs and fs.fontString and S[fs.fontString] == rs then
		local fo
		if fs.disabled then fo = fs.disabledFont
		elseif SIM.hover == f and fs.highlightFont then fo = fs.highlightFont end
		if fo and S[fo] then
			local c = SIM.fontProp(S[fo], "textColor", nil)
			if c then return c end
		end
	end
	return SIM.fontProp(rs, "textColor", { 1, 1, 1, 1 })
end

local function exportRegion(f, fs, o, items, clip, frameAlpha)
	local s = S[o]
	if not s.shown or s.isMask then return end
	if s.role then
		if s.roleCleared or not roleVisible(f, fs, s.role) then return end
	elseif s.layer == "HIGHLIGHT" then
		if not ((SIM.hover == f) or fs.lockHL) then return end
	end
	local l, b, r, t = computeRect(o)
	if s.isBarFill and S[s.isBarFill] then
		local bar = s.isBarFill
		local bs = S[bar]
		local bl, bb, br, bt = computeRect(bar)
		if not bl then return end
		local lo, hi, v = bs.min or 0, bs.max or 1, bs.value or 0
		local frac = (hi > lo) and max(0, min(1, (v - lo) / (hi - lo))) or 0
		if bs.orient == "VERTICAL" then
			if bs.reverse then l, r, t, b = bl, br, bt, bt - (bt - bb) * frac
			else l, r, b, t = bl, br, bb, bb + (bt - bb) * frac end
		else
			if bs.reverse then l, b, r, t = br - (br - bl) * frac, bb, br, bt
			else l, b, r, t = bl, bb, bl + (br - bl) * frac, bt end
		end
		if frac <= 0 then return end
	elseif s.isThumb and S[s.isThumb] then
		local sl = s.isThumb
		local ss = S[sl]
		local fl, fb, fr, ft = computeRect(sl)
		if not fl then return end
		local es = escale(o)
		local w, h = (s.w or 16) * es, (s.h or 16) * es
		local lo, hi, v = ss.min or 0, ss.max or 0, ss.value or 0
		local frac = (hi > lo) and (v - lo) / (hi - lo) or 0
		if (ss.orient or "HORIZONTAL") == "VERTICAL" then
			local cy = ft - (ft - fb - h) * frac - h / 2
			local cx = (fl + fr) / 2
			l, r, b, t = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
		else
			local cx = fl + (fr - fl - w) * frac + w / 2
			local cy = (fb + ft) / 2
			l, r, b, t = cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
		end
	end
	local alpha = frameAlpha * s.alpha * ((s.anim and s.anim.alpha) or 1)
	if alpha <= 0.002 then return end
	if s.isText then
		if not l then return end
		if not s.text or s.text == "" then return end
		local path, size, flags = SIM.fontOf(s)
		local item = box({ k = "s", i = s.id, a = alpha, t = s.text, f = path, z = size }, l, b, r, t)
		if flags ~= "" then item.fl = flags end
		local es = escale(o)
		if es ~= 1 then item.sc = es end
		item.c = fontColor(f, fs, s)
		item.jh = SIM.fontProp(s, "justifyH", "CENTER")
		item.jv = SIM.fontProp(s, "justifyV", "MIDDLE")
		local sc = SIM.fontProp(s, "shadowColor", nil)
		local so = SIM.fontProp(s, "shadowOffset", nil)
		if sc and so and (so[1] ~= 0 or so[2] ~= 0) and (sc[4] or 1) > 0 then
			item.sh = { sc[1], sc[2], sc[3], sc[4] or 1, so[1], so[2] }
		end
		if s.wrap == false then item.nw = 1 end
		if s.spacing and s.spacing ~= 0 then item.sp = s.spacing end
		if s.maxLines and s.maxLines > 0 then item.ml = s.maxLines end
		item.cl = clip
		items[#items + 1] = item
		return
	end
	if s.isLine then
		local a, e = s.lineStart, s.lineEnd
		if not a or not e then return end
		local al, ab, ar, at = computeRect(a.rel)
		local el, eb, er, et = computeRect(e.rel)
		if not al or not el then return end
		local es = escale(o)
		local H = SIM.screenH
		local x1 = al + SIM.PX[a.p] * (ar - al) + a.x * es
		local y1 = ab + SIM.PY[a.p] * (at - ab) + a.y * es
		local x2 = el + SIM.PX[e.p] * (er - el) + e.x * es
		local y2 = eb + SIM.PY[e.p] * (et - eb) + e.y * es
		items[#items + 1] = {
			k = "ln", i = s.id, a = alpha, x1 = r1(x1), y1 = r1(H - y1), x2 = r1(x2), y2 = r1(H - y2),
			th = (s.thick or 1) * es, c = s.color, vc = s.vc, tex = s.tex, cl = clip,
		}
		return
	end
	if not l then return end
	if not (s.tex or s.color or s.atlas) then return end
	local item = box({ k = "t", i = s.id, a = alpha }, l, b, r, t)
	if s.color then item.c = s.color end
	if s.tex then item.tex = s.tex end
	if s.atlas then item.at = s.atlas end
	if s.tc then item.tc = s.tc end
	if s.vc then item.vc = s.vc end
	if s.blend and s.blend ~= "BLEND" then item.bm = s.blend end
	if s.desat then item.ds = s.desat end
	local rot = (s.rot or 0) + ((s.anim and s.anim.rot) or 0)
	if rot ~= 0 then item.rot = rot end
	if s.grad then item.g = s.grad end
	if s.htile or s.vtile then item.tile = 1 end
	item.cl = clip
	items[#items + 1] = item
end

local function exportFrame(f, items, cache)
	local s = S[f]
	local l, b, r, t = computeRect(f)
	if not l then return end
	local alpha = effAlpha(f)
	if alpha <= 0.002 then return end
	local clip = clipArr(clipOf(f, cache))
	if s.backdrop then
		local bd = s.backdrop
		local es = escale(f)
		items[#items + 1] = box({
			k = "b", i = s.id, a = alpha, bg = bd.bg, ed = bd.edge, es = bd.edgeSize * es,
			ins = { bd.ins[1] * es, bd.ins[2] * es, bd.ins[3] * es, bd.ins[4] * es }, bc = s.bgColor, ec = s.bdColor, cl = clip, tile = bd.tile and 1 or nil,
		}, l, b, r, t)
	end
	if s.skin then
		local item = box({ k = "k", i = s.id, sk = s.skin, a = alpha, cl = clip }, l, b, r, t)
		if s.pushed then item.p = 1 end
		if s.disabled then item.d = 1 end
		if SIM.hover == f or s.lockHL then item.hv = 1 end
		if s.checked then item.c = 1 end
		if s.otype == "Slider" then
			local lo, hi, v = s.min or 0, s.max or 0, s.value or 0
			item.v = (hi > lo) and (v - lo) / (hi - lo) or 0
			item.o = s.orient
		end
		item.es = escale(f)
		items[#items + 1] = item
	end
	if s.regions then
		local regs = {}
		for _, o in ipairs(s.regions) do if S[o].shown then regs[#regs + 1] = o end end
		tsort(regs, function(a, c)
			local sa, sc = S[a], S[c]
			local la, lc = LAYERS[sa.layer] or 3, LAYERS[sc.layer] or 3
			if la ~= lc then return la < lc end
			local ua, uc = sa.sublevel or 0, sc.sublevel or 0
			if ua ~= uc then return ua < uc end
			return sa.id < sc.id
		end)
		for _, o in ipairs(regs) do exportRegion(f, s, o, items, clip, alpha) end
	end
	local ot = s.otype
	if ot == "EditBox" then
		local path, size, flags = SIM.fontOf(s)
		local item = box({
			k = "e", i = s.id, a = alpha, t = s.text or "", rev = s.textRev or 0, f = path, z = size,
			c = SIM.fontProp(s, "textColor", { 1, 1, 1, 1 }), foc = (SIM.focus == f) and 1 or nil,
			ml = s.multi and 1 or nil, ins = s.insets, jh = SIM.fontProp(s, "justifyH", "LEFT"),
			pw = s.password and 1 or nil, cl = clip, num = s.numeric and 1 or nil, max = s.maxLetters,
		}, l, b, r, t)
		if s.highlightReq then item.hl = s.highlightReq s.highlightReq = nil end
		local es = escale(f)
		if es ~= 1 then item.sc = es end
		items[#items + 1] = item
	elseif (ot == "MessageFrame" or ot == "ScrollingMessageFrame") and s.messages and #s.messages > 0 then
		local path, size = SIM.fontOf(s)
		local lines, now = {}, SIM.now
		local tv = s.timeVisible or 10
		for i = max(1, #s.messages - 60), #s.messages do
			local m = s.messages[i]
			if s.fading == false or ot == "ScrollingMessageFrame" or now - m.at < tv + (s.fadeDuration or 3) then
				lines[#lines + 1] = { t = m.t, c = m.c }
			end
		end
		if #lines > 0 then
			items[#items + 1] = box({
				k = "m", i = s.id, a = alpha, f = path, z = size, lines = lines, cl = clip,
				jh = SIM.fontProp(s, "justifyH", "LEFT"), top = (s.insertMode == "TOP") and 1 or nil,
			}, l, b, r, t)
		end
	elseif ot == "Cooldown" and s.cdStart and s.cdDur and s.cdDur > 0 then
		local now = s.cdPaused or SIM.now
		local left = s.cdStart + s.cdDur - now
		if left > 0 then
			items[#items + 1] = box({
				k = "cd", i = s.id, a = alpha, p = left / s.cdDur, rev = s.cdReverse and 1 or nil,
				sw = (not s.cdNoSwipe) and (s.cdColor or { 0, 0, 0, 0.8 }) or nil,
				n = (not s.cdHideNumbers) and left or nil, cl = clip,
			}, l, b, r, t)
		end
	elseif s.placeholder then
		items[#items + 1] = box({ k = "ph", i = s.id, a = alpha, t = s.placeholder, cl = clip }, l, b, r, t)
	end
end

function SIM.scene()
	local items = {}
	local cache = {}
	local list = SIM.sortedVisibleFrames()
	for _, f in ipairs(list) do exportFrame(f, items, cache) end
	return items
end

-- Frame stack under the cursor (like /fstack).
function SIM.inspectAt(x, y)
	local out = {}
	local list = SIM.sortedVisibleFrames()
	for i = #list, 1, -1 do
		local f = list[i]
		local l, b, r, t = computeRect(f)
		if l and x >= l and x <= r and y >= b and y <= t then
			local s = S[f]
			local pts = {}
			for _, p in ipairs(s.points) do
				local rn = p.rel and (S[p.rel] and (S[p.rel].name or (S[p.rel].otype .. "#" .. S[p.rel].id))) or "screen"
				pts[#pts + 1] = string.format("%s → %s:%s (%g, %g)", p.p, rn, p.rp, p.x, p.y)
			end
			local es = escale(f)
			out[#out + 1] = {
				id = s.id, name = s.name or ("<" .. s.otype .. " #" .. s.id .. ">"), type = s.otype,
				w = r1((r - l) / es), h = r1((t - b) / es), strata = SIM.effStrata(f), level = SIM.effLevel(f),
				mouse = s.mouse or false, points = pts, parent = s.parent and S[s.parent] and (S[s.parent].name or ("#" .. S[s.parent].id)) or nil,
				box = box({}, l, b, r, t),
			}
			if #out >= 12 then break end
		end
	end
	return out
end
