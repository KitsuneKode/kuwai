local K = require("kuwai.core")

local dsp = hl.dsp

K.privacy = K.privacy
	or {
		windows = "^(Bitwarden|bitwarden|org\\.keepassxc\\.KeePassXC|1Password|pinentry-.*|gcr-prompter|org\\.telegram\\.desktop|vesktop|discord|com\\.rtosta\\.zapzap|signal|Signal)$",
		layers = "^(kuwai-notifs|kuwai-center|kuwai-island|kuwai-islandbar|kuwai-assistant|notifications|swaync-notification-window|swaync-control-center)$",
	}

function kuwai.privacy_resync()
	K.set_state("sharing", "0")
	hl.exec_cmd(K.bin .. "/kuwai notifs mute-off")
	return hl.dsp.no_op()
end

if K.feature("screenshare_privacy") then
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
	K.set_state("sharing", "0")

	local shares, engaged = 0, false
	local held, grace = 0, 0
	function kuwai.capture_reset()
		held = 0
		grace = os.time() + 4
		return hl.dsp.no_op()
	end
	function kuwai.capture_hold(on)
		held = math.max(0, held + (on and 1 or -1))
		if held == 0 then
			grace = os.time() + 4
		end
		return hl.dsp.no_op()
	end
	local run = 0
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
		K.set_state("sharing", "1")
		hl.exec_cmd(K.bin .. "/kuwai notifs mute-on")
		K.notify("Sharing your screen — notifications muted, private apps hidden", 3000, "info")
	end
	function kuwai.privacy_resync()
		K.set_state("sharing", engaged and "1" or "0")
		hl.exec_cmd(K.bin .. "/kuwai notifs " .. (engaged and "mute-on" or "mute-off"))
		return hl.dsp.no_op()
	end
	hl.on("screenshare.state", function(active)
		if active then
			shares = shares + 1
			if held == 0 and os.time() >= grace then
				privacy(true)
			end
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
				K.set_state("sharing", "0")
				hl.exec_cmd(K.bin .. "/kuwai notifs mute-off")
			elseif shares == 0 then
				privacy(false)
			end
		end
	end)
end

if K.feature("persistent_size") then
	pcall(hl.window_rule, { name = "remember-float-size", match = { float = true }, persistent_size = true })
end

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

local AC
for _, name in ipairs({ "ACAD", "AC", "AC0", "ADP0", "ADP1", "ACAD0" }) do
	if K.read_line("/sys/class/power_supply/" .. name .. "/online") then
		AC = "/sys/class/power_supply/" .. name .. "/online"
		break
	end
end

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
		local display_changed = false
		if K.feature("auto_display") and K.display and K.display.reconcile then
			K.display.reconcile()
		elseif K.feature("auto_display") and K.state["display_auto"] ~= "accurate" then
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
			for _, x in ipairs(hl.get_windows() or {}) do
				if is_game(x) and (x.fullscreen or 0) > 0 then
					return
				end
			end
			gaming = false
			hl.dispatch(dsp.reload_config())
		end
	end
	hl.on("window.fullscreen", sync)
	hl.on("window.destroy", function(w)
		if gaming and is_game(w) then
			sync(nil)
		end
	end)
end

K.night = K.night or { warm = 4200, start = 20, stop = 6 }

local function sun_hours(lat, lon, t)
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
		if K.night.lat and K.night.lon then
			local rise, set = sun_hours(K.night.lat, K.night.lon, os.time())
			if not rise then
				return "day"
			end
			return (h >= set or h < rise) and "night" or "day"
		end
		local s = tonumber(K.night.start) or 20
		local e = tonumber(K.night.stop) or 6
		return (s > e and (h >= s or h < e) or (s <= e and h >= s and h < e)) and "night" or "day"
	end
	local function apply(p)
		if p == "night" and not (K.display and K.display.current() == "accurate") then
			hl.exec_cmd("hyprctl hyprsunset temperature " .. K.night.warm)
		else
			hl.exec_cmd(K.night_off)
		end
	end
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
		end, { timeout = 3000, type = "oneshot" })
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

if K.feature("hold_super") then
	local SUPER = { [133] = true, [134] = true }
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
						hl.dispatch(dsp.global("kuwai:keys-open"))
					end
				end, { timeout = 650, type = "oneshot" })
			elseif state == 0 then
				held = false
				token = token + 1
			end
		elseif state == 1 then
			token = token + 1
			if held and opened then
				opened = false
				hl.dispatch(dsp.global("kuwai:keys-close"))
			end
		end
	end)
end

if K.feature("island_switcher") then
	local ALT = { [64] = true, [108] = true }
	hl.on("input.keyboard.key", function(code, _, state)
		if state == 0 and ALT[code] and K.alt_switch then
			K.alt_switch = false
			hl.dispatch(dsp.global("kuwai:switch-commit"))
		end
	end)
end
