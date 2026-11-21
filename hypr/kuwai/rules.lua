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

rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })

rule({ name = "xwayland-menus", match = { class = "^$", title = "^$" }, no_blur = true })
rule({
	name = "xwayland-drag-fix",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

rule({ name = "flat-tiles", match = { float = false }, no_shadow = true })

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
rule({
	name = "mini-player",
	match = { class = "^([Cc]ider|[Ss]potify|feishin|org\\.gnome\\.Lollypop)$", title = "^(.*[Mm]ini ?[Pp]layer.*)$" },
	tag = "+pip",
	float = true,
	pin = true,
})
rule({ name = "pip-look", match = { tag = "pip" }, opacity = "1.0 override 1.0 override", no_dim = true, no_blur = true })

rule({ name = "idle-media", match = { class = "^(.*celluloid.*|.*mpv.*|.*vlc.*|.*[Ss]potify.*|.*[Cc]ider.*)$" }, idle_inhibit = "fullscreen" })
rule({ name = "idle-browsers", match = { class = "^(.*LibreWolf.*|.*floorp.*|.*brave-browser.*|.*firefox.*|.*chromium.*|.*zen.*|google-chrome.*|.*vivaldi.*)$" }, idle_inhibit = "fullscreen" })
rule({ name = "video-content", match = { class = "^(mpv|vlc|io\\.github\\.celluloid_player\\.Celluloid|haruna|clapper)$" }, content = "video" })
rule({
	name = "no-auto-hdr-work",
	match = { class = "^(kitty|com\\.mitchellh\\.ghostty|foot|footclient|Alacritty|org\\.wezfurlong\\.wezterm|code|Code|neovide|emacs|zeditor)$" },
	no_auto_hdr = true,
})

rule({ name = "vrr-off", match = { class = ".*" }, no_vrr = true })
rule({ name = "vrr-games", match = { content = "game" }, no_vrr = false })
rule({ name = "vrr-video", match = { content = "video" }, no_vrr = false })

rule({ name = "games", match = { class = "^(steam_app_.*|gamescope|.*\\.exe|Minecraft.*|cs2|dota2)$" }, immediate = true, content = "game", idle_inhibit = "fullscreen", no_blur = true, no_shadow = true, no_vrr = false })
rule({ name = "games-title", match = { title = "^(.*\\.exe|.*[Mm]inecraft.*)$" }, immediate = true, content = "game" })
rule({ name = "steam-friends", match = { class = "^([Ss]team)$", title = "^(Friends List|Steam Settings)$" }, float = true })

rule({ name = "jb-splash-tag", match = { class = "^(jetbrains-.*)$", title = "^(splash)$", float = true }, tag = "+jetbrains-splash" })
rule({ name = "jb-splash", match = { tag = "jetbrains-splash" }, center = true, no_focus = true, border_size = 0 })
rule({ name = "jb-popup-tag", match = { class = "^(jetbrains-.*)$", title = "^()$", float = true }, tag = "+jetbrains" })
rule({ name = "jb-popup", match = { tag = "jetbrains" }, center = true, stay_focused = true, border_size = 0 })
rule({ name = "jb-popup-size", match = { class = "^(jetbrains-.*)$", title = "^()$", float = true }, min_size = "monitor_w*0.5 monitor_h*0.5" })
rule({ name = "jb-tooltips", match = { class = "^(jetbrains-.*)$", title = "^(win.*)$", float = true }, no_initial_focus = true })
rule({ name = "jb-mouse", match = { class = "^(jetbrains-.*)$" }, no_follow_mouse = true })

rule({ name = "satty", match = { class = "^(com\\.gabm\\.satty)$" }, float = true, center = true, size = "monitor_w*0.82 monitor_h*0.82" })
rule({ name = "kuwai-edit", match = { class = "^(kuwai-edit)$" }, float = true, center = true, size = "1100 760" })
rule({ name = "recorder-picker", match = { initial_class = "^(recorder-picker)$" }, float = true, center = true, size = "500 250", stay_focused = true })
rule({ name = "kittymux-hud", match = { class = "^(kittymux-hud)$" }, float = true, center = true, fullscreen_state = "0 0", size = "700 420" })
rule({ name = "float-term", match = { class = "^(float-term)$" }, float = true, fullscreen_state = "0 0", size = "730 480", move = "(monitor_w-760) (monitor_h-510)" })
rule({ name = "drop-term", match = { class = "^(drop-term)$" }, float = true, fullscreen_state = "0 0", size = "930 500", move = "((monitor_w-930)/2) 150" })
rule({ name = "warp-tile", match = { class = "^dev\\.warp\\.Warp$" }, tile = true })
rule({ name = "xwaylandvideobridge", match = { class = "^(xwaylandvideobridge)$" }, no_initial_focus = true, no_focus = true, no_anim = true, no_blur = true, opacity = "0.0 override", float = true, max_size = "1 1" })
rule({ name = "pypr-noanim", match = { tag = "pypr_noanim" }, no_anim = true })

layer({ name = "xray-default", match = { namespace = "negative:^(glass-osd|kuwai-.*|voxtype-osd)$" }, xray = true })

layer({ name = "kuwai-glass", match = { namespace = "^kuwai-.*$" }, blur = true, ignore_alpha = 0.3, xray = false, no_anim = true })
layer({ name = "kuwai-island-shape", match = { namespace = "^kuwai-(island|islandbar|osd|auth)$" }, ignore_alpha = 0.75 })
layer({ name = "kuwai-toasts", match = { namespace = "^kuwai-notifs$" }, ignore_alpha = 0.7 })
layer({ name = "kuwai-saver", match = { namespace = "^kuwai\\.(screensaver|saver-film|fade)$" }, no_anim = true })
layer({ name = "kuwai-wallpaper", match = { namespace = "^kuwai\\.wallpaper$" }, no_anim = true })
layer({ name = "kuwai-wallfx", match = { namespace = "^kuwai\\.wallfx$" }, no_anim = true })
layer({ name = "kuwai-auth-private", match = { namespace = "^kuwai-auth$" }, no_screen_share = true })
layer({ name = "kuwai-scrim", match = { namespace = "^kuwai\\.scrim$" }, no_anim = true })
layer({ name = "glass-osd", match = { namespace = "^glass-osd$" }, blur = true, ignore_alpha = 0.3, xray = false, no_anim = true })
layer({ name = "voxtype-osd", match = { namespace = "^voxtype-osd$" }, blur = true, ignore_alpha = 0.5 })
layer({ name = "quickshell", match = { namespace = "^quickshell.*$" }, blur = true, ignore_alpha = 0 })

layer({ name = "bars", match = { namespace = "^(waybar|gtk-layer-shell:shell:bar|shell:bar)$" }, blur = true, blur_popups = true, ignore_alpha = 0.5 })
layer({ name = "menus", match = { namespace = "^(rofi|vicinae|waycal|launcher|logout_dialog|wlogout)$" }, blur = true, blur_popups = true, ignore_alpha = 0.5 })
layer({ name = "launcher-dim", match = { namespace = "^(launcher)$" }, dim_around = true })
layer({ name = "vicinae-fast", match = { namespace = "^vicinae$" }, no_anim = true })
layer({ name = "notifications", match = { namespace = "^(notifications|swaync-notification-window|swaync-control-center|shell:notifications)$" }, blur = true, ignore_alpha = 0.69, animation = "slide right" })
layer({ name = "kittymux-panel", match = { namespace = "^kittymux-panel$" }, animation = "slide left" })
layer({ name = "instant", match = { namespace = "^(selection|hyprpicker|walker|overview|anyrun|indicator.*|osk|noanim|quickshell:overview|gtk4-layer-shell)$" }, no_anim = true })

pcall(hl.workspace_rule, { workspace = "special:special", gaps_out = 30 })
pcall(hl.workspace_rule, { workspace = "special:notes", gaps_out = 30 })

return R
