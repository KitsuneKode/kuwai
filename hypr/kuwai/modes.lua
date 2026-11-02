-- kuwai.modes — one desktop, a few moods. Replaces HyDE's workflows and
-- gamemode.sh (both wrote hyprlang files a Lua config never reads).
--
--   focus    opaque windows, glass only on the shell — colour-true for
--            reading, writing and picking colours (HyDE's "editing")
--   default  the theme as it comes, with per-app translucency from user.lua
--   glass    Liquid-Glass: acrylic lens blur + translucent windows (the
--            screenshot mode — costs GPU)
--   gaming   no blur/shadows/animations/gaps/rounding, tearing allowed
--   battery  light blur, no shadows or motion blur, quicker animations
--
-- Switch: Super+Shift+/ (picker), Super+Alt+G (gaming on/off),
--         `kuwai mode <name>`, or `hyprctl eval 'kuwai.mode("glass")'`.
-- The choice persists (~/.local/state/kuwai/state) and survives reloads.
-- It's applied last — after the theme and user.lua — so it always wins.

local K = require("kuwai.core")

local M = { list = { "focus", "default", "glass", "gaming", "battery" } }

M.describe = {
	focus = "Opaque windows, glass on the shell only",
	default = "Theme as designed, per-app translucency",
	glass = "Liquid glass: acrylic lens blur, translucent windows",
	gaming = "Nothing between you and the frame",
	battery = "Light effects, longer battery",
}

local apply = {}

function apply.focus()
	K.config({ decoration = { active_opacity = 1, inactive_opacity = 1, fullscreen_opacity = 1 } })
	pcall(hl.window_rule, { name = "mode-focus-opaque", match = { class = ".*" }, opaque = true })
end

function apply.default() end

function apply.glass()
	K.config({
		decoration = {
			active_opacity = 0.92,
			inactive_opacity = 0.86,
			blur = {
				enabled = true,
				variant = "acrylic",
				size = 8,
				passes = 3,
				vibrancy = 0.35,
				acrylic = {
					refraction = 18,
					bulb = 40,
					clarity = 0.78,
					aberration = 0.02,
					tint = "rgba(eef5ff14)",
				},
			},
		},
	})
	-- Video, games and the capture tools stay crisp and opaque.
	for _, c in ipairs({ "video", "game", "photo" }) do
		pcall(hl.window_rule, { name = "mode-glass-opaque-" .. c, match = { content = c }, opaque = true })
	end
end

function apply.gaming()
	K.config({
		animations = { enabled = false },
		general = { gaps_in = 0, gaps_out = 0, border_size = 1, allow_tearing = true },
		decoration = {
			rounding = 0,
			active_opacity = 1,
			inactive_opacity = 1,
			shadow = { enabled = false },
			glow = { enabled = false },
			blur = { enabled = false },
			motion_blur = { enabled = false },
			dim_special = 0,
		},
		misc = { vrr = 2 },
	})
	pcall(hl.window_rule, { name = "mode-gaming-opaque", match = { class = ".*" }, opaque = true })
end

function apply.battery()
	K.config({
		decoration = {
			shadow = { enabled = false },
			glow = { enabled = false },
			motion_blur = { enabled = false },
			blur = { size = 4, passes = 1, special = false, popups = false, vibrancy = 0.2 },
		},
		misc = { render_unfocused_fps = 5 },
	})
	pcall(hl.window_rule, { name = "mode-battery-opaque", match = { class = ".*" }, opaque = true })
end

M.current = K.state["mode"] or "focus"
if not apply[M.current] then
	M.current = "focus"
end

function M.apply()
	local ok, err = pcall(apply[M.current])
	if not ok then
		K.err("mode " .. M.current .. ": " .. tostring(err))
	end
end

-- Runtime API (binds, `hyprctl eval`, the kuwai CLI) -------------------------
_G.kuwai = _G.kuwai or {}

function kuwai.mode(name)
	if name == nil then
		return M.current
	end
	if not apply[name] then
		K.notify("kuwai: no mode '" .. tostring(name) .. "'", 2500, "error")
		return M.current
	end
	if name ~= "gaming" then
		K.set_state("mode_before_gaming", nil)
	end
	K.set_state("mode", name)
	K.notify("Mode: " .. name .. " — " .. (M.describe[name] or ""), 2000)
	-- A reload re-runs everything from a clean slate, so leaving a mode
	-- restores exactly what the theme and user.lua said.
	hl.dispatch(hl.dsp.reload_config())
	return name
end

function kuwai.mode_toggle(name)
	if M.current == name then
		local back = K.state["mode_before_gaming"] or "focus"
		K.set_state("mode_before_gaming", nil)
		return kuwai.mode(back)
	end
	K.set_state("mode_before_gaming", M.current)
	K.set_state("mode", name)
	K.notify("Mode: " .. name .. " — " .. (M.describe[name] or ""), 2000)
	hl.dispatch(hl.dsp.reload_config())
	return name
end

function kuwai.modes()
	return table.concat(M.list, " ")
end

return M
