package.path = "hypr/?.lua;hypr/?/init.lua;" .. package.path

local DP3 = { name = "DP-3", description = "Acer XV272U", refresh_rate = 200, scale = 1, x = 0, y = 0, width = 2560, height = 1440, available_modes = {
	{ width = 2560, height = 1440, refresh_rate = 200 }, { width = 2560, height = 1440, refresh_rate = 120 } } }
local EDP = { name = "eDP-1", description = "Panel", refresh_rate = 165, scale = 1, x = 2560, y = 0, width = 2560, height = 1440, available_modes = {
	{ width = 2560, height = 1440, refresh_rate = 165 }, { width = 2560, height = 1440, refresh_rate = 60 } } }

local W, active, timers, modes, cms, last_cfg, reloads, handlers
local scales = {}
local function fresh()
	for k in pairs(package.loaded) do
		if k:match("^kuwai") then package.loaded[k] = nil end
	end
	_G.__kuwai_raw_monitor, _G.kuwai = nil, nil
	W, active, timers, modes, cms, last_cfg, reloads, handlers = {}, nil, {}, {}, {}, {}, 0, {}
	local K = { state = {}, home = "/nonexistent", night_off = "true", colour_apps = {} }
	function K.set_state(k, v) K.state[k] = v ~= nil and tostring(v) or nil end
	function K.feature(name) return name == "auto_display" end
	function K.config(c) last_cfg = c end
	function K.json_str(v) return '"' .. tostring(v) .. '"' end
	function K.notify() end
	function K.err(m) error(m) end
	function K.exists() return false end
	function K.ac_online() return true end
	function K.defer() end
	package.loaded["kuwai.core"] = K
	_G.hl = {
		dsp = { reload_config = function() return "reload" end },
		monitor = function(spec) modes[spec.output] = spec.mode; cms[spec.output] = spec.cm; scales[spec.output] = spec.scale end,
		get_monitors = function() return { DP3, EDP } end,
		get_windows = function() return W end,
		get_active_window = function() return active end,
		on = function(ev, f) handlers[ev] = f end,
		timer = function(f) timers[#timers + 1] = f end,
		dispatch = function(a) if a == "reload" then reloads = reloads + 1 end end,
		exec_cmd = function() end,
	}
	local D = require("kuwai.display")
	hl.monitor({ output = "DP-3", mode = "2560x1440@200", bitdepth = 10, cm = "srgb", max_luminance = 400 })
	hl.monitor({ output = "eDP-1", mode = "2560x1440@165" })
	modes, cms = {}, {}
	return D, K
end

local D, K = fresh()
assert(kuwai.screen("DP-3", "scale", "1.25"):find("scale 1.25"), "scale applied")
assert(scales["DP-3"] == 1.25 and K.state["screen.dp-3.scale"] == "1.25", "scale saved under the rule's output")
assert(kuwai.screen("DP-3", "rate", "120"):find("2560x1440@120"), "rate applied")
assert(kuwai.screen("DP-3", "rate", "75"):find("no 75 Hz"), "a rate the screen lacks is refused")
assert(kuwai.screen("DP-3", "scale", "9"):find("0.5 to 3"), "an absurd scale is refused")
local json = kuwai.screens_json()
assert(json:find('"rates":%[120,200%]') and json:find('"changed":true'), "the list says what it can do and what changed")
assert(kuwai.screen("DP-3", "reset"):find("2560x1440@200"), "reset goes back to monitors.lua's rule")
assert(K.state["screen.dp-3.scale"] == nil and K.state["screen.dp-3.rate"] == nil, "reset forgets")
local D2, K2 = (function()
	local saved = { ["screen.dp-3.scale"] = "1.5" }
	local D, K = fresh()
	for k, v in pairs(saved) do K.state[k] = v end
	hl.monitor({ output = "DP-3", mode = "2560x1440@200" })
	return D, K
end)()
assert(scales["DP-3"] == 1.5, "a saved scale is applied when the rule is registered")
print("display settings pass")
