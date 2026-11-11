-- A screen that loses power and comes back (hypr/kuwai/workspaces.lua):
-- its windows fold onto the screen that's left, then go home, and it shows
-- what it showed. Against a small stand-in for Hyprland's Lua API.
--   lua tests/hypr/test_outage.lua      (from the repo root)

package.path = "hypr/?.lua;hypr/?/init.lua;" .. package.path

local world, handlers, timers, state

-- Any table path that isn't defined is a no-op function (hl.window_rule, …).
local function auto(name)
	return setmetatable({}, {
		__index = function(t, k)
			local v = auto(name .. "." .. k)
			rawset(t, k, v)
			return v
		end,
		__call = function(_, args)
			return { op = name:gsub("^dsp%.", ""), args = args or {} }
		end,
	})
end

local function mon(name)
	for _, m in ipairs(world.monitors) do
		if m.name == name then
			return m
		end
	end
end
local function block_of(id)
	return math.floor((id - 1) / 10)
end
local function ws(id)
	for _, w in ipairs(world.workspaces) do
		if w.id == id then
			return w
		end
	end
	-- New workspace: the screen its block belongs to (kuwai's rule), else the focused one.
	local home
	for _, m in ipairs(world.monitors) do
		if m.block == block_of(id) then
			home = m
		end
	end
	home = home or mon(world.active)
	local w = { id = id, monitor = { name = home.name } }
	table.insert(world.workspaces, w)
	return w
end
local function apply(a)
	if a.op == "window.move" then
		local addr = a.args.window:gsub("^address:", "")
		for _, w in ipairs(world.windows) do
			if tostring(w.address) == addr then
				ws(a.args.workspace)
				w.workspace = { id = a.args.workspace }
			end
		end
	elseif a.op == "focus" and a.args.workspace then
		local w = ws(a.args.workspace)
		local m = mon(w.monitor.name)
		m.active_workspace = { id = w.id }
		world.active = m.name
		for _, f in ipairs(handlers["workspace.active"] or {}) do
			f()
		end
	elseif a.op == "workspace.move" then
		ws(a.args.workspace).monitor = { name = a.args.monitor }
	end
end

local function fresh_hl()
	handlers, timers = {}, {}
	_G.hl = auto("hl")
	hl.dsp = auto("dsp")
	hl.on = function(ev, f)
		handlers[ev] = handlers[ev] or {}
		table.insert(handlers[ev], f)
	end
	hl.timer = function(f, o)
		table.insert(timers, { f = f, t = o.timeout or 0 })
	end
	hl.dispatch = function(a)
		if type(a) == "table" and a.op then
			apply(a)
		end
	end
	hl.get_monitors = function()
		return world.monitors
	end
	hl.get_active_monitor = function()
		return mon(world.active)
	end
	hl.get_windows = function()
		return world.windows
	end
	hl.get_workspaces = function()
		return world.workspaces
	end
	hl.get_active_workspace = function()
		local m = mon(world.active)
		return m and m.active_workspace
	end
	local K = {
		state = state,
		feature = function(f)
			return f == "per_monitor_ws"
		end,
		set_state = function(k, v)
			state[k] = v ~= nil and tostring(v) or nil
		end,
	}
	setmetatable(K, { __index = function(_, k)
		return auto("K." .. k)
	end })
	package.loaded["kuwai.core"] = K
	package.loaded["kuwai.workspaces"] = nil
	dofile(os.getenv("WS_FILE") or "hypr/kuwai/workspaces.lua")
end
local function fire(ev, ...)
	for _, f in ipairs(handlers[ev] or {}) do
		f(...)
	end
end
local function run_timers()
	while #timers > 0 do
		table.sort(timers, function(a, b)
			return a.t < b.t
		end)
		local t = table.remove(timers, 1)
		t.f()
	end
end

local function setup(focus)
	state = { ["wsblock.Acer_XV272U"] = "1" }
	world = {
		monitors = {
			{ name = "eDP-1", description = "", block = 0, x = 0, active_workspace = { id = 2 } },
			{ name = "DP-3", description = "Acer XV272U", block = 1, x = 1920, active_workspace = { id = 13 } },
		},
		workspaces = { { id = 2, monitor = { name = "eDP-1" } }, { id = 11, monitor = { name = "DP-3" } }, { id = 13, monitor = { name = "DP-3" } } },
		windows = {
			{ address = "0xa", workspace = { id = 2 } },
			{ address = "0xb", workspace = { id = 13 } },
			{ address = "0xc", workspace = { id = 11 } },
		},
		active = focus,
	}
	fresh_hl()
	fire("workspace.active")
end
local function unplug()
	local dp
	for i, m in ipairs(world.monitors) do
		if m.name == "DP-3" then
			dp = table.remove(world.monitors, i)
		end
	end
	for _, w in ipairs(world.workspaces) do
		if w.monitor.name == "DP-3" then
			w.monitor = { name = "eDP-1" }
		end
	end
	world.active = "eDP-1"
	fire("monitor.removed")
	return dp
end
local function plug(dp)
	dp.active_workspace = { id = 11 } -- Hyprland's default for it, not what it showed
	table.insert(world.monitors, dp)
	fire("monitor.added", dp)
end
local function where(addr)
	for _, w in ipairs(world.windows) do
		if w.address == addr then
			return w.workspace.id
		end
	end
end

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed = failed + 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	else
		print("ok   " .. name)
	end
end

-- 1. Power out and back, you were on the Acer.
setup("DP-3")
local dp = unplug()
run_timers()
check("out: b folds into the laptop's 3", where("0xb"), 3)
check("out: c folds into the laptop's 1", where("0xc"), 1)
check("out: a stays", where("0xa"), 2)
check("out: homes kept in state", state["wshomes"] ~= nil, true)
plug(dp)
run_timers()
check("back: b home in 13", where("0xb"), 13)
check("back: c home in 11", where("0xc"), 11)
check("back: a stays", where("0xa"), 2)
check("back: the Acer shows 13 again", mon("DP-3").active_workspace.id, 13)
check("back: you're on the Acer again", world.active, "DP-3")
check("back: homes cleared", state["wshomes"], nil)

-- 2. A flap: back before the fold ran. Nothing moves.
setup("DP-3")
dp = unplug()
plug(dp)
run_timers()
check("flap: a stays", where("0xa"), 2)
check("flap: b stays", where("0xb"), 13)
check("flap: c stays", where("0xc"), 11)

-- 3. A config reload while it's dark: homes come from state.
setup("DP-3")
dp = unplug()
run_timers()
fresh_hl()
plug(dp)
run_timers()
check("reload: b home", where("0xb"), 13)
check("reload: c home", where("0xc"), 11)

-- 4. You were on the laptop: the Acer shows its 13, focus stays with you.
setup("eDP-1")
dp = unplug()
run_timers()
plug(dp)
run_timers()
check("laptop focus: Acer shows 13", mon("DP-3").active_workspace.id, 13)
check("laptop focus: you stay on the laptop", world.active, "eDP-1")

-- 5. A window closed while dark is forgotten, not chased.
setup("DP-3")
dp = unplug()
run_timers()
table.remove(world.windows, 3)
plug(dp)
run_timers()
check("closed: homes cleared", state["wshomes"], nil)

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("all passed")
