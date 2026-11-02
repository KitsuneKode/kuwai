-- kuwai.layout — the scrolling tape by default, dwindle where it fits better.

local K = require("kuwai.core")

K.config({
	general = { layout = "scrolling" },

	scrolling = {
		column_width = 0.7,
		fullscreen_on_one_column = true,
		follow_focus = 1,
		follow_min_visible = 0.4,
		focus_fit_method = 1, -- fit the focused column into view
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
		force_split = 2, -- new window goes right/bottom: predictable
	},

	master = {
		new_status = "master",
		mfact = 0.55,
	},

})

-- The layout binds live in kuwai.binds; workspace→layout pins are per machine
-- (user.lua / monitors.lua), e.g.:
--   hl.workspace_rule({ workspace = "1", layout = "dwindle" })
