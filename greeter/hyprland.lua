-- The login screen's compositor. greetd runs it as its `greeter` user
-- (greeter/install), from the copy greeter/sync keeps in /var/lib/kuwai-greeter.
-- It only lights the screens and runs one client, the rice's login face
-- (shell/greeter.qml); when that exits (a login went through, or it couldn't
-- start), Hyprland exits too and greetd moves on.
--
-- Hyprland is what brings up an NVIDIA card, so this shows on screens that
-- hang off it as well as the laptop's panel (GRUB and SDDM only had the panel).

local ROOT = "/var/lib/kuwai-greeter"

local function read_line(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local l = f:read("l")
	f:close()
	return l
end

-- GPUs: every card that drives a screen, NVIDIA first when a screen hangs
-- off it (kuwai.gpu's auto rule, so the handoff to your session is the same).
local nvidia, others = nil, {}
for n = 0, 7 do
	local vendor = read_line("/sys/class/drm/card" .. n .. "/device/vendor")
	if vendor == "0x10de" then
		nvidia = "/dev/dri/card" .. n
	elseif vendor then
		others[#others + 1] = "/dev/dri/card" .. n
	end
end
if nvidia then
	local lit = false
	for _, kind in ipairs({ "DP", "HDMI-A", "eDP" }) do
		for i = 1, 8 do
			if read_line("/sys/class/drm/" .. nvidia:match("card%d+") .. "-" .. kind .. "-" .. i .. "/status") == "connected" then
				lit = true
			end
		end
	end
	if lit then
		table.insert(others, 1, nvidia)
	else
		others[#others + 1] = nvidia
	end
end
if #others > 1 then
	hl.env("AQ_DRM_DEVICES", table.concat(others, ":"))
end

-- Your screens and keyboard, as your session has them: greeter/sync (which
-- runs as you) writes them as data into home/.config/kuwai-greeter.conf.
-- That file is yours to write, so it is read here as data only, never run:
-- known keys, numbers in range, names from a small alphabet. Anything else in
-- it and the whole file is ignored: the login screen comes up at each
-- screen's preferred mode with a US keyboard, as if there were no file.
--
--   kb_layout=us,de                         a–z 0–9 _ , -
--   kb_variant=,nodeadkeys                  the same, may be empty
--   kb_options=grp:alt_shift_toggle         the same and :
--   monitor=2560x1440@165.003;0;360;1.333333;0;8;srgb;California Institute of Technology 0x1509
--           mode;x;y;scale;transform;bit depth (8|10);colour (or empty);description (last)
local CONF = ROOT .. "/home/.config/kuwai-greeter.conf"
local DEFAULT_KB = { kb_layout = "us", kb_variant = "", kb_options = "" }

local function int(s, lo, hi)
	if type(s) ~= "string" or not s:match("^%-?%d+$") or #s > 6 then
		return nil
	end
	local n = tonumber(s)
	return n and n >= lo and n <= hi and n or nil
end
local function real(s, lo, hi)
	if type(s) ~= "string" or #s > 12 or not (s:match("^%d+$") or s:match("^%d+%.%d+$")) then
		return nil
	end
	local n = tonumber(s)
	return n and n >= lo and n <= hi and n or nil
end
-- A layout xkb has: each name in the list is a file in its symbols folder
-- (names are a–z 0–9 _ -, so never a path of their own).
local XKB = "/usr/share/X11/xkb/symbols/"
local function xkb_has(layouts)
	local f = io.open(XKB .. "us", "r")
	if not f then
		return true -- no xkb data to check against here; Hyprland reports a bad name itself
	end
	f:close()
	local n = 0
	for name in layouts:gmatch("[^,]+") do
		n = n + 1
		local g = io.open(XKB .. name, "r")
		if not g then
			return false
		end
		g:close()
	end
	return n > 0 and n <= 4
end
local COLOUR = { [""] = true, auto = true, srgb = true, wide = true, edid = true, dcip3 = true, dp3 = true, adobe = true }

-- One monitor line, or nil. The description goes to Hyprland as a selector
-- string ("desc:…", matched as a prefix), nothing more.
local function monitor(v)
	local mode, x, y, scale, transform, depth, colour, desc =
		v:match("^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")
	if not mode then
		return nil
	end
	local w, h, hz = mode:match("^(%d+)x(%d+)@([%d%.]+)$")
	w, h, hz = int(w, 320, 16384), int(h, 200, 16384), real(hz, 1, 1000)
	x, y = int(x, -65536, 65536), int(y, -65536, 65536)
	scale, transform, depth = real(scale, 0.25, 4), int(transform, 0, 7), int(depth, 8, 10)
	if not (w and h and hz and x and y and scale and transform and (depth == 8 or depth == 10) and COLOUR[colour]) then
		return nil
	end
	if #desc < 1 or #desc > 120 or not desc:match("^[%w][%w %.%-_()/+&#:]*$") then
		return nil
	end
	local m = {
		output = "desc:" .. desc,
		mode = string.format("%dx%d@%.3f", w, h, hz),
		position = string.format("%dx%d", x, y),
		scale = scale,
		transform = transform,
	}
	-- The session's 10-bit format and colour at login too, so the handoff
	-- doesn't also change the colour depth.
	if depth == 10 then
		m.bitdepth = 10
	end
	if colour ~= "" then
		m.cm = colour
	end
	return m
end

-- The whole file, or nil for "use the defaults".
local function parse(text)
	if type(text) ~= "string" or #text > 8192 then
		return nil
	end
	local kb, screens, seen, lines = { kb_layout = "us", kb_variant = "", kb_options = "" }, {}, {}, 0
	for line in (text:sub(-1) == "\n" and text or text .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + 1
		if lines > 32 or #line > 300 then
			return nil
		end
		if line ~= "" and line:sub(1, 1) ~= "#" then
			local k, v = line:match("^([%l_]+)=(.*)$")
			if not k then
				return nil
			end
			if k == "monitor" then
				local m = monitor(v)
				if not m or #screens >= 8 then
					return nil
				end
				screens[#screens + 1] = m
			elseif k == "kb_layout" or k == "kb_variant" or k == "kb_options" then
				if seen[k] or #v > 64 then
					return nil
				end
				local ok = k == "kb_options" and v:match("^[a-z0-9_,:%-]*$") or v:match("^[a-z0-9_,%-]*$")
				if not ok or (k == "kb_layout" and v == "") then
					return nil
				end
				seen[k], kb[k] = true, v
			else
				return nil
			end
		end
	end
	-- A variant or option belongs to a layout named beside it.
	if (seen.kb_variant or seen.kb_options) and not seen.kb_layout then
		return nil
	end
	if not xkb_has(kb.kb_layout) then
		return nil
	end
	return { kb = kb, screens = screens }
end

local function read_conf(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read(8193)
	f:close()
	return text
end

local ok, conf = pcall(function()
	return parse(read_conf(CONF))
end)
if not ok or not conf then
	conf = { kb = DEFAULT_KB, screens = {} }
end
for _, m in ipairs(conf.screens) do
	hl.monitor(m)
end
-- Every other screen (and every screen, without the file): its own best mode.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
	input = {
		kb_layout = conf.kb.kb_layout,
		kb_variant = conf.kb.kb_variant,
		kb_options = conf.kb.kb_options,
		numlock_by_default = false,
		repeat_delay = 250,
		repeat_rate = 35,
	},
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		background_color = 0x000000,
		session_lock_xray = false,
	},
	animations = { enabled = false },
	ecosystem = { no_update_news = true, no_donation_nag = true },
})

hl.on("hyprland.start", function()
	hl.exec_cmd(ROOT .. "/start")
end)

-- Brightness and volume keys on the login screen (the face shows their HUD,
-- shell/modules/lock/LockOsd). Brightness: the greeter user is in `video`.
-- Volume: only if a sound server runs for it (usually none; harmless).
for _, k in ipairs({
	{ "XF86MonBrightnessUp", ROOT .. "/keys brightness up" },
	{ "XF86MonBrightnessDown", ROOT .. "/keys brightness down" },
	{ "XF86AudioRaiseVolume", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+" },
	{ "XF86AudioLowerVolume", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-" },
	{ "XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" },
	-- The plain F-keys too, as in the session (hypr/kuwai/binds.lua): this
	-- keyboard's top row sends F7/F8/F10, not the XF86 keys, unless Fn is held.
	{ "F8", ROOT .. "/keys brightness up" },
	{ "F7", ROOT .. "/keys brightness down" },
	{ "F10", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" },
}) do
	pcall(hl.bind, k[1], hl.dsp.exec_cmd(k[2]), { locked = true, repeating = true })
end
