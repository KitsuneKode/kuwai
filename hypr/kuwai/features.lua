-- kuwai.features — switches for everything kuwai does on its own initiative.
--
--   kuwai feature                 list, with state
--   kuwai feature NAME on|off     persist and reload
--   hyprctl eval 'kuwai.feature("night_light", false)'
--
-- user.lua can also force one: K.features.wobble = false (wins over the state).

local K = require("kuwai.core")

local F = {
	defaults = {
		launch_focus = true, -- app keys focus an open window (again = next one) before launching
		quake = true, -- Super+` drop-down console over any workspace
		minimize = true, -- Super+O hides a window, Super+Shift+O brings it back
		per_monitor_ws = true, -- each screen owns a block of ten workspace ids (11–20 for the second…)
		desktops = false, -- on: desktops span every screen (Super+3 / Super+Ctrl+→ switch all screens together); off: each screen navigates on its own
		layouts = true, -- Super+Alt+L cycles a workspace: scrolling/dwindle/monocle/floating
		screenshare_privacy = true, -- DND + blacked-out private apps while sharing the screen
		auto_battery = true, -- unplugged → battery mode, plugged in → back
		auto_game = true, -- fullscreen game → effects off without a reload
		auto_display = true, -- colour app → accurate; a focused player → movie; unplugged → battery
		night_light = true, -- warm screens from sunset to sunrise (hyprsunset)
		persistent_size = true, -- floating apps reopen at the size you left them
		hold_super = true, -- hold Super alone ~0.9 s → Shortcuts panel, release → gone
		wobble = false, -- a little spring in windows you drag (off: reads as a gimmick)
		resize_mode = true, -- Super+Ctrl+S: arrows resize until Enter/Esc
		remember_place = true, -- floating apps reopen where you left them
		pip_dodge = true, -- picture-in-picture steps aside for a passing pointer, stays for one reaching for it
		focus_sessions = true, -- Super+Ctrl+G: timed focus with DND
		overview = true, -- Super+Tab… Mission Control (the island's overview)
		island_switcher = true, -- Alt+Tab is the island's switcher (off: snappy-switcher)
		clamshell = true, -- lid closed + external screen: panel off, no lock
		battery_guard = true, -- 10% warning; 4%: save session, then suspend
		session_restore = true, -- snapshot open apps; offer to restore at login
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
-- Off by default: an input method changes how every app takes text.
F.defaults.input_method = false

K.features = K.features or {}

-- Is feature `name` on? Order: user.lua override > persisted state > default.
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
