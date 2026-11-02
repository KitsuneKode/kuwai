-- kuwai.motion — the same motion language as the shell (docs/DESIGN.md):
-- one strong ease-out for entrances/exits, exits about two thirds of entrances,
-- UI under ~300ms, never ease-in, never a loop.
--
-- Window moves and reflows use a critically damped spring: physics-timed and
-- interruptible (a retarget mid-flight keeps its velocity, like Spring.qml),
-- so dragging, swapping and scrolling columns never snap back or restart.
--
-- Speeds are in tenths of a second (2.5 = 250ms). Springs ignore speed.

local K = require("kuwai.core")

local M = {}

local function curve(name, p1, p2)
	hl.curve(name, { type = "bezier", points = { p1, p2 } })
end

curve("kuwaiOut", { 0.23, 1 }, { 0.32, 1 }) -- Theme.easeOut
curve("kuwaiInOut", { 0.77, 0 }, { 0.175, 1 }) -- Theme.easeInOut
curve("kuwaiDrawer", { 0.32, 0.72 }, { 0, 1 }) -- Theme.easeDrawer
curve("kuwaiLinear", { 0, 0 }, { 1, 1 })

-- zeta = damping / (2*sqrt(stiffness*mass)) = 1 → no overshoot, ~200ms to rest.
hl.curve("kuwaiGlide", { type = "spring", mass = 1, stiffness = 550, damping = 47 })
-- A touch softer for large surfaces (special workspaces sliding in).
hl.curve("kuwaiSheet", { type = "spring", mass = 1, stiffness = 380, damping = 39 })

local function anim(leaf, speed, curve_name, style)
	local spec = { leaf = leaf, enabled = true, speed = speed or 1 }
	if curve_name and curve_name:match("Glide$") or curve_name and curve_name:match("Sheet$") then
		spec.spring = curve_name
	else
		spec.bezier = curve_name or "kuwaiOut"
	end
	spec.style = style
	local ok, err = pcall(hl.animation, spec)
	if not ok then
		K.err("animation " .. leaf .. ": " .. tostring(err))
	end
end

local function off(leaf)
	pcall(hl.animation, { leaf = leaf, enabled = false })
end

function M.apply()
	K.config({ animations = { enabled = true, workspace_wraparound = false } })

	anim("global", 2.5, "kuwaiOut")

	-- Windows: arrive from 95%, leave the same way, quicker.
	anim("windows", 1, "kuwaiGlide")
	anim("windowsIn", 2.5, "kuwaiOut", "popin 95%")
	anim("windowsOut", 1.6, "kuwaiOut", "popin 95%")
	anim("windowsMove", 1, "kuwaiGlide")

	anim("fadeIn", 1.8, "kuwaiOut")
	anim("fadeOut", 1.2, "kuwaiOut")
	anim("fadeSwitch", 1.8, "kuwaiOut")
	anim("fadeShadow", 1.8, "kuwaiOut")
	anim("fadeDim", 2.5, "kuwaiOut")

	-- Layers (bars, menus, launchers): a short rise; the rice's own rice-*
	-- surfaces opt out (layer rule no_anim) because they animate themselves.
	anim("layersIn", 2.2, "kuwaiOut", "popin 93%")
	anim("layersOut", 1.5, "kuwaiOut", "popin 94%")
	anim("fadeLayersIn", 1.6, "kuwaiOut")
	anim("fadeLayersOut", 1.2, "kuwaiOut")

	-- Workspaces: a short slide that fades, so direction still reads.
	anim("workspaces", 2.5, "kuwaiOut", "slidefade 8%")
	anim("specialWorkspaceIn", 1, "kuwaiSheet", "slidevert")
	anim("specialWorkspaceOut", 1.6, "kuwaiOut", "slidevert")

	-- Border colour eases on focus change. The angle never animates: HyDE's
	-- looping gradient redrew every frame forever (no VFR, constant GPU load).
	anim("border", 1.5, "kuwaiOut")
	off("borderangle")

	anim("zoomFactor", 3, "kuwaiOut")
	anim("monitorAdded", 2.5, "kuwaiOut")
end

-- Reduce Motion (the center's toggle / RICE_REDUCE_MOTION / `kuwai motion off`):
-- fades stay, travel and scale go.
function M.reduce()
	off("windowsIn")
	off("windowsOut")
	off("windowsMove")
	off("windows")
	off("workspaces")
	off("specialWorkspaceIn")
	off("specialWorkspaceOut")
	anim("layersIn", 1.6, "kuwaiOut", "fade")
	anim("layersOut", 1.2, "kuwaiOut", "fade")
end

M.apply()
if os.getenv("RICE_REDUCE_MOTION") == "1" or K.state["motion"] == "reduced" then
	M.reduce()
elseif K.state["motion"] == "off" then
	K.config({ animations = { enabled = false } })
end

return M
