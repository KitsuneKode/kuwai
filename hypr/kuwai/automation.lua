-- kuwai.automation — things kuwai does on its own. Each one is a feature
-- (kuwai.features) you can switch off: `kuwai feature NAME off`.
-- All event-driven or a cheap sysfs timer; no daemons.

local K = require("kuwai.core")

local dsp = hl.dsp

---------------------------------------------------------------------------
-- Screen-share privacy
---------------------------------------------------------------------------
-- While a real share is live (a capture running > 2.5 s): private apps and
-- notifications are drawn black in it and notifications go quiet; all of it
-- is undone when the share ends. Screenshots are never affected.
-- user.lua can extend K.privacy.
K.privacy = K.privacy
	or {
		windows = "^(Bitwarden|bitwarden|org\\.keepassxc\\.KeePassXC|1Password|pinentry-.*|gcr-prompter|org\\.telegram\\.desktop|vesktop|discord|com\\.rtosta\\.zapzap|signal|Signal)$",
		layers = "^(rice-notifs|rice-center|notifications|swaync-notification-window|swaync-control-center)$",
	}

if K.feature("screenshare_privacy") then
	-- no_screen_share blacks a surface out of *every* capture, screenshots
	-- included, so these exist only while a real share is running.
	local _, wr = pcall(hl.window_rule, { name = "privacy-windows", match = { class = K.privacy.windows }, no_screen_share = true, enabled = false })
	local _, lr = pcall(hl.layer_rule, { name = "privacy-layers", match = { namespace = K.privacy.layers }, no_screen_share = true, enabled = false })
	local function privacy(on)
		for _, r in ipairs({ wr, lr }) do
			if type(r) == "userdata" or type(r) == "table" then
				pcall(function()
					r:set_enabled(on)
				end)
			end
		end
	end
	privacy(false)

	-- Screenshots (grim, the island's previews) are capture sessions too, but
	-- they last a fraction of a second. Only a capture still running after
	-- 2.5 s is a share; only what was switched on is switched back off.
	local shares, engaged = 0, false
	-- The shell's own live previews (Mission Control, the switcher) are captures
	-- too: it says so with `kuwai.capture_hold(true|false)` around them.
	local held, grace = 0, 0
	function kuwai.capture_hold(on)
		held = math.max(0, held + (on and 1 or -1))
		-- Hyprland ends the shell's capture sessions a moment after the panel
		-- closes: keep ignoring captures for a few seconds after the last one.
		if held == 0 then
			grace = os.time() + 4
		end
		return hl.dsp.no_op()
	end
	-- `run` changes whenever captures stop, so a burst of screenshots (each
	-- short, but one always in flight 2.5 s later) isn't taken for a share:
	-- only a capture that never stopped since the timer started counts.
	local run = 0
	-- The check repeats while the capture lasts: one that falls inside a
	-- Mission Control / switcher hold (or its grace) is postponed, not lost,
	-- so a share that began meanwhile is still caught once the hold ends.
	local function check(mine)
		if shares == 0 or run ~= mine or engaged then
			return
		end
		if held > 0 or os.time() < grace then
			hl.timer(function()
				check(mine)
			end, { timeout = 1000, type = "oneshot" })
			return
		end
		engaged = true
		privacy(true)
		hl.exec_cmd(K.bin .. "/rice notifs mute-on")
		K.notify("Sharing your screen — notifications muted, private apps hidden", 3000, "info")
	end
	hl.on("screenshare.state", function(active)
		if active then
			shares = shares + 1
			local mine = run
			hl.timer(function()
				check(mine)
			end, { timeout = 2500, type = "oneshot" })
		else
			shares = math.max(0, shares - 1)
			if shares == 0 then
				run = run + 1
			end
			if shares == 0 and engaged then
				engaged = false
				privacy(false)
				hl.exec_cmd(K.bin .. "/rice notifs mute-off")
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Remember floating sizes; Super+Esc is in binds
---------------------------------------------------------------------------
if K.feature("persistent_size") then
	pcall(hl.window_rule, { name = "remember-float-size", match = { float = true }, persistent_size = true })
end

---------------------------------------------------------------------------
-- Wobble
---------------------------------------------------------------------------
K.config({
	decoration = {
		wobble = {
			enabled = K.feature("wobble"),
			intensity = 0.15,
			stiffness = 260,
			damping = 16,
		},
	},
})
pcall(hl.window_rule, { name = "no-wobble-games", match = { content = "game" }, no_wobble = true })

---------------------------------------------------------------------------
-- Battery: unplugged → battery mode, plugged in → the mode you had
---------------------------------------------------------------------------
local AC
for _, name in ipairs({ "ACAD", "AC", "AC0", "ADP0", "ADP1", "ACAD0" }) do
	if K.read_line("/sys/class/power_supply/" .. name .. "/online") then
		AC = "/sys/class/power_supply/" .. name .. "/online"
		break
	end
end

-- nil when there's no AC adapter to read (a desktop).
function K.ac_online()
	if not AC then
		return nil
	end
	return K.read_line(AC) == "1"
end

if K.feature("auto_battery") and AC then
	local function check()
		local online = K.read_line(AC) == "1"
		local last = K.state["ac_last"]
		local now = online and "1" or "0"
		if last == now then
			return
		end
		K.set_state("ac_last", now)
		-- The display preset's battery layer (kuwai.display) changes with it;
		-- an open colour app (accurate) stays on top.
		local display_changed = false
		if K.feature("auto_display") and K.state["display_auto"] ~= "accurate" then
			local want = (not online) and "battery" or nil
			if K.state["display_auto"] ~= want then
				K.set_state("display_auto", want)
				K.set_state("display_why", want and "On battery" or nil)
				display_changed = true
			end
		end
		local mode = K.state["mode"] or "focus"
		if not online and mode ~= "battery" and mode ~= "gaming" then
			K.set_state("mode_before_battery", mode)
			kuwai.mode("battery")
		elseif online and mode == "battery" and K.state["mode_before_battery"] then
			local back = K.state["mode_before_battery"]
			K.set_state("mode_before_battery", nil)
			kuwai.mode(back)
		elseif display_changed then
			hl.dispatch(dsp.reload_config())
		end
	end
	K.defer(function()
		hl.timer(check, { timeout = 15000, type = "repeat" })
		check()
	end)
end

---------------------------------------------------------------------------
-- Games: a fullscreen game turns the effects off, live; leaving restores.
---------------------------------------------------------------------------
local function is_game(w)
	if not w then
		return false
	end
	if w.content_type == "game" then
		return true
	end
	local c = (w.class or ""):lower()
	return c:match("^steam_app_") ~= nil or c == "gamescope" or c:match("%.exe$") ~= nil or c == "cs2"
end

if K.feature("auto_game") then
	local gaming = false
	local function sync(w)
		local fs_game = w and is_game(w) and (w.fullscreen or 0) > 0
		if fs_game and not gaming and (K.state["mode"] or "focus") ~= "gaming" then
			gaming = true
			K.config({
				animations = { enabled = false },
				decoration = {
					blur = { enabled = false },
					shadow = { enabled = false },
					glow = { enabled = false },
					motion_blur = { enabled = false },
					wobble = { enabled = false },
				},
			})
		elseif gaming and not fs_game then
			-- Still a fullscreen game anywhere? Then stay.
			for _, x in ipairs(hl.get_windows() or {}) do
				if is_game(x) and (x.fullscreen or 0) > 0 then
					return
				end
			end
			gaming = false
			hl.dispatch(dsp.reload_config()) -- exactly what the theme and mode said
		end
	end
	hl.on("window.fullscreen", sync)
	hl.on("window.destroy", function(w)
		if gaming and is_game(w) then
			sync(nil)
		end
	end)
end

---------------------------------------------------------------------------
-- Night light: warm from sunset to sunrise. Acts only at the two edges, so
-- the Night Shift switch in the center still works in between.
---------------------------------------------------------------------------
K.night = K.night or { lat = 27.2353, lon = 94.1053, warm = 4200 } -- North Lakhimpur; user.lua can change

local function sun_hours(lat, lon, t)
	-- NOAA sunrise/sunset (zenith 90.833°), result in local hours.
	local rad, deg = math.pi / 180, 180 / math.pi
	local N = os.date("*t", t).yday
	local lng = lon / 15
	local function calc(rising)
		local tt = N + (((rising and 6 or 18) - lng) / 24)
		local M = 0.9856 * tt - 3.289
		local L = (M + 1.916 * math.sin(M * rad) + 0.020 * math.sin(2 * M * rad) + 282.634) % 360
		local RA = (math.atan(0.91764 * math.tan(L * rad)) * deg) % 360
		RA = (RA + (math.floor(L / 90) * 90 - math.floor(RA / 90) * 90)) / 15
		local sinDec = 0.39782 * math.sin(L * rad)
		local cosDec = math.cos(math.asin(sinDec))
		local cosH = (math.cos(90.833 * rad) - sinDec * math.sin(lat * rad)) / (cosDec * math.cos(lat * rad))
		if cosH > 1 or cosH < -1 then
			return nil
		end
		local H = (rising and (360 - math.acos(cosH) * deg) or (math.acos(cosH) * deg)) / 15
		local T = H + RA - 0.06571 * tt - 6.622
		return (T - lng) % 24
	end
	local offset = (os.time() - os.time(os.date("!*t"))) / 3600
	local r, s = calc(true), calc(false)
	return r and (r + offset) % 24, s and (s + offset) % 24
end
K.sun_hours = sun_hours

if K.feature("night_light") then
	local function phase()
		local now = os.date("*t")
		local h = now.hour + now.min / 60
		local rise, set = sun_hours(K.night.lat, K.night.lon, os.time())
		if not rise then
			return "day"
		end
		return (h >= set or h < rise) and "night" or "day"
	end
	local function apply(p)
		-- The accurate display preset holds Night Shift off (kuwai.display).
		if p == "night" and not (K.display and K.display.current() == "accurate") then
			hl.exec_cmd("hyprctl hyprsunset temperature " .. K.night.warm)
		else
			hl.exec_cmd(K.night_off)
		end
	end
	-- Leaving the accurate preset: warm again if it's night now.
	function K.night_sync()
		local p = phase()
		K.set_state("night_phase", p)
		apply(p)
	end
	hl.on("hyprland.start", function()
		hl.exec_cmd("systemctl --user start hyprsunset.service")
		local p = phase()
		K.set_state("night_phase", p)
		hl.timer(function()
			apply(p)
		end, { timeout = 3000, type = "oneshot" }) -- after hyprsunset is up
	end)
	K.defer(function()
		hl.timer(function()
			local p = phase()
			if p ~= K.state["night_phase"] then
				K.set_state("night_phase", p)
				apply(p)
			end
		end, { timeout = 60000, type = "repeat" })
	end)
end

---------------------------------------------------------------------------
-- Where are you looking? One answer for every surface that appears on its
-- own (toasts, the password prompt): the pointer's screen and the focused
-- screen agree → that one; you typed in the last 5 s → the focused screen
-- (you're reading what you type); otherwise the pointer's screen. Hyprland's
-- Lua exposes key events but not pointer motion, so typing is the signal.
---------------------------------------------------------------------------
local last_key = 0
hl.on("input.keyboard.key", function()
	last_key = os.time()
end)
function kuwai.where()
	local p = hl.get_cursor_pos()
	local focused = hl.get_active_monitor()
	local pointer
	for _, m in ipairs(hl.get_monitors() or {}) do
		local w, h = m.width / (m.scale or 1), m.height / (m.scale or 1)
		if p and p.x >= m.x and p.y >= m.y and p.x < m.x + w and p.y < m.y + h then
			pointer = m.name
		end
	end
	local f = focused and focused.name or ""
	pointer = pointer or f
	local typing = os.time() - last_key <= 5
	local looking = (pointer == f or not typing) and pointer or f
	return string.format('{"looking":%s,"pointer":%s,"focused":%s,"typing":%s}',
		K.json_str(looking), K.json_str(pointer), K.json_str(f), typing and "true" or "false")
end

---------------------------------------------------------------------------
-- Hold Super alone → the Shortcuts panel while held (macOS CheatSheet)
---------------------------------------------------------------------------
if K.feature("hold_super") then
	-- Hold Super alone ~0.65 s → the palette opens and stays (Esc or a click
	-- away closes it). If a real shortcut follows while Super is still held,
	-- the hold was just you thinking: the palette closes again.
	local SUPER = { [133] = true, [134] = true } -- XKB keycodes of Super_L / Super_R
	local token, opened, held, pos = 0, false, false, nil
	hl.on("input.keyboard.key", function(code, _, state)
		if SUPER[code] then
			if state == 1 then
				held = true
				opened = false
				token = token + 1
				local mine = token
				pos = hl.get_cursor_pos()
				hl.timer(function()
					local p = hl.get_cursor_pos()
					local still = pos and p and math.abs(p.x - pos.x) + math.abs(p.y - pos.y) < 8
					if mine == token and held and still then
						opened = true
						hl.dispatch(dsp.global("rice:keys-open"))
					end
				end, { timeout = 650, type = "oneshot" })
			elseif state == 0 then
				held = false
				token = token + 1
			end
		elseif state == 1 then
			token = token + 1 -- any other key: a shortcut, not a hold
			if held and opened then
				opened = false
				hl.dispatch(dsp.global("rice:keys-close"))
			end
		end
	end)
end

---------------------------------------------------------------------------
-- The island switcher: Alt coming up commits the switch.
---------------------------------------------------------------------------
if K.feature("island_switcher") then
	local ALT = { [64] = true, [108] = true } -- XKB keycodes of Alt_L / Alt_R
	hl.on("input.keyboard.key", function(code, _, state)
		if state == 0 and ALT[code] and K.alt_switch then
			K.alt_switch = false
			hl.dispatch(dsp.global("rice:switch-commit"))
		end
	end)
end
