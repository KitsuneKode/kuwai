-- kuwai.look — the material: geometry, corners, depth, glass.
--
-- Order matters and mirrors how the old hyprlang stack layered:
--   1. kuwai base           sane geometry + glass tuned for the rice
--   2. wallbash groupbar    colours from the wallpaper palette
--   3. HyDE theme           ~/.config/hypr/themes/theme.conf (borders, glow…)
--   4. kuwai identity       the bits that make it kuwai, whatever the theme
-- Modes (kuwai.modes) and user.lua come after all of this.

local K = require("kuwai.core")
local T = require("kuwai.theme")

local L = {}

-- 1. Base ------------------------------------------------------------------
K.config({
	general = {
		gaps_in = 5,
		gaps_out = 10,
		gaps_workspaces = 40, -- space between workspaces while swiping
		float_gaps = 10,
		border_size = 2,
		col = {
			active_border = { colors = { "rgba(ffffffcc)", "rgba(ffffff55)" }, angle = 45 },
			inactive_border = "rgba(ffffff14)",
		},
		resize_on_border = true,
		extend_border_grab_area = 15,
		hover_icon_on_border = true,
		allow_tearing = true, -- only windows with the `immediate` rule tear
		snap = {
			enabled = true, -- floating windows snap to edges and each other
			window_gap = 10,
			monitor_gap = 10,
			respect_gaps = true,
			border_overlap = true,
		},
	},

	decoration = {
		rounding = 18,
		rounding_power = 4, -- squircle, not a circle arc: Apple's continuous corner
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		fullscreen_opacity = 1.0,
		dim_special = 0.3, -- recede the desktop behind a scratchpad
		border_part_of_window = true,

		shadow = {
			enabled = true,
			range = 28,
			render_power = 3,
			offset = "0 8", -- light from above: depth reads downwards
			color = "rgba(0000005a)",
			color_inactive = "rgba(00000030)",
		},

		blur = {
			enabled = true,
			variant = "kawase", -- the "glass" mode swaps in acrylic
			size = 6,
			passes = 3,
			new_optimizations = true,
			ignore_opacity = true,
			xray = false, -- glass blurs the real windows behind it
			noise = 0.02, -- grain reads as speckle on glass at higher values
			contrast = 1.0,
			brightness = 0.95,
			vibrancy = 0.3,
			vibrancy_darkness = 0.35,
			popups = true,
			popups_ignorealpha = 0.6,
			special = true,
			input_methods = true,
		},

		-- Motion blur while dragging smeared text and cost GPU on every move:
		-- off. (Turn on per taste: motion_blur = { enabled = true }.)
		motion_blur = { enabled = false },
	},

	group = {
		insert_after_current = true,
		focus_removed_window = true,
		auto_group = false,
		groupbar = {
			enabled = true,
			font_family = "SF Pro Text",
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
		font_family = "SF Pro",
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		force_default_wallpaper = 0,
		background_color = "rgb(0b0b0f)",
	},
})

-- 2. Wallbash groupbar -------------------------------------------------------
-- 3. Theme -------------------------------------------------------------------
-- (T.apply parses colours first, so the groupbar can use them before the
-- theme's own group colours land on top.)
function L.apply_theme()
	T.load_colors()
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
	-- The theme lands last, so its explicit group colours win over the palette.
	T.apply()
end

-- 4. Identity: applied after the theme, whatever it said ----------------------
function L.apply_identity()
	K.config({
		decoration = {
			rounding_power = 4,
			-- At most 3 passes whatever the theme says (some ask for 4): on two
			-- 1440p screens a fourth pass costs ~25% more blur work for a
			-- difference you can't see; a slightly wider radius makes up for it.
			blur = { noise = 0.02, vibrancy = 0.3, vibrancy_darkness = 0.35, special = true, passes = 3, size = 6 },
		},
		-- Triple buffering when a frame runs late (hybrid laptops: the iGPU's
		-- panel is fed across from the NVIDIA renderer): smoother, not slower.
		render = { new_render_scheduling = true },
		group = { groupbar = { rounding_power = 4, gradient_rounding_power = 4, font_family = "SF Pro Text" } },
	})
	-- Hyprland's own notifications and error bar, in the rice's face.
	K.config({ misc = { font_family = "SF Pro Text" } })
end

L.apply_theme()
L.apply_identity()

return L
