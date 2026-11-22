local K = require("kuwai.core")
local A = require("kuwai.actions")

local C = {}
local DEFAULTS = {
	classes = { "^com%.rtosta%.zapzap$" },
	small = { 380, 600 },
	large = { 870, 600 },
	anchor = "inplace",
	dwell = 350,
	linger = 1200,
	margin = { 20, 50 },
	gap = 8,
}

function C.opt(key)
	local o = K.chat or {}
	if o[key] ~= nil then
		return o[key]
	end
	return DEFAULTS[key]
end

function C.is_chat(w)
	if not w or not w.floating or not w.class then
		return false
	end
	for _, pat in ipairs(C.opt("classes")) do
		if w.class:find(pat) then
			return true
		end
	end
	return false
end

local function clamp(v, lo, hi)
	if hi < lo then
		return lo
	end
	return math.max(lo, math.min(hi, v))
end

function C.target(w, big, u)
	local sz = big and C.opt("large") or C.opt("small")
	local gap = C.opt("gap")
	if C.opt("anchor") == "corner" then
		local m = C.opt("margin")
		return u.x + u.w - sz[1] - m[1], u.y + m[2], sz[1], sz[2]
	end
	local at, cur = w.at or { x = u.x, y = u.y }, w.size or { x = sz[1], y = sz[2] }
	local x = at.x
	if at.x + cur.x / 2 > u.x + u.w / 2 then
		x = at.x + cur.x - sz[1]
	end
	local y = at.y
	return clamp(x, u.x + gap, u.x + u.w - sz[1] - gap), clamp(y, u.y + gap, u.y + u.h - sz[2] - gap), sz[1], sz[2]
end

C.big = {}

function C.resize(w, big)
	local mon = w.monitor or hl.get_active_monitor()
	if not mon then
		return
	end
	local x, y, wd, ht = C.target(w, big, A.usable(mon))
	local sel = "address:" .. w.address
	hl.dispatch(hl.dsp.window.resize({ window = sel, x = wd, y = ht }))
	hl.dispatch(hl.dsp.window.move({ window = sel, x = x, y = y }))
	C.big[w.address] = big or nil
end

function C.toggle()
	local w = hl.get_active_window()
	if not C.is_chat(w) then
		for _, v in ipairs(hl.get_windows()) do
			if C.is_chat(v) then
				w = v
				break
			end
		end
	end
	if C.is_chat(w) then
		C.resize(w, not C.big[w.address])
	end
end

local function still(addr)
	local a = hl.get_active_window()
	return a and a.address == addr and hl.get_window("address:" .. addr)
end

function C.on_active(w)
	if not K.feature("chat_autoexpand") then
		return
	end
	for addr in pairs(C.big) do
		if not w or w.address ~= addr then
			hl.timer(function()
				local cur = hl.get_window("address:" .. addr)
				local a = hl.get_active_window()
				if cur and C.big[addr] and not (a and a.address == addr) then
					C.resize(cur, false)
				elseif not cur then
					C.big[addr] = nil
				end
			end, { timeout = C.opt("linger"), type = "oneshot" })
		end
	end
	if C.is_chat(w) and not C.big[w.address] then
		local addr = w.address
		hl.timer(function()
			local cur = still(addr)
			if cur and not C.big[addr] then
				C.resize(cur, true)
			end
		end, { timeout = C.opt("dwell"), type = "oneshot" })
	end
end

hl.on("window.active", C.on_active)
hl.on("window.destroy", function(w)
	if w then
		C.big[w.address] = nil
	end
end)

_G.kuwai = _G.kuwai or {}
_G.kuwai.chat_toggle = C.toggle

return C
