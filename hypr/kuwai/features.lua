local K = require("kuwai.core")

local F = {
	defaults = {
		launch_focus = true,
		quake = true,
		minimize = true,
		per_monitor_ws = true,
		desktops = false,
		layouts = true,
		screenshare_privacy = true,
		auto_battery = true,
		auto_game = true,
		auto_display = true,
		night_light = false,
		persistent_size = true,
		hold_super = true,
		wobble = false,
		resize_mode = true,
		remember_place = true,
		pip_dodge = true,
		focus_sessions = true,
		overview = true,
		island_switcher = true,
		clamshell = true,
		battery_guard = true,
		session_restore = true,
	},
	describe = {
		input_method = "Start fcitx5 (or ibus) for typing other scripts: Japanese, Chinese, Korean, Indic…",
		launch_focus = "App keys focus an open window first (press again for the next)",
		quake = "Super+` drop-down console",
		minimize = "Super+O hide window, Super+Shift+O bring back",
		per_monitor_ws = "Each screen has its own workspaces 1–10",
		desktops = "Desktops span every screen (switch all screens together)",
		layouts = "Super+Alt+L: scrolling → dwindle → monocle → floating",
		screenshare_privacy = "DND and private apps hidden while sharing",
		auto_battery = "Battery mode when unplugged",
		auto_game = "Effects off while a fullscreen game runs",
		auto_display = "Accurate while a colour app is open; Movie when a player is focused",
		night_light = "Warm screens from sunset to sunrise",
		persistent_size = "Floating apps remember their size",
		hold_super = "Hold Super to peek at the shortcuts",
		wobble = "Springy window dragging",
		resize_mode = "Super+Ctrl+S: resize with the arrows",
		remember_place = "Floating apps reopen where you left them",
		pip_dodge = "Picture-in-picture steps aside for a pointer passing by, never for one reaching for it; a drag settles in the corner it was thrown to",
		focus_sessions = "Super+Ctrl+G: 25-minute focus session",
		overview = "Mission Control: every workspace, live",
		island_switcher = "Alt+Tab: the island's window switcher with live previews",
		clamshell = "Lid closed with an external screen: panel off, no lock",
		battery_guard = "Critical battery: save the session and suspend",
		session_restore = "Reopen your apps on their workspaces after a crash or reboot",
	},
}
F.defaults.input_method = false

K.features = K.features or {}

function K.feature(name)
	if K.features[name] ~= nil then
		return K.features[name] and true or false
	end
	local s = K.state["feature." .. name]
	if s == "on" then
		return true
	elseif s == "off" then
		return false
	end
	return F.defaults[name] == true
end

_G.kuwai = _G.kuwai or {}

function kuwai.feature(name, on)
	if F.defaults[name] == nil then
		return "no feature " .. tostring(name)
	end
	if on == nil then
		return K.feature(name)
	end
	K.set_state("feature." .. name, on and "on" or "off")
	K.notify((F.describe[name] or name) .. (on and " — on" or " — off"), 2000)
	hl.dispatch(hl.dsp.reload_config())
	return on
end

function kuwai.features()
	local names = {}
	for n in pairs(F.defaults) do
		names[#names + 1] = n
	end
	table.sort(names)
	local out = {}
	for _, n in ipairs(names) do
		out[#out + 1] = ("%s=%s\t%s"):format(n, K.feature(n) and "on" or "off", F.describe[n] or "")
	end
	return table.concat(out, "\n")
end

return F
