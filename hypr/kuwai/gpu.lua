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
	else
		local on_ac = K.read_line("/sys/class/power_supply/ACAD/online") == "1"
		primary = (#nv.outputs > 0 or on_ac) and nv or igpu
	end
end
G.mode, G.primary = mode, primary and primary.vendor or "none"

if primary and #cards > 1 then
	local list = { primary.dev }
	for _, c in ipairs(cards) do
		if c ~= primary then
			list[#list + 1] = c.dev
		end
	end
	hl.env("AQ_DRM_DEVICES", table.concat(list, ":"))
end

if nv then
	hl.env("NVD_BACKEND", "direct")
	if primary == nv then
		hl.env("LIBVA_DRIVER_NAME", "nvidia")
		hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
	end
end

hl.env("KUWAI_GPU_PRIMARY", G.primary)
print(("[kuwai] gpu: mode=%s primary=%s nvidia_outputs=%s"):format(
	mode,
	G.primary,
	nv and table.concat(nv.outputs, ",") or "-"
))

K.config({
	cursor = { no_hardware_cursors = 2 },
	opengl = { nvidia_anti_flicker = false },
})

return G
