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
-- Smart PiP: when the pointer comes near a picture-in-picture window, it slides
-- to the other bottom corner. Hold Shift to reach it (pause, drag, close).
-- The 150 ms check runs only while a PiP window exists.
---------------------------------------------------------------------------
if K.feature("pip_dodge") then
	local timer
	local function pips()
		local out = {}
		for _, w in ipairs(hl.get_windows() or {}) do
			if (w.title or ""):lower():find("picture.?in.?picture") and w.floating then
				out[#out + 1] = w
			end
		end
		return out
	end
	local function tick()
		local list = pips()
		if #list == 0 then
			if timer then
				timer:set_enabled(false)
			end
			return
		end
		if hl.is_key_down("Shift_L") or hl.is_key_down("Shift_R") then
			return
		end
		local c = hl.get_cursor_pos()
		if not c then
			return
		end
		for _, w in ipairs(list) do
			local at, sz, m = w.at or {}, w.size or {}, w.monitor
			local pad = 24
			if m and at.x and sz.x and c.x > at.x - pad and c.x < at.x + sz.x + pad and c.y > at.y - pad and c.y < at.y + sz.y + pad then
				local u = A.usable(m)
				local margin = 16
				local left = u.x + margin
				local right = u.x + u.w - sz.x - margin
				local x = (at.x - u.x > u.w / 2 - sz.x / 2) and left or right
				hl.dispatch(dsp.window.move({ window = "address:" .. w.address, x = x, y = at.y }))
			end
		end
	end
	hl.on("window.open", function(w)
		if w and (w.title or ""):lower():find("picture.?in.?picture") then
			if timer then
				timer:set_enabled(true)
			else
				timer = hl.timer(tick, { timeout = 150, type = "repeat" })
			end
		end
	end)
end

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
