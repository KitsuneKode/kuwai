-- kuwai.input — keyboard, pointer, touchpad and 1:1 gestures.

local K = require("kuwai.core")

K.config({
	input = {
		kb_layout = "us",
		numlock_by_default = false,
		repeat_delay = 250,
		repeat_rate = 35,

		sensitivity = -0.5,
		accel_profile = "flat",
		force_no_accel = true,
		follow_mouse = 1,
		float_switch_override_focus = 1,
		off_window_axis_events = 2,
		follow_mouse_shrink = 4, -- crossing a gap doesn't steal focus
		special_fallthrough = true, -- a scratchpad of floats doesn't block the workspace under it

		touchpad = {
			natural_scroll = true, -- content follows the fingers, like macOS
			disable_while_typing = true,
			clickfinger_behavior = true, -- two-finger click = right click
			tap_to_click = true,
			scroll_factor = 0.7,
		},
	},

	gestures = {
		workspace_swipe_distance = 700,
		workspace_swipe_cancel_ratio = 0.2,
		workspace_swipe_min_speed_to_force = 5,
		workspace_swipe_direction_lock = true,
		workspace_swipe_direction_lock_threshold = 10,
		workspace_swipe_create_new = true,
	},

	cursor = {
		hide_on_key_press = true, -- the pointer gets out of the way while typing
		zoom_factor = 1,
		zoom_rigid = false,
		zoom_disable_aa = true, -- crisp pixels when zoomed (inspection, not photos)
		hotspot_padding = 1,
	},
})

---------------------------------------------------------------------------
-- Gestures. Hyprland rejects a second gesture on the same fingers+direction,
-- so user.lua must unset one before redefining it:
--   hl.gesture({ fingers = 3, direction = "up", action = "unset" })
---------------------------------------------------------------------------
local function gesture(spec)
	local ok, err = pcall(hl.gesture, spec)
	if not ok then
		K.err("gesture " .. spec.fingers .. " " .. spec.direction .. ": " .. tostring(err))
	end
end

local function cmd(c)
	return function()
		hl.exec_cmd(c)
	end
end

local VOL = "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "
local BRIGHT = K.home .. "/Scripts/brightness.sh "

-- Three fingers: workspaces sideways (1:1), volume up/down, pinch float/tile.
gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
gesture({ fingers = 3, direction = "up", action = cmd(VOL .. "5%+") })
gesture({ fingers = 3, direction = "down", action = cmd(VOL .. "5%-") })
gesture({ fingers = 3, direction = "pinchin", action = "float", mode = "tile" })
gesture({ fingers = 3, direction = "pinchout", action = "float", mode = "float" })

-- Four fingers: scroll the column tape 1:1 (scrolling layout), brightness.
gesture({ fingers = 4, direction = "horizontal", action = "scroll_move" })
if K.exists(K.home .. "/Scripts/brightness.sh") then
	gesture({ fingers = 4, direction = "up", action = cmd(BRIGHT .. "i") })
	gesture({ fingers = 4, direction = "down", action = cmd(BRIGHT .. "d") })
end

-- With modifiers: fullscreen, scratchpad, live zoom into the cursor.
gesture({ fingers = 4, direction = "up", mods = "SUPER", scale = 1.5, action = "fullscreen" })
gesture({ fingers = 4, direction = "down", mods = "SUPER", action = "fullscreen", mode = "maximize" })
gesture({ fingers = 4, direction = "pinch", mods = "ALT", action = "special", workspace_name = "special" })
if K.feature("overview") then -- pinch in with four fingers, like Mission Control
	gesture({ fingers = 4, direction = "pinchin", action = function() hl.dispatch(hl.dsp.global("rice:overview")) end })
end
gesture({ fingers = 4, direction = "pinch", mods = "SUPER", action = "cursor_zoom", mode = "live", zoom_level = 2 })
