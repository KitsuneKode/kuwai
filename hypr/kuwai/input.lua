local K = require("kuwai.core")

local KB_SWITCH = {
	["alt-shift"] = "grp:alt_shift_toggle",
	caps = "grp:caps_toggle",
	["win-space"] = "grp:win_space_toggle",
	["ctrl-shift"] = "grp:ctrl_shift_toggle",
	none = "",
}
local function kb_settings()
	return {
		kb_layout = K.state["kb_layout"] or "us",
		kb_variant = K.state["kb_variant"] or "",
		kb_options = KB_SWITCH[K.state["kb_switch"] or "none"] or "",
	}
end
_G.kuwai = _G.kuwai or {}
function kuwai.keyboard(layout, variant, switch)
	if layout then
		K.set_state("kb_layout", layout ~= "" and layout or nil)
	end
	if variant then
		K.set_state("kb_variant", variant ~= "" and variant or nil)
	end
	if switch and KB_SWITCH[switch] ~= nil then
		K.set_state("kb_switch", switch ~= "none" and switch or nil)
	end
	K.config({ input = kb_settings() })
	local s = kb_settings()
	return s.kb_layout .. (s.kb_variant ~= "" and (" (" .. s.kb_variant .. ")") or "") .. (s.kb_options ~= "" and (" · " .. s.kb_options) or "")
end

local POINTER = {
	speed = { default = "-0.5", num = { -1, 1 } },
	accel = { default = "flat", one_of = { flat = true, adaptive = true } },
	["mouse-natural"] = { default = "off", one_of = { on = true, off = true } },
	["trackpad-natural"] = { default = "on", one_of = { on = true, off = true } },
	tap = { default = "on", one_of = { on = true, off = true } },
	["trackpad-scroll"] = { default = "0.7", num = { 0.2, 3 } },
	["repeat-delay"] = { default = "250", num = { 150, 1000 } },
	["repeat-rate"] = { default = "35", num = { 10, 80 } },
}
local function ptr(key)
	return K.state["ptr." .. key] or POINTER[key].default
end
local function pointer_settings()
	return {
		sensitivity = tonumber(ptr("speed")),
		accel_profile = ptr("accel"),
		force_no_accel = ptr("accel") == "flat",
		natural_scroll = ptr("mouse-natural") == "on",
		repeat_delay = math.floor(tonumber(ptr("repeat-delay"))),
		repeat_rate = math.floor(tonumber(ptr("repeat-rate"))),
		touchpad = {
			natural_scroll = ptr("trackpad-natural") == "on",
			tap_to_click = ptr("tap") == "on",
			scroll_factor = tonumber(ptr("trackpad-scroll")),
		},
	}
end
function kuwai.pointer(key, value)
	local spec = POINTER[key]
	if not spec then
		return "unknown setting: " .. tostring(key)
	end
	value = tostring(value)
	if spec.num then
		local n = tonumber(value)
		if not n or n < spec.num[1] or n > spec.num[2] then
			return key .. " takes a number from " .. spec.num[1] .. " to " .. spec.num[2]
		end
	elseif not spec.one_of[value] then
		return key .. ": not a choice (" .. value .. ")"
	end
	K.set_state("ptr." .. key, value ~= spec.default and value or nil)
	K.config({ input = pointer_settings() })
	return key .. " " .. value
end

if K.feature("input_method") then
	local im = K.has("fcitx5") and "fcitx" or K.has("ibus-daemon") and "ibus" or nil
	if im then
		pcall(hl.env, "XMODIFIERS", "@im=" .. im)
		pcall(hl.env, "QT_IM_MODULE", im)
		pcall(hl.env, "SDL_IM_MODULE", im)
		K.on_start(im == "fcitx" and "fcitx5 -d --replace" or "ibus-daemon -drx --panel disable")
	else
		K.err("input_method is on, but neither fcitx5 nor ibus is installed")
	end
end

local kb = kb_settings()
K.config({
	input = {
		kb_layout = kb.kb_layout,
		kb_variant = kb.kb_variant,
		kb_options = kb.kb_options,
		numlock_by_default = false,
		repeat_delay = pointer_settings().repeat_delay,
		repeat_rate = pointer_settings().repeat_rate,

		sensitivity = pointer_settings().sensitivity,
		accel_profile = pointer_settings().accel_profile,
		force_no_accel = pointer_settings().force_no_accel,
		natural_scroll = pointer_settings().natural_scroll,
		follow_mouse = 1,
		float_switch_override_focus = 1,
		off_window_axis_events = 2,
		follow_mouse_shrink = 4,
		special_fallthrough = true,

		touchpad = {
			natural_scroll = pointer_settings().touchpad.natural_scroll,
			disable_while_typing = true,
			clickfinger_behavior = true,
			tap_to_click = pointer_settings().touchpad.tap_to_click,
			scroll_factor = pointer_settings().touchpad.scroll_factor,
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
		hide_on_key_press = true,
		zoom_factor = 1,
		zoom_rigid = false,
		zoom_disable_aa = true,
		hotspot_padding = 1,
		warp_on_toggle_special = 1,
	},
})

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
local BRIGHT = K.bin .. "/kuwai-brightness "

gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
gesture({ fingers = 3, direction = "up", action = cmd(VOL .. "5%+") })
gesture({ fingers = 3, direction = "down", action = cmd(VOL .. "5%-") })
gesture({ fingers = 3, direction = "pinchin", action = "float", mode = "tile" })
gesture({ fingers = 3, direction = "pinchout", action = "float", mode = "float" })

gesture({ fingers = 4, direction = "horizontal", action = "scroll_move" })
if K.exists(K.bin .. "/kuwai-brightness") then
	gesture({ fingers = 4, direction = "up", action = cmd(BRIGHT .. "i") })
	gesture({ fingers = 4, direction = "down", action = cmd(BRIGHT .. "d") })
end

gesture({ fingers = 4, direction = "up", mods = "SUPER", scale = 1.5, action = "fullscreen" })
gesture({ fingers = 4, direction = "down", mods = "SUPER", action = "fullscreen", mode = "maximize" })
gesture({ fingers = 4, direction = "pinch", mods = "ALT", action = "special", workspace_name = "special" })
if K.feature("overview") then
	gesture({ fingers = 4, direction = "pinchin", action = function() hl.dispatch(hl.dsp.global("kuwai:overview")) end })
end
gesture({ fingers = 4, direction = "pinch", mods = "SUPER", action = "cursor_zoom", mode = "live", zoom_level = 2 })
