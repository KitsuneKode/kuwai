local K = require("kuwai.core")
local T = require("kuwai.theme")

local L = {}

local UI_FONT = "SF Pro Text, Inter, sans-serif"

K.config({
	general = {
		gaps_in = 5,
		gaps_out = 10,
		gaps_workspaces = 40,
		float_gaps = 10,
		border_size = 2,
		col = {
			active_border = { colors = { "rgba(ffffffcc)", "rgba(ffffff55)" }, angle = 45 },
			inactive_border = "rgba(ffffff14)",
		},
		resize_on_border = true,
		extend_border_grab_area = 15,
		hover_icon_on_border = true,
		allow_tearing = true,
		snap = {
			enabled = true,
			window_gap = 10,
			monitor_gap = 10,
			respect_gaps = true,
			border_overlap = true,
		},
	},

	decoration = {
		rounding = 18,
		rounding_power = 4,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		fullscreen_opacity = 1.0,
		dim_special = 0.3,
		border_part_of_window = true,

		shadow = {
			enabled = true,
			range = 40,
			render_power = 3,
			offset = "0 12",
			color = "rgba(00000066)",
			color_inactive = "rgba(00000033)",
		},

		glow = {
			enabled = true,
			range = 12,
			render_power = 3,
			color = { colors = { "rgba(ffffff36)", "rgba(ffffff10)" }, angle = 45 },
			color_inactive = "rgba(00000000)",
		},

		blur = {
			enabled = true,
			variant = "kawase",
			size = 6,
			passes = 3,
			new_optimizations = true,
			ignore_opacity = true,
			xray = false,
			noise = 0.02,
			contrast = 1.0,
			brightness = 0.95,
			vibrancy = 0.3,
			vibrancy_darkness = 0.35,
			popups = true,
			popups_ignorealpha = 0.6,
			special = true,
			input_methods = true,
		},

		motion_blur = { enabled = false },
	},

	group = {
		insert_after_current = true,
		focus_removed_window = true,
		auto_group = false,
		groupbar = {
			enabled = true,
			disable_when_only = true,
			font_family = UI_FONT,
			font_size = 11,
			font_weight_active = "semibold",
			font_weight_inactive = "normal",
			height = 18,
			indicator_height = 0,
			gradients = true,
			gradient_rounding = 9,
			gradient_rounding_power = 4,
			rounding = 9,
			rounding_power = 4,
			gaps_in = 4,
			gaps_out = 4,
			keep_upper_gap = false,
			render_titles = true,
			middle_click_close = true,
			blur = true,
		},
	},

	misc = {
		font_family = UI_FONT,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		force_default_wallpaper = 0,
		background_color = "rgb(0b0b0f)",
	},
})

function L.apply_theme()
	T.load_colors(true)
	if T.kuwai then
		local active_b = T.rgba("accent", "b3")
		local soft_b = T.rgba("accent", "4d")
		local inactive_b = T.rgba("border", "55")
		if active_b then
			K.config({
				general = {
					col = {
						active_border = { colors = { active_b, soft_b }, angle = 45 },
						inactive_border = inactive_b or "rgba(ffffff14)",
					},
				},
				decoration = {
					glow = {
						color = { colors = { T.rgba("accent", "40"), T.rgba("accent", "14") }, angle = 45 },
						color_inactive = "rgba(00000000)",
					},
				},
			})
		end
		if T.colors.bg and T.colors.bg:match("^%x%x%x%x%x%x$") then
			K.config({ misc = { background_color = "rgb(" .. T.colors.bg .. ")" } })
		end
	end
	local active, inactive = T.rgba("pry3", "ee"), T.rgba("pry1", "ee")
	if active then
		K.config({
			group = {
				groupbar = {
					col = {
						active = active,
						inactive = inactive,
						locked_active = T.rgba("pry2", "ee"),
						locked_inactive = T.rgba("pry4", "ee"),
					},
					text_color = T.rgba("txt3", "ee") or "rgba(ffffffee)",
					text_color_inactive = T.rgba("txt1", "aa") or "rgba(ffffffaa)",
				},
			},
		})
	end
	T.apply()
end

L.SHAPE = {
	general = { border_size = 2, gaps_in = 5, gaps_out = 10 },
	decoration = {
		rounding = 18,
		rounding_power = 4,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		dim_inactive = false,
		shadow = { enabled = true, range = 40, render_power = 3, offset = "0 12" },
		glow = { enabled = true, range = 12, render_power = 3 },
	},
}

function L.apply_identity()
	K.config(L.SHAPE)
	K.config({
		decoration = {
			blur = { noise = 0.02, vibrancy = 0.3, vibrancy_darkness = 0.35, special = true, passes = 3, size = 6 },
		},
		render = { new_render_scheduling = false },
		group = { groupbar = { rounding_power = 4, gradient_rounding_power = 4, font_family = UI_FONT } },
	})
	K.config({ misc = { font_family = UI_FONT } })
end

L.apply_theme()
L.apply_identity()

return L
