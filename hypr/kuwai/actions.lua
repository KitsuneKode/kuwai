-- kuwai.actions — window actions that used to be shell scripts (jq + several
-- hyprctl round trips each). In Lua they're one step on the compositor's own
-- state: no process, no race with focus-follows-mouse, no visible jumps.
--
-- Everything targets windows by address, never "the active window" after a
-- change, because un-maximizing or floating reflows the layout and the pointer
-- can hand focus to whatever lands under it mid-way.

local K = require("kuwai.core")

local A = {}

local function sel(w)
	return "address:" .. w.address
end

local function dsp(d)
	return hl.dispatch(d)
end

-- Logical rectangle of a monitor, minus bars (reserved area).
function A.usable(m)
	local s = m.scale or 1
	local w, h = math.floor(m.width / s), math.floor(m.height / s)
	local r = m.reserved or {}
	local top, bot = r.top or 0, r.bottom or 0
	local left, right = r.left or 0, r.right or 0
	return {
		x = m.x + left,
		y = m.y + top,
		w = w - left - right,
		h = h - top - bot,
		mx = m.x,
		my = m.y,
		mw = w,
		mh = h,
	}
end

local function unmaximize(w)
	if (w.fullscreen or 0) ~= 0 then
		dsp(hl.dsp.window.fullscreen_state({ window = sel(w), internal = 0, client = 0, action = "set" }))
	end
end

-- Float at one predictable size (62% × 66% of the usable area, centred),
-- tile back on the second press. Plain float toggling did nothing on
-- maximized windows and kept the tiled size the first time.
function A.float_toggle()
	local w = hl.get_active_window()
	if not w then
		return
	end
	if w.floating then
		dsp(hl.dsp.window.float({ window = sel(w), action = "disable" }))
		return
	end
	unmaximize(w)
	local u = A.usable(w.monitor or hl.get_active_monitor())
	local ww, wh = math.floor(u.w * 0.62), math.floor(u.h * 0.66)
	dsp(hl.dsp.window.float({ window = sel(w), action = "enable" }))
	dsp(hl.dsp.window.resize({ window = sel(w), x = ww, y = wh }))
	dsp(hl.dsp.window.move({ window = sel(w), x = u.x + math.floor((u.w - ww) / 2), y = u.y + math.floor((u.h - wh) / 2) }))
end

-- Pin = float + show on every workspace; unpinning tiles it back.
function A.pin_toggle()
	local w = hl.get_active_window()
	if not w then
		return
	end
	if w.pinned then
		dsp(hl.dsp.window.pin({ window = sel(w), action = "disable" }))
		dsp(hl.dsp.window.float({ window = sel(w), action = "disable" }))
	else
		if not w.floating then
			dsp(hl.dsp.window.float({ window = sel(w), action = "enable" }))
		end
		dsp(hl.dsp.window.pin({ window = sel(w), action = "enable" }))
	end
end

-- Close; Steam's main window is hidden to the tray instead of quitting.
function A.close()
	local w = hl.get_active_window()
	if not w then
		return
	end
	if w.class == "steam" or w.class == "Steam" then
		if K.has("xdotool") then
			hl.exec_cmd("xdotool windowunmap $(xdotool getactivewindow)")
			return
		end
	end
	dsp(hl.dsp.window.close({ window = sel(w) }))
end

-- Floating: nudge by (dx, dy). Tiled: move within the layout.
function A.move(direction, dx, dy)
	return function()
		local w = hl.get_active_window()
		if w and w.floating then
			dsp(hl.dsp.window.move({ window = sel(w), x = dx, y = dy, relative = true }))
		else
			dsp(hl.dsp.window.move({ direction = direction }))
		end
	end
end

-- Picture-in-picture / mpv: flip between small and large, anchored to the
-- bottom-right of the monitor the window is on. The window keeps focus where
-- it was (nothing is focused to do this).
local PIP_SIZES = { small = { 480, 270 }, large = { 955, 540 } }
function A.pip_toggle(kind)
	return function()
		local target
		for _, w in ipairs(hl.get_windows()) do
			local t, c = (w.title or ""):lower(), (w.class or ""):lower()
			if (kind == "mpv" and c:find("mpv", 1, true)) or (kind ~= "mpv" and t:find("picture.in.picture")) then
				target = w
				break
			end
		end
		if not target then
			return
		end
		local size = target.size or {}
		local cur_w = size.x or size[1] or 0
		local s = (cur_w == PIP_SIZES.large[1]) and PIP_SIZES.small or PIP_SIZES.large
		local u = A.usable(target.monitor or hl.get_active_monitor())
		local margin = 16
		unmaximize(target)
		if not target.floating then
			dsp(hl.dsp.window.float({ window = sel(target), action = "enable" }))
		end
		dsp(hl.dsp.window.resize({ window = sel(target), x = s[1], y = s[2] }))
		dsp(hl.dsp.window.move({ window = sel(target), x = u.mx + u.mw - s[1] - margin, y = u.my + u.mh - s[2] - margin }))
	end
end

-- Zoom into the cursor (Alt+Shift+wheel), clamped to 1–10×.
function A.zoom(mult)
	return function()
		local z = K.get("cursor.zoom_factor") or 1
		local nz = (mult == 0) and 1 or math.max(1, math.min(10, z * mult))
		K.config({ cursor = { zoom_factor = nz } })
	end
end

-- Launch-or-focus (feature launch_focus). `pattern` is a Lua pattern matched
-- against the lowercased window class. Not open → launch. Open but not focused
-- → focus its most recent window. Already focused → the next one of that app.
-- Feature off → always launch.
function A.app(pattern, cmd)
	return function()
		if not K.feature("launch_focus") then
			hl.exec_cmd(cmd)
			return
		end
		local mine, active = {}, hl.get_active_window()
		for _, w in ipairs(hl.get_windows() or {}) do
			if (w.class or ""):lower():match(pattern) and w.mapped ~= false then
				mine[#mine + 1] = w
			end
		end
		if #mine == 0 then
			hl.exec_cmd(cmd)
			return
		end
		table.sort(mine, function(a, b)
			return (a.focus_history_id or 99) < (b.focus_history_id or 99)
		end)
		local target = mine[1]
		if active and (active.class or ""):lower():match(pattern) then
			-- cycle: the least recently used one comes next
			target = mine[#mine]
		end
		dsp(hl.dsp.focus({ window = sel(target) }))
	end
end
A.focus_or_launch = A.app

-- Focus the next/previous screen, left to right.
local function monitors_by_x()
	local ms = hl.get_monitors() or {}
	table.sort(ms, function(a, b)
		return (a.x or 0) < (b.x or 0)
	end)
	return ms
end

function A.focus_screen(delta)
	return function()
		local ms, cur = monitors_by_x(), hl.get_active_monitor()
		if #ms < 2 or not cur then
			return
		end
		local i = 1
		for j, m in ipairs(ms) do
			if m.name == cur.name then
				i = j
			end
		end
		dsp(hl.dsp.focus({ monitor = ms[((i - 1 + delta) % #ms) + 1].name }))
	end
end

-- Exit: let the rice (or hyprshutdown) close apps gracefully when available.
function A.exit()
	if K.has("hyprshutdown") then
		hl.exec_cmd("hyprshutdown")
	else
		dsp(hl.dsp.exit())
	end
end

_G.kuwai = _G.kuwai or {}
_G.kuwai.actions = A

return A
