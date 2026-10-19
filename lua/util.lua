-- WowSim: Lua 5.1 helpers that WoW provides on top of plain Lua.
-- Everything internal hangs off the hidden global __SIM.

local SIM = __SIM
local type, pairs, ipairs, tostring, select, unpack = type, pairs, ipairs, tostring, select, unpack
local floor, fmod = math.floor, math.fmod
local sfind, ssub, sgsub, sformat, sbyte, schar = string.find, string.sub, string.gsub, string.format, string.byte, string.char
local tconcat, tinsert, tremove, tsort = table.concat, table.insert, table.remove, table.sort

------------------------------------------------------------------------
-- bit library (WoW ships one; plain Lua 5.1 does not)
------------------------------------------------------------------------
do
	local function tobit(x)
		x = floor(x) % 4294967296
		if x >= 2147483648 then x = x - 4294967296 end
		return x
	end
	local function u(x) return floor(x) % 4294967296 end
	local function op(a, b, kind)
		a, b = u(a), u(b)
		local r, p = 0, 1
		for _ = 1, 32 do
			local x, y = a % 2, b % 2
			local v
			if kind == 1 then v = (x == 1 and y == 1)
			elseif kind == 2 then v = (x == 1 or y == 1)
			else v = (x ~= y) end
			if v then r = r + p end
			a, b, p = (a - x) / 2, (b - y) / 2, p * 2
		end
		return tobit(r)
	end
	local function fold(kind)
		return function(a, ...)
			a = tobit(a)
			for i = 1, select("#", ...) do a = op(a, (select(i, ...)), kind) end
			return a
		end
	end
	bit = {
		tobit = tobit,
		band = fold(1), bor = fold(2), bxor = fold(3),
		bnot = function(a) return tobit(4294967295 - u(a)) end,
		lshift = function(a, n) return tobit(u(a) * 2 ^ (n % 32)) end,
		rshift = function(a, n) return tobit(floor(u(a) / 2 ^ (n % 32))) end,
		arshift = function(a, n) return tobit(floor(tobit(a) / 2 ^ (n % 32))) end,
		mod = function(a, b) return fmod(a, b) end,
		tohex = function(a, n) return sformat("%0" .. (n or 8) .. "x", u(a)) end,
	}
end

------------------------------------------------------------------------
-- String helpers
------------------------------------------------------------------------
local function charClass(delim)
	return "[" .. sgsub(delim, "[%]%^%-%%]", "%%%0") .. "]"
end

function strsplit(delim, str, pieces)
	str = tostring(str)
	local out, n, start = {}, 0, 1
	local pat = charClass(delim)
	pieces = pieces or 0
	while not (pieces > 0 and n == pieces - 1) do
		local s, e = sfind(str, pat, start)
		if not s then break end
		n = n + 1
		out[n] = ssub(str, start, s - 1)
		start = e + 1
	end
	n = n + 1
	out[n] = ssub(str, start)
	return unpack(out, 1, n)
end

function strsplittable(delim, str, pieces)
	return { strsplit(delim, str, pieces) }
end

function strtrim(str, chars)
	chars = chars and charClass(chars) or "[ \t\r\n]"
	str = sgsub(str, "^" .. chars .. "+", "")
	return (sgsub(str, chars .. "+$", ""))
end

function strjoin(delim, ...)
	local t = {}
	for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
	return tconcat(t, delim)
end

function strconcat(...)
	return strjoin("", ...)
end

function tostringall(...)
	local n = select("#", ...)
	if n == 0 then return end
	return tostring((select(1, ...))), tostringall(select(2, ...))
end

function strcmputf8i(a, b)
	a, b = string.lower(a), string.lower(b)
	if a == b then return 0 end
	return a < b and -1 or 1
end

function strlenutf8(s)
	local _, n = sgsub(s, "[^\128-\191]", "")
	return n
end

function string.trim(s) return strtrim(s) end
function string.split(delim, str, pieces) return strsplit(delim, str, pieces) end
string.join = strjoin

strlower, strupper, strlen, strsub, strfind = string.lower, string.upper, string.len, string.sub, string.find
strmatch, strrep, strbyte, strchar, strrev = string.match, string.rep, string.byte, string.char, string.reverse
gsub, format, gmatch = string.gsub, string.format, string.gmatch
strgsub = string.gsub

------------------------------------------------------------------------
-- Math / table aliases
------------------------------------------------------------------------
_G.abs, _G.ceil, _G.floor, _G.max, _G.min, _G.sqrt = math.abs, math.ceil, math.floor, math.max, math.min, math.sqrt
mod, exp, log, log10, frexp, ldexp = math.fmod, math.exp, math.log, math.log10, math.frexp, math.ldexp
sin = function(d) return math.sin(math.rad(d)) end
cos = function(d) return math.cos(math.rad(d)) end
tan = function(d) return math.tan(math.rad(d)) end
asin = function(x) return math.deg(math.asin(x)) end
acos = function(x) return math.deg(math.acos(x)) end
atan = function(x) return math.deg(math.atan(x)) end
atan2 = function(y, x) return math.deg(math.atan2(y, x)) end
deg, rad = math.deg, math.rad
random = math.random
fastrandom = math.random
PI = math.pi

_G.tinsert, _G.tremove, _G.sort, _G.getn = table.insert, table.remove, table.sort, table.getn
foreach, foreachi = table.foreach, table.foreachi

function wipe(t)
	for k in pairs(t) do t[k] = nil end
	return t
end
table.wipe = wipe

function tContains(t, v)
	for i = 1, #t do if t[i] == v then return true end end
	return false
end

function tIndexOf(t, v)
	for i = 1, #t do if t[i] == v then return i end end
end

function tDeleteItem(t, v)
	local n = 0
	for i = #t, 1, -1 do if t[i] == v then tremove(t, i); n = n + 1 end end
	return n
end

function tInvert(t)
	local r = {}
	for k, v in pairs(t) do r[v] = k end
	return r
end

function tAppendAll(t, src)
	for i = 1, #src do t[#t + 1] = src[i] end
end

function tUnorderedRemove(t, i)
	t[i] = t[#t]
	t[#t] = nil
end

function tCount(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function TableIsEmpty(t) return next(t) == nil end
function TableHasAnyEntries(t) return next(t) ~= nil end

function CopyTable(t, shallow)
	local r = {}
	for k, v in pairs(t) do
		if type(v) == "table" and not shallow then r[k] = CopyTable(v) else r[k] = v end
	end
	return r
end

function GetKeysArray(t) local r = {} for k in pairs(t) do r[#r + 1] = k end return r end
function GetValuesArray(t) local r = {} for _, v in pairs(t) do r[#r + 1] = v end return r end
function GetPairsArray(t) local r = {} for k, v in pairs(t) do r[#r + 1] = { key = k, value = v } end return r end

function MergeTable(dst, src) for k, v in pairs(src) do dst[k] = v end return dst end

function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
function Saturate(v) return Clamp(v, 0, 1) end
function Lerp(a, b, t) return a + (b - a) * t end
function Round(v) return floor(v + 0.5) end
function ClampedPercentageBetween(v, lo, hi) if hi == lo then return 0 end return Saturate((v - lo) / (hi - lo)) end
function PercentageBetween(v, lo, hi) if hi == lo then return 0 end return (v - lo) / (hi - lo) end
function FrameDeltaLerp(a, b, amount) return Lerp(a, b, Saturate(amount * 0.016 * 60)) end
function WithinRange(v, lo, hi) return v >= lo and v <= hi end
function ApproximatelyEqual(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end

------------------------------------------------------------------------
-- Mixins
------------------------------------------------------------------------
function Mixin(object, ...)
	for i = 1, select("#", ...) do
		local mixin = select(i, ...)
		if mixin then for k, v in pairs(mixin) do object[k] = v end end
	end
	return object
end

function CreateFromMixins(...)
	return Mixin({}, ...)
end

function CreateAndInitFromMixin(mixin, ...)
	local o = CreateFromMixins(mixin)
	o:Init(...)
	return o
end

------------------------------------------------------------------------
-- os: WoW only exposes time/date/clock
------------------------------------------------------------------------
do
	local o = os
	time, date = o.time, o.date
	os = { time = o.time, date = o.date, clock = o.clock, difftime = o.difftime }
	SIM.realClock = o.clock
end

------------------------------------------------------------------------
-- JSON (used for the scene sent to the browser)
------------------------------------------------------------------------
do
	local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
	local function esc(s)
		s = sgsub(s, '[%c"\\]', function(c)
			return escapes[c] or sformat("\\u%04x", sbyte(c))
		end)
		return s
	end
	local function num(n)
		if n ~= n or n == math.huge or n == -math.huge then return "0" end
		if n == floor(n) and n > -1e15 and n < 1e15 then return sformat("%d", n) end
		return sformat("%.4f", n)
	end
	local enc
	enc = function(v, out, depth)
		local t = type(v)
		if t == "string" then out[#out + 1] = '"' .. esc(v) .. '"'
		elseif t == "number" then out[#out + 1] = num(v)
		elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
		elseif t == "table" and depth < 40 then
			if v[1] ~= nil or rawget(v, "__array") then
				out[#out + 1] = "["
				for i = 1, #v do
					if i > 1 then out[#out + 1] = "," end
					enc(v[i], out, depth + 1)
				end
				out[#out + 1] = "]"
			else
				out[#out + 1] = "{"
				local first = true
				for k, val in pairs(v) do
					if k ~= "__array" and type(k) ~= "table" then
						local vt = type(val)
						if vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
							if not first then out[#out + 1] = "," end
							first = false
							out[#out + 1] = '"' .. esc(tostring(k)) .. '":'
							enc(val, out, depth + 1)
						end
					end
				end
				out[#out + 1] = "}"
			end
		else
			out[#out + 1] = "null"
		end
	end
	function SIM.json(v)
		local out = {}
		enc(v, out, 0)
		return tconcat(out)
	end
	SIM.EMPTY_ARRAY = { __array = true }
end

------------------------------------------------------------------------
-- SavedVariables serializer (Lua source, like WTF files)
------------------------------------------------------------------------
do
	local function key(k)
		if type(k) == "string" then return "[" .. sformat("%q", k) .. "]" end
		if type(k) == "number" then return "[" .. tostring(k) .. "]" end
		if type(k) == "boolean" then return "[" .. tostring(k) .. "]" end
	end
	local function val(v, indent, seen, out)
		local t = type(v)
		if t == "string" then out[#out + 1] = sformat("%q", v)
		elseif t == "number" then
			if v ~= v then out[#out + 1] = "0/0"
			elseif v == math.huge then out[#out + 1] = "math.huge"
			elseif v == -math.huge then out[#out + 1] = "-math.huge"
			elseif v == floor(v) then out[#out + 1] = sformat("%d", v)
			else out[#out + 1] = sformat("%.17g", v) end
		elseif t == "boolean" then out[#out + 1] = tostring(v)
		elseif t == "table" then
			if seen[v] then out[#out + 1] = "nil --[[cycle]]" return end
			seen[v] = true
			out[#out + 1] = "{\n"
			local keys = {}
			for k in pairs(v) do if key(k) then keys[#keys + 1] = k end end
			tsort(keys, function(a, b)
				local ta, tb = type(a), type(b)
				if ta ~= tb then return ta < tb end
				if ta == "boolean" then return tostring(a) < tostring(b) end
				return a < b
			end)
			local pad = string.rep("\t", indent + 1)
			for _, k in ipairs(keys) do
				local vt = type(v[k])
				if vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
					out[#out + 1] = pad .. key(k) .. " = "
					val(v[k], indent + 1, seen, out)
					out[#out + 1] = ",\n"
				end
			end
			out[#out + 1] = string.rep("\t", indent) .. "}"
			seen[v] = nil
		else
			out[#out + 1] = "nil"
		end
	end
	function SIM.serialize(name, v)
		local out = { name, " = " }
		val(v, 0, {}, out)
		out[#out + 1] = "\n"
		return tconcat(out)
	end
	-- Pretty value dump for the console.
	function SIM.dump(v, maxDepth)
		if type(v) ~= "table" then
			if type(v) == "string" then return sformat("%q", v) end
			return tostring(v)
		end
		local out = {}
		val(v, 0, {}, out)
		local s = tconcat(out)
		if #s > 20000 then s = ssub(s, 1, 20000) .. "\n... (truncated)" end
		return s
	end
end
