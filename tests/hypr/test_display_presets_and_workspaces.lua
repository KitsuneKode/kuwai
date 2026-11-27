package.path = "hypr/?.lua;hypr/?/init.lua;" .. package.path

local fails = 0
local function check(cond, what)
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local function fresh_display(monitors, extra_rules, exists_fn)
	for k in pairs(package.loaded) do
		if k:match("^kuwai") then
			package.loaded[k] = nil
		end
	end
	_G.__kuwai_raw_monitor, _G.kuwai = nil, nil
	local W, active, timers, calls, last_cfg, reloads, handlers = {}, nil, {}, {}, {}, 0, {}
	local K = { state = {}, home = "/tmp/kuwai-test-home", night_off = "true", colour_apps = {} }
	function K.set_state(k, v)
		K.state[k] = v ~= nil and tostring(v) or nil
	end
	function K.feature(name)
		return name == "auto_display"
	end
	function K.config(c)
		last_cfg = c
	end
	function K.json_str(v)
		return '"' .. tostring(v) .. '"'
	end
	function K.notify() end
	function K.err(m)
		error(m)
	end
	function K.exists(p)
		return exists_fn and exists_fn(p) or false
	end
	function K.ac_online()
		return true
	end
	function K.defer() end
	package.loaded["kuwai.core"] = K
	_G.hl = {
		dsp = { reload_config = function() return "reload" end },
		monitor = function(spec)
			local copy = {}
			for k, v in pairs(spec) do
				copy[k] = v
			end
			calls[#calls + 1] = copy
		end,
		get_monitors = function()
			return monitors
		end,
		get_windows = function()
			return W
		end,
		get_active_window = function()
			return active
		end,
		on = function(ev, f)
			handlers[ev] = f
		end,
		timer = function(f)
			timers[#timers + 1] = f
		end,
		dispatch = function(a)
			if a == "reload" then
				reloads = reloads + 1
			end
		end,
		exec_cmd = function() end,
	}
	local D = require("kuwai.display")
	for _, spec in ipairs(extra_rules or {}) do
		hl.monitor(spec)
	end
	calls = {}
	return D, K, {
		calls = function() return calls end,
		clear = function() calls = {} end,
		windows = W,
		set_active = function(w) active = w end,
		last_cfg = function() return last_cfg end,
	}
end

local function by_output(calls)
	local out = {}
	for _, c in ipairs(calls) do
		out[c.output] = c
	end
	return out
end

do
	local DP1 = {
		name = "DP-1",
		description = "Dell Inc. DELL U2723QE",
		width = 2560,
		height = 1440,
		refresh_rate = 200,
		scale = 1,
		x = 0,
		y = 0,
		available_modes = {
			{ width = 2560, height = 1440, refresh_rate = 200 },
			{ width = 2560, height = 1440, refresh_rate = 120 },
		},
	}
	local EDP = {
		name = "eDP-1",
		description = "Built-in Panel",
		width = 2560,
		height = 1440,
		refresh_rate = 165,
		scale = 1,
		x = 2560,
		y = 0,
		available_modes = {
			{ width = 2560, height = 1440, refresh_rate = 165 },
			{ width = 2560, height = 1440, refresh_rate = 60 },
		},
	}
	local icc_path = "/tmp/kuwai-test-home/.local/share/kuwai-data/icc/dell-inc-dell-u2723qe.icc"
	local D, K, ctx = fresh_display({ DP1, EDP }, nil, function(p) return p == icc_path end)

	K.state.display = "movie"
	D.apply()
	local m = by_output(ctx.calls())
	check(m["DP-1"] and m["DP-1"].mode == "2560x1440@120", "empty monitors.lua: movie sets DP-1 to 120 Hz")
	check(m["eDP-1"] == nil, "empty monitors.lua: movie leaves eDP-1 alone")

	ctx.clear()
	K.state.display = "battery"
	D.apply()
	m = by_output(ctx.calls())
	check(m["eDP-1"] and m["eDP-1"].mode == "2560x1440@60", "empty monitors.lua: battery sets eDP-1 to 60 Hz")
	check(m["DP-1"] and m["DP-1"].mode == "2560x1440@200", "empty monitors.lua: leaving movie restores DP-1 to 200 Hz")

	ctx.clear()
	K.state.display = "accurate"
	D.apply()
	m = by_output(ctx.calls())
	check(m["DP-1"] and m["DP-1"].icc == icc_path, "empty monitors.lua: accurate applies ICC profile")
	check(m["eDP-1"] and m["eDP-1"].mode == "2560x1440@165", "empty monitors.lua: leaving battery restores eDP-1 to 165 Hz")

	ctx.clear()
	K.state.display = nil
	K.state.display_hdr = "on"
	D.apply()
	m = by_output(ctx.calls())
	check(m["DP-1"] and m["DP-1"].cm == "hdredid", "empty monitors.lua: explicit HDR enables hdredid on external screen")
	check(m["eDP-1"] == nil, "empty monitors.lua: explicit HDR leaves internal panel alone")

	ctx.clear()
	K.state.display_hdr = nil
	D.apply()
	m = by_output(ctx.calls())
	check(m["DP-1"] and m["DP-1"].cm == "srgb", "empty monitors.lua: turning HDR off restores srgb")
end

do
	local A = {
		name = "DP-1",
		description = "LG Electronics LG ULTRAGEAR",
		width = 2560,
		height = 1440,
		refresh_rate = 180,
		scale = 1,
		x = 0,
		y = 0,
		available_modes = {
			{ width = 2560, height = 1440, refresh_rate = 180 },
			{ width = 2560, height = 1440, refresh_rate = 120 },
		},
	}
	local B = {
		name = "DP-2",
		description = "LG Electronics LG ULTRAGEAR",
		width = 2560,
		height = 1440,
		refresh_rate = 180,
		scale = 1,
		x = 2560,
		y = 0,
		available_modes = {
			{ width = 2560, height = 1440, refresh_rate = 180 },
			{ width = 2560, height = 1440, refresh_rate = 120 },
		},
	}
	local D, K, ctx = fresh_display({ A, B }, {
		{ output = "desc:LG Electronics LG ULTRAGEAR", mode = "2560x1440@180", scale = 1 },
	})

	ctx.windows[1] = { address = "0x1", class = "mpv", monitor = A, fullscreen = 0 }
	K.state.display_auto = "movie"
	D.apply()
	local m = by_output(ctx.calls())
	check(m["DP-1"] and m["DP-1"].mode == "2560x1440@120", "shared desc rule: auto movie targets DP-1 by connector name")
	check(m["DP-2"] == nil, "shared desc rule: auto movie does not clobber identical DP-2")
	check(m["desc:LG Electronics LG ULTRAGEAR"] == nil, "shared desc rule: never emits shared desc selector")

	ctx.clear()
	check(kuwai.screen("DP-1", "scale", "1.5"):find("scale 1.5"), "identical monitors: DP-1 scale set")
	m = by_output(ctx.calls())
	check(m["DP-1"] and m["DP-1"].scale == 1.5, "identical monitors: scale targets DP-1 connector")
	check(m["DP-2"] == nil and m["desc:LG Electronics LG ULTRAGEAR"] == nil, "identical monitors: DP-2 untouched by DP-1 scale")
	check(K.state["screen.dp-1.scale"] == "1.5" and K.state["screen.dp-2.scale"] == nil, "identical monitors: separate state keys")
	local j = kuwai.screens_json()
	check(j:find('"name":"DP%-1"[^}]-"changed":true') ~= nil, "identical monitors: DP-1 reports changed=true")
	check(j:find('"name":"DP%-2"[^}]-"changed":false') ~= nil, "identical monitors: DP-2 reports changed=false")
end

do
	local S1 = {
		name = "DP-1",
		description = "Dell Inc. DELL U2723QE AAA111",
		width = 3840,
		height = 2160,
		refresh_rate = 144,
		scale = 1,
		x = 0,
		y = 0,
		available_modes = { { width = 3840, height = 2160, refresh_rate = 144 }, { width = 3840, height = 2160, refresh_rate = 120 } },
	}
	local S2 = {
		name = "DP-2",
		description = "Dell Inc. DELL U2723QE BBB222",
		width = 3840,
		height = 2160,
		refresh_rate = 144,
		scale = 1,
		x = 3840,
		y = 0,
		available_modes = { { width = 3840, height = 2160, refresh_rate = 144 }, { width = 3840, height = 2160, refresh_rate = 120 } },
	}
	local D, K, ctx = fresh_display({ S1, S2 }, {
		{ output = "desc:Dell Inc. DELL U2723QE", mode = "3840x2160@144", scale = 1 },
		{ output = "desc:Dell Inc. DELL U2723QE BBB222", mode = "3840x2160@144", scale = 1.5 },
	})
	check(kuwai.screen("DP-2", "rate", "120"):find("scale 1.5"), "longer desc prefix with serial wins over generic model rule")
end

local function fresh_workspaces(monitors, initial_state)
	for k in pairs(package.loaded) do
		if k:match("^kuwai") then
			package.loaded[k] = nil
		end
	end
	_G.kuwai = nil
	local state = {}
	for k, v in pairs(initial_state or {}) do
		state[k] = v
	end
	local ws_rules, disabled_rules, handlers = {}, {}, {}
	local function auto(name)
		return setmetatable({}, {
			__index = function(t, k)
				local v = auto(name .. "." .. k)
				rawset(t, k, v)
				return v
			end,
			__call = function(_, args)
				return { op = name, args = args or {} }
			end,
		})
	end
	_G.hl = auto("hl")
	hl.dsp = auto("dsp")
	hl.get_monitors = function() return monitors end
	hl.get_active_monitor = function() return monitors[1] end
	hl.get_workspaces = function() return {} end
	hl.get_windows = function() return {} end
	hl.on = function(ev, f)
		handlers[ev] = handlers[ev] or {}
		handlers[ev][#handlers[ev] + 1] = f
	end
	hl.timer = function() end
	hl.dispatch = function() end
	hl.workspace_rule = function(spec)
		local rec = { workspace = spec.workspace, monitor = spec.monitor, enabled = true }
		ws_rules[#ws_rules + 1] = rec
		return {
			set_enabled = function(_, on)
				rec.enabled = on
				if not on then
					disabled_rules[#disabled_rules + 1] = rec
				end
			end,
		}
	end
	local K = {
		state = state,
		feature = function(f) return f == "per_monitor_ws" end,
		set_state = function(k, v) state[k] = v ~= nil and tostring(v) or nil end,
	}
	setmetatable(K, { __index = function(_, k) return auto("K." .. k) end })
	package.loaded["kuwai.core"] = K
	local W = require("kuwai.workspaces")
	return W, state, ws_rules, handlers
end

local function active_rule_map(ws_rules)
	local m = {}
	for _, r in ipairs(ws_rules) do
		if r.enabled then
			m[r.workspace] = r.monitor
		end
	end
	return m
end

do
	local mons = {
		{ name = "DP-1", description = "Dell Inc. DELL U2723QE AAA111" },
		{ name = "HDMI-A-1", description = "ASUS PG27AQN XYZ999" },
	}
	local W, state, ws_rules = fresh_workspaces(mons)
	check(W.block(mons[1]) == 0 and W.base(mons[1]) == 0, "desktop: first monitor gets workspaces 1-10 (block 0)")
	check(W.block(mons[2]) == 1 and W.base(mons[2]) == 10, "desktop: second monitor gets workspaces 11-20 (block 1)")
	check(state["wsbase.DP-1"] == "0" and state["wsbase.HDMI-A-1"] == "10", "desktop: wsbase persisted as 0 and 10")
	local rm = active_rule_map(ws_rules)
	check(rm["1"] == "desc:Dell Inc. DELL U2723QE AAA111" and rm["10"] == "desc:Dell Inc. DELL U2723QE AAA111", "desktop: ws 1-10 bound to first monitor")
	check(rm["11"] == "desc:ASUS PG27AQN XYZ999" and rm["20"] == "desc:ASUS PG27AQN XYZ999", "desktop: ws 11-20 bound to second monitor")
end

do
	local mons = {
		{ name = "eDP-1", description = "Built-in Panel" },
		{ name = "DP-3", description = "Acer XV272U" },
	}
	local W = fresh_workspaces(mons)
	check(W.block(mons[1]) == 0, "laptop: eDP-1 keeps block 0")
	check(W.block(mons[2]) == 1, "laptop: external DP-3 gets block 1")
end

do
	local lid = { { name = "eDP-1", description = "Built-in Panel" } }
	local _, seen = fresh_workspaces(lid)
	local Wl = fresh_workspaces(lid, seen)
	Wl.block(lid[1])
	local docked = { { name = "HDMI-A-1", description = "LG 27GP850 NEW123" } }
	local Wd = fresh_workspaces(docked, { wsinternal = "1" })
	check(Wd.block(docked[1]) ~= 0, "laptop docked with the lid shut: a new monitor never takes the panel's workspaces 1-10")
end

do
	local mons = {
		{ name = "DP-1", make = "LG Electronics", model = "LG ULTRAGEAR", serial = "", description = "LG Electronics LG ULTRAGEAR" },
		{ name = "DP-2", make = "LG Electronics", model = "LG ULTRAGEAR", serial = "", description = "LG Electronics LG ULTRAGEAR" },
	}
	local W, _, ws_rules = fresh_workspaces(mons)
	check(W.block(mons[1]) == 0 and W.block(mons[2]) == 1, "identical monitors (no serial): distinct blocks 0 and 1")
	local rm = active_rule_map(ws_rules)
	check(rm["1"] == "DP-1" and rm["10"] == "DP-1", "identical monitors (no serial): ws 1-10 bound to DP-1 connector")
	check(rm["11"] == "DP-2" and rm["20"] == "DP-2", "identical monitors (no serial): ws 11-20 bound to DP-2 connector")
end

do
	local mons = {
		{ name = "DP-1", make = "Dell Inc.", model = "DELL U2723QE", serial = "SER001", description = "Dell Inc. DELL U2723QE" },
		{ name = "DP-2", make = "Dell Inc.", model = "DELL U2723QE", serial = "SER002", description = "Dell Inc. DELL U2723QE" },
	}
	local W, _, ws_rules = fresh_workspaces(mons)
	check(W.block(mons[1]) == 0 and W.block(mons[2]) == 1, "identical descriptions with distinct serials: distinct blocks 0 and 1")
	local rm = active_rule_map(ws_rules)
	check(rm["1"] == "DP-1" and rm["11"] == "DP-2", "identical descriptions with distinct serials: connector selector avoids desc collision")
end

do
	local m1 = { name = "DP-1", description = "LG Electronics LG ULTRAGEAR" }
	local m2 = { name = "DP-2", description = "LG Electronics LG ULTRAGEAR" }
	local mons = { m1 }
	local W, _, ws_rules, handlers = fresh_workspaces(mons)
	check(W.block(m1) == 0, "hotplug identical: first monitor starts on block 0")
	local rm = active_rule_map(ws_rules)
	check(rm["1"] == "desc:LG Electronics LG ULTRAGEAR", "hotplug identical: single monitor uses desc selector")

	mons[2] = m2
	for _, f in ipairs(handlers["monitor.added"] or {}) do
		f(m2)
	end
	check(W.block(m1) == 0, "hotplug identical: first monitor keeps block 0 after second arrives")
	check(W.block(m2) == 1, "hotplug identical: second identical monitor gets block 1")
	rm = active_rule_map(ws_rules)
	check(rm["1"] == "DP-1" and rm["10"] == "DP-1", "hotplug identical: first monitor rebound from desc to DP-1")
	check(rm["11"] == "DP-2" and rm["20"] == "DP-2", "hotplug identical: second monitor bound to DP-2")
end

if fails > 0 then
	os.exit(1)
end
print("ok test_display_presets_and_workspaces")
