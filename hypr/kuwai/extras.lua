local K = require("kuwai.core")
local A = require("kuwai.actions")

local dsp = hl.dsp
local bind = K.bind

if K.feature("resize_mode") then
	K.group("Windows|Resize")
	bind("SUPER + CTRL + S", "Resize mode (arrows; Enter/Esc to leave)", dsp.submap("resize"))
	K.group(nil)
	local function r(x, y)
		return dsp.window.resize({ x = x, y = y, relative = true })
	end
	K.submap("resize", function()
		local rep = { repeating = true }
		for key, d in pairs({ left = { -20, 0 }, right = { 20, 0 }, up = { 0, -20 }, down = { 0, 20 }, h = { -20, 0 }, l = { 20, 0 }, k = { 0, -20 }, j = { 0, 20 } }) do
			bind(key, "", r(d[1], d[2]), rep)
			bind("SHIFT + " .. key, "", r(d[1] * 5, d[2] * 5), rep)
		end
		bind("equal", "", dsp.layout("colresize +0.05"), rep)
		bind("minus", "", dsp.layout("colresize -0.05"), rep)
		bind("Return", "", dsp.submap("reset"))
		bind("Escape", "", dsp.submap("reset"))
		bind("catchall", "", dsp.submap("reset"))
	end)
	local note
	hl.on("keybinds.submap", function(name)
		if name == "resize" then
			local ok, n = pcall(hl.notification.create, { text = "Resize — arrows (Shift: faster), Enter to finish", timeout = 600000, icon = "info" })
			note = ok and n or nil
		elseif note then
			pcall(function()
				note:dismiss()
			end)
			note = nil
		end
	end)
end

local PLACE_SKIP = {
	cider = true,
	["com.mitchellh.ghostty"] = true,
	["google-chrome"] = true,
	["brave-browser"] = true,
}

if K.feature("remember_place") then
	local function key(cls)
		return "place." .. cls:gsub("[^%w%.%-_]", "_")
	end
	for k, v in pairs(K.state) do
		local cls = k:match("^place%.(.+)$")
		local x, y = (v or ""):match("^(%-?%d+),(%-?%d+)")
		if cls and x and not PLACE_SKIP[cls:lower()] then
			pcall(hl.window_rule, {
				name = "place-" .. cls,
				match = { class = "^(" .. cls:gsub("([%.%-%+%*%?%^%$%(%)%[%]])", "\\%1") .. ")$", float = true },
				move = x .. " " .. y,
			})
		end
	end
	hl.on("window.close", function(w)
		if not (w and w.floating and w.class and w.class ~= "" and not w.pinned) then
			return
		end
		if PLACE_SKIP[w.class:lower()] then
			return
		end
		local m = w.monitor
		local at = w.at or {}
		if not (m and at.x) then
			return
		end
		local x, y = math.floor(at.x - m.x), math.floor(at.y - m.y)
		if x < -50 or y < -50 then
			return
		end
		local count = 0
		for k in pairs(K.state) do
			if k:match("^place%.") then
				count = count + 1
			end
		end
		if count >= 40 and not K.state[key(w.class)] then
			return
		end
		K.set_state(key(w.class), x .. "," .. y)
	end)
end

local PIP_TICK = 0.05
local PIP_FAST = 1100
local PIP_CHASE = 30
local PIP_MARGIN = 16
local PIP_PAD = 28
local PIP_TITLES = { "picture.?in.?picture", "mini.?player" }
local function pip_title(w)
	local t = (w and w.title or ""):lower()
	for _, pat in ipairs(PIP_TITLES) do
		if t:find(pat) then
			return true
		end
	end
	return false
end
local function is_special_ws(ws)
	if not ws then
		return false
	end
	return (ws.id and ws.id < 0) or (ws.name and ws.name:sub(1, 8) == "special:") or false
end
local function is_pip(w)
	return w and pip_title(w) and w.floating and not is_special_ws(w.workspace)
end
local function pips()
	local out = {}
	for _, w in ipairs(hl.get_windows() or {}) do
		if is_pip(w) then
			out[#out + 1] = w
		end
	end
	return out
end
local function seg_hits_rect(x1, y1, x2, y2, rx, ry, rw, rh)
	local dx, dy = x2 - x1, y2 - y1
	local t0, t1 = 0, 1
	local function clip(p, q)
		if p == 0 then
			return q >= 0
		end
		local r = q / p
		if p < 0 then
			if r > t1 then
				return false
			end
			if r > t0 then
				t0 = r
			end
		else
			if r < t0 then
				return false
			end
			if r < t1 then
				t1 = r
			end
		end
		return true
	end
	return clip(-dx, x1 - rx)
		and clip(dx, rx + rw - x1)
		and clip(-dy, y1 - ry)
		and clip(dy, ry + rh - y1)
end
local function mon_at(x, y)
	local best, bd
	for _, m in ipairs(hl.get_monitors() or {}) do
		local u = A.usable(m)
		local cx = math.max(u.x, math.min(x, u.x + u.w))
		local cy = math.max(u.y, math.min(y, u.y + u.h))
		local d = (cx - x) ^ 2 + (cy - y) ^ 2
		if not bd or d < bd then
			best, bd = m, d
		end
	end
	return best
end
local function corners(m, sz)
	local u = A.usable(m)
	local l, r = u.x + PIP_MARGIN, u.x + u.w - sz.x - PIP_MARGIN
	local t, b = u.y + PIP_MARGIN, u.y + u.h - sz.y - PIP_MARGIN
	return { { l, t }, { r, t }, { r, b }, { l, b } }
end
local function nearest(m, sz, x, y)
	local best, bd, bi
	for i, c in ipairs(corners(m, sz)) do
		local d = (c[1] - x) ^ 2 + (c[2] - y) ^ 2
		if not bd or d < bd then
			best, bd, bi = c, d, i
		end
	end
	return best, bi
end
local pip = { tick = 0, cur = nil, dodged = {}, reaching = {}, seen = {}, ours = {} }
local function place(w, x, y)
	local key = tostring(w.address)
	pip.ours[key] = { math.floor(x), math.floor(y) }
	pip.seen[key] = nil
	hl.dispatch(dsp.window.move({ window = "address:" .. w.address, x = math.floor(x), y = math.floor(y) }))
end
local pip_wake
_G.kuwai = _G.kuwai or {}
function kuwai.pip_note_move(addr, x, y)
	if not addr or not x or not y then
		return
	end
	local key = tostring(addr)
	pip.ours[key] = { math.floor(x), math.floor(y) }
	pip.seen[key] = nil
	if pip_wake then
		pip_wake()
	end
end
if K.feature("pip_dodge") then
	local timer
	local function tick()
		local list = pips()
		if #list == 0 then
			if timer then
				timer:set_enabled(false)
			end
			pip.seen, pip.ours, pip.reaching, pip.dodged, pip.cur = {}, {}, {}, {}, nil
			return
		end
		pip.tick = pip.tick + 1
		local prev = pip.cur
		local c = hl.get_cursor_pos()
		local speed = 0
		if c and prev then
			speed = math.sqrt((c.x - prev.x) ^ 2 + (c.y - prev.y) ^ 2) / PIP_TICK
		end
		pip.cur = c and { x = c.x, y = c.y } or nil
		local shift = hl.is_key_down("Shift_L") or hl.is_key_down("Shift_R")
		local live = {}
		for _, w in ipairs(list) do
			local at, sz = w.at or {}, w.size or {}
			if at.x and sz.x then
				local key = tostring(w.address)
				live[key] = true
				local inside = c and c.x >= at.x and c.x <= at.x + sz.x and c.y >= at.y and c.y <= at.y + sz.y
				local was_inside = prev and prev.x >= at.x and prev.x <= at.x + sz.x and prev.y >= at.y and prev.y <= at.y + sz.y
				local near = c and c.x > at.x - PIP_PAD and c.x < at.x + sz.x + PIP_PAD and c.y > at.y - PIP_PAD and c.y < at.y + sz.y + PIP_PAD
				local crossed = c and prev and seg_hits_rect(prev.x, prev.y, c.x, c.y, at.x - PIP_PAD, at.y - PIP_PAD, sz.x + PIP_PAD * 2, sz.y + PIP_PAD * 2)
				local hit = near or crossed
				local cx, cy = at.x + sz.x / 2, at.y + sz.y / 2
				local toward = c and prev and ((c.x - prev.x) * (cx - prev.x) + (c.y - prev.y) * (cy - prev.y) > 0)
				local s = pip.seen[key]
				local mine = pip.ours[key]
				if mine and math.abs(mine[1] - at.x) < 4 and math.abs(mine[2] - at.y) < 4 then
					pip.ours[key] = nil
					s = nil
				end
				if s and (s.x ~= at.x or s.y ~= at.y) and not mine then
					s.vx, s.vy = at.x - s.x, at.y - s.y
					s.x, s.y, s.still, s.moving = at.x, at.y, 0, true
				elseif s then
					s.still = s.still + 1
					if s.moving and s.still >= 2 and not inside then
						s.moving = false
						local gx = at.x + sz.x / 2 + (s.vx or 0) * 3
						local gy = at.y + sz.y / 2 + (s.vy or 0) * 3
						local m = mon_at(gx, gy)
						if m then
							local cpos = nearest(m, sz, gx - sz.x / 2, gy - sz.y / 2)
							place(w, cpos[1], cpos[2])
						end
					end
				end
				if not pip.seen[key] or not s then
					pip.seen[key] = { x = at.x, y = at.y, still = 0, moving = false }
				end
				local last_dodge = pip.dodged[key] or -1000
				local dodged_now = false
				if hit and not was_inside and not pip.reaching[key] and not shift and toward and speed >= PIP_FAST
						and pip.tick - last_dodge > PIP_CHASE and not (s and s.moving) then
					local m = w.monitor or mon_at(at.x, at.y)
					local u = A.usable(m)
					local x = (at.x - u.x > u.w / 2 - sz.x / 2) and (u.x + PIP_MARGIN) or (u.x + u.w - sz.x - PIP_MARGIN)
					pip.dodged[key] = pip.tick
					pip.reaching[key] = false
					dodged_now = true
					place(w, x, at.y)
				end
				if not dodged_now then
					if inside or (near and speed < PIP_FAST) then
						pip.reaching[key] = true
					elseif not hit then
						pip.reaching[key] = false
					end
				end
			end
		end
		for _, tbl in ipairs({ pip.seen, pip.ours, pip.reaching, pip.dodged }) do
			for k in pairs(tbl) do
				if not live[k] then
					tbl[k] = nil
				end
			end
		end
	end
	local function start_timer()
		if timer then
			timer:set_enabled(true)
		else
			timer = hl.timer(tick, { timeout = math.floor(PIP_TICK * 1000), type = "repeat" })
		end
	end
	pip_wake = start_timer
	local function wake(w)
		if w and pip_title(w) then
			start_timer()
		end
	end
	hl.on("window.open", wake)
	hl.on("window.title", wake)
	K.defer(function()
		if #pips() > 0 then
			start_timer()
		end
	end)
end
local function the_pip()
	local list = pips()
	if #list <= 1 then
		return list[1]
	end
	local c = hl.get_cursor_pos()
	if c then
		for _, w in ipairs(list) do
			local at, sz = w.at or {}, w.size or {}
			if at.x and sz.x and c.x >= at.x and c.x <= at.x + sz.x and c.y >= at.y and c.y <= at.y + sz.y then
				return w
			end
		end
	end
	local best, best_rank = list[1], list[1].focus_history_id or 999
	for i = 2, #list do
		local r = list[i].focus_history_id or 999
		if r < best_rank then
			best, best_rank = list[i], r
		end
	end
	return best
end
local function kuwai_pip_corner()
	local w = the_pip()
	if not w or not w.at or not w.size then
		return
	end
	local m = w.monitor or mon_at(w.at.x, w.at.y)
	local _, i = nearest(m, w.size, w.at.x, w.at.y)
	local c = corners(m, w.size)[(i % 4) + 1]
	pip.dodged[tostring(w.address)] = pip.tick
	place(w, c[1], c[2])
end
local function kuwai_pip_screen()
	local w = the_pip()
	if not w or not w.at or not w.size then
		return
	end
	local here = w.monitor or mon_at(w.at.x, w.at.y)
	local mons = hl.get_monitors() or {}
	if #mons < 2 then
		return
	end
	local idx = 1
	for i, m in ipairs(mons) do
		if m.name == here.name then
			idx = i
		end
	end
	local there = mons[(idx % #mons) + 1]
	local _, i = nearest(here, w.size, w.at.x, w.at.y)
	local c = corners(there, w.size)[i]
	pip.dodged[tostring(w.address)] = pip.tick
	place(w, c[1], c[2])
end
bind("SUPER + ALT + W", "Picture-in-picture: next corner", kuwai_pip_corner)
bind("SUPER + ALT + SHIFT + W", "Picture-in-picture: the other screen", kuwai_pip_screen)

_G.kuwai = _G.kuwai or {}
if K.feature("focus_sessions") then
	local t
	local function finish(quiet)
		if t then
			pcall(function()
				t:set_enabled(false)
			end)
			t = nil
		end
		K.set_state("focus_until", nil)
		hl.exec_cmd(K.bin .. "/kuwai notifs dnd-off")
		if not quiet then
			hl.exec_cmd(K.bin .. "/kuwai-notify -a kuwai -i alarm-symbolic 'Focus session done' 'Notifications are back. Take a break.'")
		end
	end
	local function arm(until_ts)
		local left = until_ts - os.time()
		if left <= 0 then
			finish(false)
			return
		end
		t = hl.timer(function()
			finish(false)
		end, { timeout = left * 1000, type = "oneshot" })
	end
	function kuwai.focus(minutes)
		if K.state["focus_until"] and minutes == nil then
			finish(true)
			K.notify("Focus session stopped", 1500)
			return "stopped"
		end
		minutes = tonumber(minutes) or 25
		if t then
			pcall(function()
				t:set_enabled(false)
			end)
			t = nil
		end
		local until_ts = os.time() + minutes * 60
		K.set_state("focus_until", until_ts)
		hl.exec_cmd(K.bin .. "/kuwai notifs dnd-on")
		K.notify(("Focus for %d minutes — notifications held until %s"):format(minutes, os.date("%H:%M", until_ts)), 3000)
		arm(until_ts)
		return "until " .. os.date("%H:%M", until_ts)
	end
	K.group("Shell")
	bind("SUPER + CTRL + G", "Focus session: 25 minutes (again to stop)", function()
		kuwai.focus()
	end)
	K.group(nil)
	K.defer(function()
		local u = tonumber(K.state["focus_until"])
		if u then
			arm(u)
		end
	end)
end
