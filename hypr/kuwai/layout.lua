local K = require("kuwai.core")

K.config({
	general = { layout = "scrolling" },

	scrolling = {
		column_width = 0.7,
		fullscreen_on_one_column = true,
		follow_focus = 1,
		follow_min_visible = 0.4,
		focus_fit_method = 1,
		explicit_column_widths = "0.5, 0.67, 0.8, 1.0",
		wrap_focus = true,
		wrap_swapcol = true,
		direction = "right",
	},

	dwindle = {
		preserve_split = true,
		smart_split = false,
		smart_resizing = false,
		precise_mouse_move = true,
		force_split = 2,
	},

	master = {
		new_status = "master",
		mfact = 0.55,
	},

})
