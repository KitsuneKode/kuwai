local K = require("kuwai.core")

local LIB = K.hyde_lib
if not K.hyde then
	return
end

local function hyde(script)
	return LIB .. "/" .. script
end

hl.on("hyprland.start", function()
	if K.has("awww-daemon") then
		hl.exec_cmd("awww-daemon --format xrgb")
	end
	hl.exec_cmd("WALLPAPER_AWWW_TRANSITION_DEFAULT=none " .. hyde("wallpaper.sh") .. " --start --global")
	hl.exec_cmd("systemctl --user start hyde-config.service")
end)

local bind, group = K.bind, K.group
local rofi = function(cmd)
	return "pkill -x rofi || " .. cmd
end

group("Pickers")
local vic = K.has("vicinae")
bind("SUPER + SHIFT + E", "Find a file", vic and "vicinae cmd launch files:search" or rofi(hyde("rofilaunch.sh") .. " f"))
bind("SUPER + SHIFT + A", "Rofi style", rofi(hyde("rofiselect.sh")))

group("Theming")
bind("SUPER + SHIFT + R", "Wallbash mode", rofi(hyde("wallbashtoggle.sh") .. " -m"), { locked = true })
bind("SUPER + SHIFT + U", "Lock screen layout", rofi(hyde("hyprlock.sh") .. " --select"))

group("Utilities")
bind("SUPER + SHIFT + G", "Game launcher", hyde("gamelauncher.sh"))
if K.has("hyde-shell") then
	K.apps.monitor = "hyde-shell system.monitor"
end
group(nil)
