-- kuwai.extras — resize mode, per-app place memory, smart PiP, focus sessions.
-- Each is a feature (`kuwai feature NAME off`).

local K = require("kuwai.core")
local A = require("kuwai.actions")

local dsp = hl.dsp
local bind = K.bind

---------------------------------------------------------------------------
-- Resize mode: Super+Ctrl+S, then arrows (Shift = big steps, Ctrl+Alt+±
-- = column width). Enter/Esc or any other key leaves. While it's on, a small
-- Hyprland notification says so (the island can read `submap>>resize` too).
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Remember place: a floating app reopens where it was on its screen.
-- (Size is persistent_size's job.) Your own move/size rules in user.lua load
-- later and win; only the last 40 apps are kept.
---------------------------------------------------------------------------
if K.feature("remember_place") then
	local function key(cls)
		return "place." .. cls:gsub("[^%w%.%-_]", "_")
	end
	-- Recreate the rules from what was saved.
	for k, v in pairs(K.state) do
		local cls = k:match("^place%.(.+)$")
		local x, y = (v or ""):match("^(%-?%d+),(%-?%d+)")
		if cls and x then
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
		local m = w.monitor
		local at = w.at or {}
		if not (m and at.x) then
			return
		end
		-- monitor-local logical position; skip windows mostly off-screen
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

---------------------------------------------------------------------------
-- Picture-in-picture that knows when you want it (feature pip_dodge)
---------------------------------------------------------------------------
-- It steps aside for a pointer passing by, never for one going to it:
--   · a pointer moving fast past it: it slides to the other bottom corner;
--   · a pointer arriving slowly, resting near it, or already on it: it stays
--     (you're reaching for it: seek, pause, close);
--   · just moved and you came after it: it stays (you're chasing it);
--   · Shift held: it stays, as before.
-- Drag it (Super+drag) and let go: it settles in the corner it was heading
-- for, on whichever screen that is, so a throw up sends it to a top corner
-- and a throw across sends it to the other screen.
-- Keys: Super+Alt+W next corner · Super+Alt+Shift+W the other screen ·
-- Super+Alt+E bigger / smaller. The 150 ms look runs only while one exists.
local PIP_TICK = 0.15                                  -- seconds
local PIP_FAST = 1100                                  -- px/s: faster than this is passing by
local PIP_CHASE = 27                                   -- ticks (~4 s) a dodge makes it stay put
local PIP_MARGIN = 16
local function is_pip(w)
	return w and (w.title or ""):lower():find("picture.?in.?picture") and w.floating
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
-- The four corners of a screen for a window of size sz: top-left, top-right,
-- bottom-right, bottom-left (clockwise, the order Super+Alt+W walks).
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
local pip = { tick = 0, cur = nil, dodged = -1000, reaching = false, seen = {}, ours = {} }
local function place(w, x, y)
	pip.ours[tostring(w.address)] = { math.floor(x), math.floor(y) }
	hl.dispatch(dsp.window.move({ window = "address:" .. w.address, x = math.floor(x), y = math.floor(y) }))
end
if K.feature("pip_dodge") then
	local timer
	local function tick()
		local list = pips()
		if #list == 0 then
			if timer then
				timer:set_enabled(false)
			end
			pip.seen, pip.ours, pip.reaching = {}, {}, false
			return
		end
		pip.tick = pip.tick + 1
		local c = hl.get_cursor_pos()
		local speed = 0
		if c and pip.cur then
			speed = math.sqrt((c.x - pip.cur.x) ^ 2 + (c.y - pip.cur.y) ^ 2) / PIP_TICK
		end
		pip.cur = c and { x = c.x, y = c.y } or nil
		local shift = hl.is_key_down("Shift_L") or hl.is_key_down("Shift_R")
		for _, w in ipairs(list) do
			local at, sz = w.at or {}, w.size or {}
			if at.x and sz.x then
				local key = tostring(w.address)
				local inside = c and c.x >= at.x and c.x <= at.x + sz.x and c.y >= at.y and c.y <= at.y + sz.y
				local pad = 24
				local near = c and c.x > at.x - pad and c.x < at.x + sz.x + pad and c.y > at.y - pad and c.y < at.y + sz.y + pad
				-- Reaching: on it, or slowly near it; it holds until the pointer has gone.
				if inside or (near and speed < PIP_FAST) then
					pip.reaching = true
				elseif not near then
					pip.reaching = false
				end
				-- Moved by you (a drag), not by us: when it stops, it settles in the
				-- corner it was heading for, on the screen that corner is on.
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
				-- Passing by, fast, and not chased: step aside.
				if near and not inside and not pip.reaching and not shift and speed >= PIP_FAST
						and pip.tick - pip.dodged > PIP_CHASE and not (s and s.moving) then
					local m = w.monitor or mon_at(at.x, at.y)
					local u = A.usable(m)
					local x = (at.x - u.x > u.w / 2 - sz.x / 2) and (u.x + PIP_MARGIN) or (u.x + u.w - sz.x - PIP_MARGIN)
					pip.dodged = pip.tick
					place(w, x, at.y)
				end
			end
		end
	end
	hl.on("window.open", function(w)
		if w and (w.title or ""):lower():find("picture.?in.?picture") then
			if timer then
				timer:set_enabled(true)
			else
				timer = hl.timer(tick, { timeout = math.floor(PIP_TICK * 1000), type = "repeat" })
			end
		end
	end)
end
-- Keys, with or without the dodging.
local function the_pip()
	return pips()[1]
end
local function kuwai_pip_corner()
	local w = the_pip()
	if not w or not w.at or not w.size then
		return
	end
	local m = w.monitor or mon_at(w.at.x, w.at.y)
	local _, i = nearest(m, w.size, w.at.x, w.at.y)
	local c = corners(m, w.size)[(i % 4) + 1]
	pip.dodged = pip.tick
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
	pip.dodged = pip.tick
	place(w, c[1], c[2])
end
bind("SUPER + ALT + W", "Picture-in-picture: next corner", kuwai_pip_corner)
bind("SUPER + ALT + SHIFT + W", "Picture-in-picture: the other screen", kuwai_pip_screen)
bind("SUPER + ALT + E", "Picture-in-picture: bigger / smaller", A.pip_toggle("pip"))

---------------------------------------------------------------------------
-- Focus sessions: Super+Ctrl+G starts 25 minutes (again: stop). Do Not
-- Disturb and focus mode for the length of it; a notification when it ends.
-- `kuwai focus 50` for another length. Survives reloads.
---------------------------------------------------------------------------
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
		hl.exec_cmd(K.bin .. "/rice notifs dnd-off")
		if not quiet then
			hl.exec_cmd(K.bin .. "/rice-notify -a kuwai -i alarm-symbolic 'Focus session done' 'Notifications are back. Take a break.'")
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
		-- A new length replaces a running session: its timer goes first, or
		-- the old deadline would end the new session early.
		if t then
			pcall(function()
				t:set_enabled(false)
			end)
			t = nil
		end
		local until_ts = os.time() + minutes * 60
		K.set_state("focus_until", until_ts)
		hl.exec_cmd(K.bin .. "/rice notifs dnd-on")
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
