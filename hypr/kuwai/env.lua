local K = require("kuwai.core")

local set = hl.env

set("XDG_CURRENT_DESKTOP", "Hyprland")
set("XDG_SESSION_TYPE", "wayland")
set("XDG_SESSION_DESKTOP", "Hyprland")

set("GDK_BACKEND", "wayland,x11,*")
set("QT_QPA_PLATFORM", "wayland;xcb")
set("SDL_VIDEODRIVER", "wayland,x11")
set("CLUTTER_BACKEND", "wayland")
set("ELECTRON_OZONE_PLATFORM_HINT", "auto")
set("MOZ_ENABLE_WAYLAND", "1")
set("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
set("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
set("QT_QPA_PLATFORMTHEME", K.state["qt_theme"] or (K.has("qt6ct") and "qt6ct" or "qt5ct"))
set("GDK_SCALE", "1")
set("ACCESSIBILITY_ENABLED", "1")
set("QT_LINUX_ACCESSIBILITY_ALWAYS_ON", "1")

local default_cursor = (K.exists(K.data_home .. "/icons/macOS/index.theme") or K.exists("/usr/share/icons/macOS/index.theme")) and "macOS" or "Adwaita"
local cursor_theme = K.state["cursor_theme"] or default_cursor
local cursor_size = K.state["cursor_size"] or "24"
set("XCURSOR_THEME", cursor_theme)
set("XCURSOR_SIZE", cursor_size)
set("HYPRCURSOR_THEME", cursor_theme)
set("HYPRCURSOR_SIZE", cursor_size)
K.cursor = { theme = cursor_theme, size = cursor_size }

set("SSH_AUTH_SOCK", K.runtime .. "/gcr/ssh")

set("HYPRLAND_CONFIG", K.user_dir .. "/hyprland.lua")

local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
local seen, parts = {}, {}
local function add(dir, front)
	if dir and dir ~= "" and not seen[dir] then
		seen[dir] = true
		if front then
			table.insert(parts, 1, dir)
		else
			parts[#parts + 1] = dir
		end
	end
end
local others = {}
for _, root in ipairs({ K.home .. "/Projects/rice", K.home .. "/Projects/kuwai", (os.getenv("XDG_DATA_HOME") or (K.home .. "/.local/share")) .. "/kuwai" }) do
	others[root .. "/bin"] = true
	others[root .. "/bin/compat"] = true
end
for dir in path:gmatch("[^:]+") do
	if not (others[dir] and dir ~= K.bin) then
		add(dir)
	end
end
add(K.home .. "/.local/bin", true)
add(K.bin, true)
add(K.bin .. "/compat")
if K.hyde then
	add(K.hyde_lib)
end
set("PATH", table.concat(parts, ":"))

set("KUWAI_ROOT", K.root)
