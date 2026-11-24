local K = require("kuwai.core")

local M = {}

local function curve(name, p1, p2)
	hl.curve(name, { type = "bezier", points = { p1, p2 } })
end

curve("kuwaiOut", { 0.23, 1 }, { 0.32, 1 })
curve("kuwaiInOut", { 0.77, 0 }, { 0.175, 1 })
curve("kuwaiDrawer", { 0.32, 0.72 }, { 0, 1 })
curve("kuwaiLinear", { 0, 0 }, { 1, 1 })

hl.curve("kuwaiGlide", { type = "spring", mass = 1, stiffness = 550, damping = 47 })
hl.curve("kuwaiSheet", { type = "spring", mass = 1, stiffness = 380, damping = 39 })
hl.curve("kuwaiPage", { type = "spring", mass = 1, stiffness = 520, damping = 45.6 })

local SPRINGS = { kuwaiGlide = true, kuwaiSheet = true, kuwaiPage = true }

local function anim(leaf, speed, curve_name, style)
	local spec = { leaf = leaf, enabled = true, speed = speed or 1 }
	if SPRINGS[curve_name] then
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

	anim("windows", 1, "kuwaiGlide")
	anim("windowsIn", 2.5, "kuwaiOut", "popin 95%")
	anim("windowsOut", 1.6, "kuwaiOut", "popin 95%")
	anim("windowsMove", 1, "kuwaiGlide")

	anim("fadeIn", 1.8, "kuwaiOut")
	anim("fadeOut", 1.2, "kuwaiOut")
	anim("fadeSwitch", 2, "kuwaiOut")
	anim("fadeShadow", 2, "kuwaiOut")
	anim("fadeGlow", 2, "kuwaiOut")
	anim("fadeDim", 2, "kuwaiOut")
	anim("fadePopupsIn", 0.9, "kuwaiOut")
	anim("fadePopupsOut", 1.2, "kuwaiOut")

	anim("layersIn", 2.2, "kuwaiOut", "popin 93%")
	anim("layersOut", 1.5, "kuwaiOut", "popin 94%")
	anim("fadeLayersIn", 1.6, "kuwaiOut")
	anim("fadeLayersOut", 1.2, "kuwaiOut")

	anim("workspaces", 3, "kuwaiPage", "slide")
	anim("specialWorkspaceIn", 1, "kuwaiSheet", "slidevert")
	anim("specialWorkspaceOut", 1.6, "kuwaiOut", "slidevert")

	anim("border", 2, "kuwaiOut")
	off("borderangle")
	off("shadowangle")
	off("glowangle")

	anim("zoomFactor", 3, "kuwaiOut")
	anim("monitorAdded", 2.5, "kuwaiOut")
	anim("fadeDpms", 2.5, "kuwaiOut")
end

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
if os.getenv("KUWAI_REDUCE_MOTION") == "1" or K.state["motion"] == "reduced" then
	M.reduce()
elseif K.state["motion"] == "off" then
	K.config({ animations = { enabled = false } })
end

return M
