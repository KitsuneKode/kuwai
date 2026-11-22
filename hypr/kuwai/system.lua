local K = require("kuwai.core")

K.config({
	misc = {
		vrr = 3,
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,
		animate_manual_resizes = true,
		animate_mouse_windowdragging = true,
		enable_swallow = false,
		swallow_regex = "^(kitty|com\\.mitchellh\\.ghostty|foot|footclient|Alacritty|org\\.wezfurlong\\.wezterm)$",
		focus_on_activate = true,
		on_focus_under_fullscreen = 2,
		initial_workspace_tracking = 0,
		allow_session_lock_restore = true,
		session_lock_xray = false,
		anr_missed_pings = 5,
		disable_scale_notification = true,
		screencopy_force_8b = true,
		close_special_on_empty = true,
		middle_click_paste = true,
	},

	binds = {
		scroll_event_delay = 0,
		hide_special_on_workspace_change = true,
		workspace_back_and_forth = true,
		allow_workspace_cycles = true,
		movefocus_cycles_fullscreen = false,
		drag_threshold = 10,
	},

	layers = {
		allow_new_top_layers_over_existing_fullscreen = true,
	},

	xwayland = {
		enabled = true,
		force_zero_scaling = true,
		use_nearest_neighbor = false,
	},

	render = {
		direct_scanout = 2,
		cm_enabled = true,
		cm_auto_hdr = 0,
		send_content_type = true,
	},

	ecosystem = {
		no_update_news = true,
		no_donation_nag = true,
	},

	debug = {
		disable_logs = false,
		error_position = 0,
	},
})

local first_launch = #(hl.get_monitors() or {}) == 0
if first_launch then
	hl.env("KUWAI_PERMISSIONS", "1")
end
K.config({ ecosystem = { enforce_permissions = first_launch or os.getenv("KUWAI_PERMISSIONS") == "1" } })

local function allow(binary, kind)
	pcall(hl.permission, { binary = binary, type = kind, mode = "allow" })
end

for _, bin in ipairs({
	"/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland",
	"/usr/bin/grim",
	"/usr/bin/grimblast",
	K.home .. "/.local/lib/hyde/screenshot/grimblast",
	"/usr/bin/slurp",
	"/usr/bin/hyprpicker",
	"/usr/bin/hyprlock",
	"/usr/bin/hyprshot",
	"/usr/bin/hyprcap",
	"/usr/bin/wf-recorder",
	"/usr/bin/wl-screenrec",
	"/usr/bin/gpu-screen-recorder",
	"/usr/bin/quickshell",
	"/usr/bin/wayvnc",
	"/usr/bin/hyprland-share-picker",
	"/usr/bin/snappy-switcher",
	"/usr/bin/gsr-kms-server",
	"/usr/bin/satty",
	((K.data_home .. "/t3code/hyprland-capture/t3-hyprland-snap-shot"):gsub("%.", "\\.")),
}) do
	allow(bin, "screencopy")
end

for _, bin in ipairs({
	"/usr/bin/hyprpicker",
	"/usr/bin/slurp",
	"/usr/bin/quickshell",
	"/usr/bin/wayvnc",
	"/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland",
}) do
	allow(bin, "cursorpos")
end

allow("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "input-capture")
