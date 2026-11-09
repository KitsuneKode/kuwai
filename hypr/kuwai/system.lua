-- kuwai.system — compositor behaviour, rendering, XWayland, permissions.

local K = require("kuwai.core")

K.config({
	misc = {
		vrr = 3, -- default: VRR only for fullscreen games and video
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,
		animate_manual_resizes = true,
		animate_mouse_windowdragging = true,
		enable_swallow = false,
		swallow_regex = "^(kitty|com\\.mitchellh\\.ghostty|foot|footclient|Alacritty|org\\.wezfurlong\\.wezterm)$",
		focus_on_activate = true,
		on_focus_under_fullscreen = 2, -- a new window un-fullscreens the old one
		initial_workspace_tracking = 0,
		allow_session_lock_restore = true, -- a restarted shell can take the lock back
		session_lock_xray = false, -- a monitor with no lock surface must not show the session
		anr_missed_pings = 5,
		disable_scale_notification = true,
		-- 10-bit outputs: keep grim/slurp/screen share on 8-bit buffers so
		-- screenshots and recordings stay compatible.
		screencopy_force_8b = true,
		close_special_on_empty = true,
		middle_click_paste = true,
	},

	binds = {
		scroll_event_delay = 0,
		hide_special_on_workspace_change = true,
		workspace_back_and_forth = true, -- Super+N on the current workspace goes back
		allow_workspace_cycles = true,
		movefocus_cycles_fullscreen = false,
		drag_threshold = 10, -- click vs drag on Super+mouse binds
	},

	layers = {
		allow_new_top_layers_over_existing_fullscreen = true,
	},

	xwayland = {
		enabled = true,
		force_zero_scaling = true, -- crisp X11 apps on fractional scales
		use_nearest_neighbor = false,
	},

	render = {
		direct_scanout = 2, -- auto: zero-copy fullscreen games/video
		cm_enabled = true,
		-- Off until a display preset opts in (kuwai.display). A fullscreen
		-- surface that merely advertises HDR otherwise modesets the Acer
		-- into wide gamut and back: a black flash, wrong greens, and a
		-- stalled frame for every window on that screen. On NVIDIA that
		-- switch also lands while 10-bit is not the mode Hyprland trusts.
		cm_auto_hdr = 0,
		send_content_type = true,
	},

	ecosystem = {
		no_update_news = true,
		no_donation_nag = true,
		-- Set below: only when the allow-list could actually be loaded.
	},

	debug = {
		disable_logs = false,
		error_position = 0,
	},
})

---------------------------------------------------------------------------
-- Permissions (read once at Hyprland start; a reload doesn't change them).
-- Anything not listed here asks first.
---------------------------------------------------------------------------
-- Hyprland reads permission rules only while it is starting (no screens exist
-- yet when the config runs). Enforcing them in a session that didn't start
-- with this config would mean an empty allow-list: a prompt for every
-- screenshot. So: enforce only when the list was loaded at start; reloads keep
-- enforcing via the env marker set then.
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
	"/usr/bin/quickshell", -- island previews, live wallpaper, lock screen
	"/usr/bin/wayvnc",
	"/usr/bin/hyprland-share-picker", -- window/screen thumbnails in the share dialog
	"/usr/bin/snappy-switcher", -- Alt+Tab previews
	"/usr/bin/gsr-kms-server", -- GPU Screen Recorder's capture helper
	"/usr/bin/satty",
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

-- Input capture (Deskflow / Input Leap / remote control) goes through the portal.
allow("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "input-capture")
-- Keyboards stay allowed by default (keyd, voxtype's wtype, ydotool, KDE Connect).
