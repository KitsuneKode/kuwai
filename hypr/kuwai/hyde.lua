-- kuwai.hyde — the HyDE bridge. kuwai doesn't need HyDE; when it's installed,
-- this keeps the HyDE pieces the rice hasn't replaced yet working: wallpaper
-- daemon and wallbash, Waybar, rofi pickers, battery alerts, config.toml.
-- Themes come through kuwai.theme (HyDE's theme.conf + wallbash colours).
--
-- As the shell grows (island bar, wallpapers, themes are already the rice's),
-- lines here simply get deleted.

local K = require("kuwai.core")

local LIB = K.home .. "/.local/lib/hyde"
if not K.exists(LIB .. "/globalcontrol.sh") then
	return
end

local function hyde(script)
	return LIB .. "/" .. script
end

hl.on("hyprland.start", function()
	hl.exec_cmd(hyde("wallpaper.sh") .. " --start --global") -- awww + wallbash recolouring
	-- (HyDE's batterynotify.sh is replaced by kuwai's battery_guard.)
	hl.exec_cmd("systemctl --user start hyde-config.service") -- config.toml → HyDE scripts
end)

local bind, group = K.bind, K.group
local rofi = function(cmd)
	return "pkill -x rofi || " .. cmd
end

group("Pickers")
-- Power tools live in Vicinae (Super+Space) when it's installed; the island
-- launcher (Super+A) is for apps and open windows.
local vic = K.has("vicinae")
-- Emoji and glyphs: the island launcher's `:` / `;` modes (HyDE's databases,
-- the rice's UI).
bind("SUPER + comma", "Emoji", hl.dsp.global("rice:emoji"))
bind("SUPER + period", "Glyphs", hl.dsp.global("rice:glyphs"))
bind("SUPER + SHIFT + E", "Find a file", vic and "vicinae cmd launch files:search" or rofi(hyde("rofilaunch.sh") .. " f"))
bind("SUPER + SHIFT + A", "Rofi style", rofi(hyde("rofiselect.sh")))

group("Theming")
-- Wallpapers: the island's panel (Super+Shift+W). Super+Alt+arrows are workspaces.
bind("SUPER + SHIFT + R", "Wallbash mode", rofi(hyde("wallbashtoggle.sh") .. " -m"), { locked = true })
bind("SUPER + SHIFT + U", "Lock screen layout", rofi(hyde("hyprlock.sh") .. " --select"))
bind("CTRL + ALT + W", "Waybar on/off", "pkill -x waybar || hyde-shell waybar", { locked = true })

group("Utilities")
bind("SUPER + SHIFT + G", "Game launcher", hyde("gamelauncher.sh"))
if K.has("hyde-shell") then
	K.apps.monitor = "hyde-shell system.monitor"
end
group(nil)
