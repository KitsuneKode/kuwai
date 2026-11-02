-- kuwai.rules — window, layer and workspace rules that make the desktop behave.
-- App-specific taste (sizes, opacities, which app lives where) is user.lua's.
--
-- Effects are evaluated top to bottom and the last match wins, so specific
-- rules sit below general ones. Static effects (float, size, move, workspace…)
-- are decided once, at map time, from the initial class/title.

local K = require("kuwai.core")

local R = { named = {} }

local function rule(spec)
	local ok, h = pcall(hl.window_rule, spec)
	if not ok then
		K.err("window_rule " .. tostring(spec.name or "?") .. ": " .. tostring(h))
		return nil
	end
	if spec.name then
		R.named[spec.name] = h
	end
	return h
end

local function layer(spec)
	local ok, err = pcall(hl.layer_rule, spec)
	if not ok then
		K.err("layer_rule " .. tostring(spec.name or "?") .. ": " .. tostring(err))
	end
end

R.rule, R.layer = rule, layer

---------------------------------------------------------------------------
-- Everyone
---------------------------------------------------------------------------
-- Apps asking to maximize themselves (Chromium/Electron at start, mostly) put
-- tiled windows into fullscreen mode 1, where they refuse moves and resizes.
-- Ignore the request; Super+F11 / the gestures still fullscreen on purpose.
rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

-- XWayland: menus/tooltips with no class or title — no blur, and don't let
-- the invisible drag helper steal focus.
rule({ name = "xwayland-menus", match = { class = "^$", title = "^$" }, no_blur = true })
rule({
	name = "xwayland-drag-fix",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- Depth: tiled windows sit flat on the desktop, only floating ones cast a
-- shadow. (The 0.53 conversion had this inverted.)
rule({ name = "flat-tiles", match = { float = false }, no_shadow = true })

---------------------------------------------------------------------------
-- Dialogs, pickers, portals: float and centre
---------------------------------------------------------------------------
local DIALOG_TITLES = table.concat({
	"Open File.*", "Select a File.*", "Open Folder.*", "Save As.*", "Save File.*", "Choose Files.*",
	"Library.*", "File Upload.*", "Confirm to replace files", "File Operation Progress",
	"Authentication Required", "Add Folder to Workspace", "Choose wallpaper.*",
	".*wants to (save|open).*", "Properties for .*", "File Already Exists.*",
	".*Welcome", ".*Shell conflicts.*",
}, "|")

rule({ name = "dialogs", match = { title = "^(" .. DIALOG_TITLES .. ")$" }, float = true, center = true })
rule({ name = "dialogs-initial", match = { initial_title = "^(Open File|Save As.*|Volume Control|Open Folder)$" }, float = true, center = true })
rule({ name = "modals", match = { modal = true }, float = true, center = true })
rule({
	name = "portals",
	match = { class = "^(xdg-desktop-portal-gtk|[Xx]dg-desktop-portal-gtk|org\\.freedesktop\\.impl\\.portal\\.desktop\\.(hyprland|gtk|kde))$" },
	float = true,
	center = true,
	fullscreen_state = "0 0",
	size = "monitor_w*0.55 monitor_h*0.6",
})
rule({ name = "pinentry", match = { class = "^(pinentry-.*|gcr-prompter|org\\.gnome\\.keyring\\..*)$" }, float = true, center = true, stay_focused = true })
rule({ name = "polkit", match = { class = "^(org\\.kde\\.polkit-kde-authentication-agent-1|hyprpolkitagent|polkit-gnome-authentication-agent-1)$" }, float = true, center = true, stay_focused = true })

-- Utility windows that are always small and floating.
rule({
	name = "utilities",
	match = { class = "^(blueman-manager|blueberry\\.py|pavucontrol|pavucontrol-qt|org\\.pulseaudio\\.pavucontrol|nm-connection-editor|nm-applet|nwg-(look|displays)|qt[56]ct|kvantummanager|org\\.kde\\.ark|com\\.github\\.wwmm\\.easyeffects|org\\.kde\\.easyeffects|io\\.missioncenter\\.MissionCenter|Zotero|guifetch|kcm_.*|.*plasmawindowed.*|.*bluedevilwizard|vlc|eglgears|vkcube|hyprland-share-picker|hyprland-run|hyprland-dialog|hyprland-update-screen|hyprland-welcome|hyprland-donate-screen)$" },
	float = true,
	center = true,
})
rule({ name = "utilities-size", match = { class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|nm-connection-editor|io\\.missioncenter\\.MissionCenter|Zotero)$" }, size = "monitor_w*0.45 monitor_h*0.45" })
rule({ name = "wallpaper-picker", match = { title = "^(Choose wallpaper)(.*)$" }, size = "monitor_w*0.6 monitor_h*0.6" })
rule({ name = "dolphin-progress", match = { class = "^(org\\.kde\\.dolphin)$", title = "^(Progress Dialog|Copying) — Dolphin$" }, float = true, move = "40 80" })
rule({ name = "plasma-changeicons", match = { class = "^(plasma-changeicons)$" }, float = true, no_initial_focus = true, move = "999999 999999" })

---------------------------------------------------------------------------
-- Picture-in-picture: pinned bottom-right, a quarter of the screen, never dimmed
---------------------------------------------------------------------------
local PIP = "^([Pp]icture[- ]?[Ii]n[- ]?[Pp]icture)(.*)$"
rule({
	name = "pip",
	match = { initial_title = PIP },
	tag = "+pip",
	float = true,
	pin = true,
	keep_aspect_ratio = true,
	fullscreen_state = "0 0",
	size = "monitor_w*0.25 monitor_h*0.25",
	move = "monitor_w*0.73 monitor_h*0.72",
})
rule({ name = "pip-look", match = { tag = "pip" }, opacity = "1.0 override 1.0 override", no_dim = true, no_blur = true })

---------------------------------------------------------------------------
-- Media, games, idle
---------------------------------------------------------------------------
rule({ name = "idle-media", match = { class = "^(.*celluloid.*|.*mpv.*|.*vlc.*|.*[Ss]potify.*|.*[Cc]ider.*)$" }, idle_inhibit = "fullscreen" })
rule({ name = "idle-browsers", match = { class = "^(.*LibreWolf.*|.*floorp.*|.*brave-browser.*|.*firefox.*|.*chromium.*|.*zen.*|google-chrome.*|.*vivaldi.*)$" }, idle_inhibit = "fullscreen" })
rule({ name = "video-content", match = { class = "^(mpv|vlc|io\\.github\\.celluloid_player\\.Celluloid)$" }, content = "video" })

-- VRR only where it helps. On 0.57 a fullscreen window turns adaptive sync on
-- whatever the monitor's vrr mode says (even 0), and an LCD whose refresh
-- follows a terminal's or browser's uneven frame rate flickers and pulses in
-- brightness. So: off for every window, back on for games and video.
rule({ name = "vrr-off", match = { class = ".*" }, no_vrr = true })
rule({ name = "vrr-games", match = { content = "game" }, no_vrr = false })
rule({ name = "vrr-video", match = { content = "video" }, no_vrr = false })

-- Games tear (lowest latency) and are marked as games, which lets VRR and the
-- cursor's no_break_fs_vrr logic treat them right.
rule({ name = "games", match = { class = "^(steam_app_.*|gamescope|.*\\.exe|Minecraft.*|cs2|dota2)$" }, immediate = true, content = "game", idle_inhibit = "fullscreen", no_blur = true, no_shadow = true, no_vrr = false })
rule({ name = "games-title", match = { title = "^(.*\\.exe|.*[Mm]inecraft.*)$" }, immediate = true, content = "game" })
rule({ name = "steam-friends", match = { class = "^([Ss]team)$", title = "^(Friends List|Steam Settings)$" }, float = true })

---------------------------------------------------------------------------
-- JetBrains IDEs: splash and popups behave
---------------------------------------------------------------------------
rule({ name = "jb-splash-tag", match = { class = "^(jetbrains-.*)$", title = "^(splash)$", float = true }, tag = "+jetbrains-splash" })
rule({ name = "jb-splash", match = { tag = "jetbrains-splash" }, center = true, no_focus = true, border_size = 0 })
rule({ name = "jb-popup-tag", match = { class = "^(jetbrains-.*)$", title = "^()$", float = true }, tag = "+jetbrains" })
rule({ name = "jb-popup", match = { tag = "jetbrains" }, center = true, stay_focused = true, border_size = 0 })
rule({ name = "jb-popup-size", match = { class = "^(jetbrains-.*)$", title = "^()$", float = true }, min_size = "monitor_w*0.5 monitor_h*0.5" })
rule({ name = "jb-tooltips", match = { class = "^(jetbrains-.*)$", title = "^(win.*)$", float = true }, no_initial_focus = true })
rule({ name = "jb-mouse", match = { class = "^(jetbrains-.*)$" }, no_follow_mouse = true })

---------------------------------------------------------------------------
-- The rice's own windows and kuwai's terminal variants
---------------------------------------------------------------------------
rule({ name = "satty", match = { class = "^(com\\.gabm\\.satty)$" }, float = true, center = true, size = "monitor_w*0.82 monitor_h*0.82" })
rule({ name = "rice-edit", match = { class = "^(rice-edit)$" }, float = true, center = true, size = "1100 760" })
rule({ name = "recorder-picker", match = { initial_class = "^(recorder-picker)$" }, float = true, center = true, size = "500 250", stay_focused = true })
rule({ name = "kittymux-hud", match = { class = "^(kittymux-hud)$" }, float = true, center = true, fullscreen_state = "0 0", size = "700 420" })
-- --class float-term / drop-term (Super+Alt+T / Super+Ctrl+T): anchored, local
-- to whichever monitor they open on.
rule({ name = "float-term", match = { class = "^(float-term)$" }, float = true, fullscreen_state = "0 0", size = "730 480", move = "(monitor_w-760) (monitor_h-510)" })
rule({ name = "drop-term", match = { class = "^(drop-term)$" }, float = true, fullscreen_state = "0 0", size = "930 500", move = "((monitor_w-930)/2) 150" })
rule({ name = "warp-tile", match = { class = "^dev\\.warp\\.Warp$" }, tile = true })
rule({ name = "xwaylandvideobridge", match = { class = "^(xwaylandvideobridge)$" }, no_initial_focus = true, no_focus = true, no_anim = true, no_blur = true, opacity = "0.0 override", float = true, max_size = "1 1" })
rule({ name = "pypr-noanim", match = { tag = "pypr_noanim" }, no_anim = true })

---------------------------------------------------------------------------
-- Layers
---------------------------------------------------------------------------
-- Bars and panels blur only the wallpaper (xray): cheap, and steady while
-- windows move under them. The rice's glass (rice-*, glass-osd) is excluded:
-- its glass must show the real windows behind it.
layer({ name = "xray-default", match = { namespace = "negative:^(glass-osd|rice-.*|voxtype-osd)$" }, xray = true })

-- The rice: every surface is a layer named rice-*, draws its own glass and its
-- own motion. Blur only under the card (alpha > 0.3), real windows behind it.
layer({ name = "rice-glass", match = { namespace = "^rice-.*$" }, blur = true, ignore_alpha = 0.3, xray = false, no_anim = true })
-- The island and what grows out of it (near-opaque black): blur only the
-- shape itself. At 0.3 the soft shadow around a panel was blurred too, which
-- showed as a square halo behind the rounded panel.
layer({ name = "rice-island-shape", match = { namespace = "^rice-(island|islandbar|osd|auth)$" }, ignore_alpha = 0.75 })
-- The center's scrim: deliberately outside rice-* so nothing blurs under it.
layer({ name = "rice-scrim", match = { namespace = "^rice\\.scrim$" }, no_anim = true })
layer({ name = "glass-osd", match = { namespace = "^glass-osd$" }, blur = true, ignore_alpha = 0.3, xray = false, no_anim = true })
layer({ name = "voxtype-osd", match = { namespace = "^voxtype-osd$" }, blur = true, ignore_alpha = 0.5 })
layer({ name = "quickshell", match = { namespace = "^quickshell.*$" }, blur = true, ignore_alpha = 0 })

layer({ name = "bars", match = { namespace = "^(waybar|gtk-layer-shell:shell:bar|shell:bar)$" }, blur = true, blur_popups = true, ignore_alpha = 0.5 })
layer({ name = "menus", match = { namespace = "^(rofi|vicinae|waycal|launcher|logout_dialog|wlogout)$" }, blur = true, blur_popups = true, ignore_alpha = 0.5 })
layer({ name = "launcher-dim", match = { namespace = "^(launcher)$" }, dim_around = true })
layer({ name = "vicinae-fast", match = { namespace = "^vicinae$" }, no_anim = true })
layer({ name = "notifications", match = { namespace = "^(notifications|swaync-notification-window|swaync-control-center|shell:notifications)$" }, blur = true, ignore_alpha = 0.69, animation = "slide right" })
layer({ name = "kittymux-panel", match = { namespace = "^kittymux-panel$" }, animation = "slide left" })
-- Pickers and overlays must appear on the same frame.
layer({ name = "instant", match = { namespace = "^(selection|hyprpicker|walker|overview|anyrun|indicator.*|osk|noanim|quickshell:overview|gtk4-layer-shell)$" }, no_anim = true })

---------------------------------------------------------------------------
-- Workspaces
---------------------------------------------------------------------------
pcall(hl.workspace_rule, { workspace = "special:special", gaps_out = 30 })
pcall(hl.workspace_rule, { workspace = "special:notes", gaps_out = 30 })

return R
