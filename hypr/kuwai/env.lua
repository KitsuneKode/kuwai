-- kuwai.env — session environment for the compositor and everything it spawns.
-- hl.env doesn't expand $VARS: build strings in Lua.

local K = require("kuwai.core")

local set = hl.env

-- Session identity (portals, screen sharing, xdg-desktop-portal-hyprland).
set("XDG_CURRENT_DESKTOP", "Hyprland")
set("XDG_SESSION_TYPE", "wayland")
set("XDG_SESSION_DESKTOP", "Hyprland")

-- Toolkits: Wayland first, X11 as the fallback.
set("GDK_BACKEND", "wayland,x11,*")
set("QT_QPA_PLATFORM", "wayland;xcb")
set("SDL_VIDEODRIVER", "wayland,x11")
set("CLUTTER_BACKEND", "wayland")
set("ELECTRON_OZONE_PLATFORM_HINT", "auto")
set("MOZ_ENABLE_WAYLAND", "1")
set("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
set("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
set("QT_QPA_PLATFORMTHEME", K.state["qt_theme"] or "qt5ct")
-- XWayland apps render at 1x (xwayland.force_zero_scaling); GDK_SCALE keeps
-- GTK2/3 X11 apps readable without blurry upscaling.
set("GDK_SCALE", "1")

-- Cursor: one theme for Wayland (hyprcursor/XCURSOR) and XWayland.
local cursor_theme = K.state["cursor_theme"] or "macOS"
local cursor_size = K.state["cursor_size"] or "24"
set("XCURSOR_THEME", cursor_theme)
set("XCURSOR_SIZE", cursor_size)
set("HYPRCURSOR_THEME", cursor_theme)
set("HYPRCURSOR_SIZE", cursor_size)
K.cursor = { theme = cursor_theme, size = cursor_size }

-- SSH agent: gnome-keyring no longer ships one; gcr-ssh-agent.socket does.
set("SSH_AUTH_SOCK", K.runtime .. "/gcr/ssh")

-- Hyprland itself reads HYPRLAND_CONFIG as its config path, and HyDE's theme
-- switcher only checks that it's readable: point both at the real entry.
-- (HyDE used to export its hyprlang file here — on 0.57 that's parsed as Lua
-- and the whole session comes up empty.)
set("HYPRLAND_CONFIG", K.hypr .. "/hyprland.lua")

-- PATH: kuwai's bin, ~/.local/bin and HyDE's script dir, each added once.
-- (hl.env persists on the live process, so a naive append would grow PATH by
-- one copy per `hyprctl reload`.)
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
-- The other kuwai copy's bin (stable ↔ dev) drops out: one `rice` on PATH,
-- the one this session runs.
local others = { [K.home .. "/Projects/rice/bin"] = true, [K.home .. "/Projects/kuwai/bin"] = true, [(os.getenv("XDG_DATA_HOME") or (K.home .. "/.local/share")) .. "/kuwai/bin"] = true }
for dir in path:gmatch("[^:]+") do
	if not (others[dir] and dir ~= K.bin) then
		add(dir)
	end
end
add(K.home .. "/.local/bin", true)
add(K.bin, true)
if K.exists(K.home .. "/.local/lib/hyde/globalcontrol.sh") then
	add(K.home .. "/.local/lib/hyde")
end
set("PATH", table.concat(parts, ":"))

set("KUWAI_ROOT", K.root)
