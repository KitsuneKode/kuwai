-- kuwai.gpu — which GPU renders, and the driver environment that follows.
--
-- Hybrid laptops wire the panel to the iGPU and the HDMI/DP ports (often) to
-- the dGPU. Rendering on the GPU that owns the busy screen avoids a cross-GPU
-- copy every frame; rendering on the iGPU keeps the dGPU asleep on battery.
--
--   auto    (default) NVIDIA renders when a screen hangs off it at login (an
--           external monitor, or the panel itself behind a MUX in dGPU mode),
--           otherwise the iGPU renders and NVIDIA wakes only for prime-run apps.
--   nvidia  always NVIDIA        intel   always the iGPU
--
-- Pick with `kuwai gpu <auto|nvidia|intel>` (or KUWAI_GPU=...); it takes effect
-- at the next login — Hyprland chooses its renderer once, at start.
--
-- Everything here reads cached sysfs only. lspci/nvidia-smi would wake a
-- runtime-suspended dGPU, and that wake alone can outlast Hyprland's config
-- budget (both Omarchy and HyDE learned this the hard way).

local K = require("kuwai.core")

local VENDORS = { ["0x10de"] = "nvidia", ["0x8086"] = "intel", ["0x1002"] = "amd" }
local CONNECTORS = { "eDP", "DP", "HDMI-A", "DVI-D", "DVI-I", "USB-C", "Virtual" }

local cards = {}
for n = 0, 7 do
	local vendor = K.read_line("/sys/class/drm/card" .. n .. "/device/vendor")
	if vendor then
		local card = { n = n, dev = "/dev/dri/card" .. n, vendor = VENDORS[vendor] or vendor, outputs = {} }
		for _, kind in ipairs(CONNECTORS) do
			for i = 1, 8 do
				local name = kind .. "-" .. i
				local status = K.read_line("/sys/class/drm/card" .. n .. "-" .. name .. "/status")
				if status == "connected" then
					card.outputs[#card.outputs + 1] = name
				end
			end
		end
		cards[#cards + 1] = card
	end
end

local function first(vendor)
	for _, c in ipairs(cards) do
		if c.vendor == vendor then
			return c
		end
	end
end

local nv = first("nvidia")
local igpu = first("intel") or first("amd")

local G = { cards = cards, nvidia = nv, igpu = igpu }

local mode = os.getenv("KUWAI_GPU") or K.state["gpu"] or "auto"
local primary = igpu or nv
if nv and igpu then
	if mode == "nvidia" then
		primary = nv
	elseif mode == "intel" or mode == "igpu" then
		primary = igpu
	else -- auto: render where the screens are
		primary = (#nv.outputs > 0) and nv or igpu
	end
end
G.mode, G.primary = mode, primary and primary.vendor or "none"

if primary and #cards > 1 then
	-- Every card that drives a screen must be listed, primary first.
	local list = { primary.dev }
	for _, c in ipairs(cards) do
		if c ~= primary then
			list[#list + 1] = c.dev
		end
	end
	hl.env("AQ_DRM_DEVICES", table.concat(list, ":"))
end

if nv then
	-- nvidia-vaapi-driver: direct backend is the one that works on 525+.
	hl.env("NVD_BACKEND", "direct")
	if primary == nv then
		-- Only when NVIDIA composites. On an iGPU-rendered session these force
		-- Chromium/Electron video onto a GPU that doesn't own the screen
		-- (black video, broken decode). prime-run sets them per app instead.
		hl.env("LIBVA_DRIVER_NAME", "nvidia")
		hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
	end
end

-- For scripts and the shell: `echo $KUWAI_GPU_PRIMARY`.
hl.env("KUWAI_GPU_PRIMARY", G.primary)
print(("[kuwai] gpu: mode=%s primary=%s nvidia_outputs=%s"):format(
	mode,
	G.primary,
	nv and table.concat(nv.outputs, ",") or "-"
))

-- Hardware cursors: Hyprland's auto (2) already avoids them while tearing and
-- uses a CPU buffer on NVIDIA. The old forced-off setting cost a software
-- cursor on every frame and isn't needed on the open 5xx/6xx drivers.
K.config({
	cursor = { no_hardware_cursors = 2 },
	opengl = { nvidia_anti_flicker = true },
})

return G
