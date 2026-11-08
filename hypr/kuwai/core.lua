-- kuwai.core — the small toolkit every other kuwai module builds on.
--
-- Rules this file lives by (Hyprland runs the whole config on its event loop
-- with a ~1.5s budget, and every bind callback on the same loop):
--   * never io.popen / os.execute / sleep at load or in a bind; spawn with
--     hl.exec_cmd and read files only from sysfs, tmpfs or ~/.config;
--   * one module failing must not take the session down: kuwai.init loads each
--     module through K.load, which records the error and carries on;
--   * everything user-visible goes through K.bind so it shows up, grouped, in
--     the rice's Shortcuts panel (Super+/), which parses "[Group|Sub] text".

local K = {}

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------
local env = os.getenv
K.home = env("HOME") or ""
K.config_home = env("XDG_CONFIG_HOME") or (K.home .. "/.config")
K.state_home = env("XDG_STATE_HOME") or (K.home .. "/.local/state")
K.data_home = env("XDG_DATA_HOME") or (K.home .. "/.local/share")
K.runtime = env("XDG_RUNTIME_DIR") or "/tmp"
K.hypr = K.config_home .. "/hypr" -- the user's own files (monitors.lua, user.lua)
-- KUWAI_ROOT is set by the entry file (~/.config/hypr/hyprland.lua).
K.root = KUWAI_ROOT or (K.home .. "/Projects/rice")
K.bin = K.root .. "/bin"
K.state_dir = K.state_home .. "/kuwai"

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------
function K.read(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

function K.read_line(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end

function K.exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- Is `cmd` on PATH (or an existing absolute path)? Pure file probes, no fork.
function K.has(cmd)
	if cmd:find("/", 1, true) then
		return K.exists(cmd)
	end
	for dir in ((env("PATH") or "/usr/bin") .. ":"):gmatch("([^:]*):") do
		if dir ~= "" and K.exists(dir .. "/" .. cmd) then
			return true
		end
	end
	return false
end

function K.q(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

---------------------------------------------------------------------------
-- Errors: collected, shown once at the end of the load, kept for `kuwai doctor`
---------------------------------------------------------------------------
K.errors = {}

function K.err(msg)
	K.errors[#K.errors + 1] = msg
	print("[kuwai] " .. msg)
end

-- Load a module by name; a failure is recorded, not fatal.
function K.load(name)
	local ok, res = pcall(require, name)
	if not ok then
		K.err(name .. ": " .. tostring(res))
		return nil
	end
	return res
end

-- Load an optional user file from ~/.config/hypr (monitors.lua, user.lua, ...).
function K.load_user(file)
	local path = K.hypr .. "/" .. file
	if not K.exists(path) then
		return false
	end
	local ok, err = pcall(dofile, path)
	if not ok then
		K.err(file .. ": " .. tostring(err))
	end
	return ok
end

-- Apply config through pcall so one bad table doesn't abort the module.
function K.config(t)
	local ok, err = pcall(hl.config, t)
	if not ok then
		K.err("hl.config: " .. tostring(err))
	end
end

-- Current value of an option, or nil.
function K.get(key)
	local ok, v = pcall(hl.get_config, key)
	if ok then
		return v
	end
	return nil
end

---------------------------------------------------------------------------
-- Persisted state (~/.local/state/kuwai/state): tiny key=value file, read at
-- load, written by kuwai.set_state (called from binds or `hyprctl eval`).
---------------------------------------------------------------------------
K.state = {}
do
	local s = K.read(K.state_dir .. "/state")
	if s then
		for k, v in s:gmatch("([%w_%.%-]+)=([^\n]*)") do
			K.state[k] = v
		end
	end
end

function K.set_state(key, value)
	K.state[key] = value ~= nil and tostring(value) or nil
	local f = io.open(K.state_dir .. "/state", "w")
	if not f then
		os.execute("mkdir -p -m 700 " .. K.q(K.state_dir)) -- first write only
		f = io.open(K.state_dir .. "/state", "w")
	end
	if not f then
		K.err("cannot write " .. K.state_dir .. "/state")
		return
	end
	local keys = {}
	for k in pairs(K.state) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		f:write(k, "=", K.state[k], "\n")
	end
	f:close()
end

---------------------------------------------------------------------------
-- Dispatch helpers
---------------------------------------------------------------------------
function K.run(d)
	if type(d) == "string" then
		hl.exec_cmd(d)
	elseif type(d) == "function" then
		d()
	elseif d ~= nil then
		hl.dispatch(d)
	end
end

-- Night Shift off: neutral, then identity. `identity` alone leaves the
-- reported temperature at the old warm value, so the center showed it on.
K.night_off = "hyprctl hyprsunset temperature 6500; hyprctl hyprsunset identity"

function K.notify(text, ms, icon)
	pcall(hl.notification.create, { text = text, timeout = ms or 2500, icon = icon or "ok" })
end

-- Run `fn` once per config load, after the compositor is up: on the first
-- start, or right after a reload. Timers must be created this way — one made
-- while the config is still loading crashes `Hyprland --verify-config` on exit
-- (its timer cleanup runs after the event loop is gone; Hyprland 0.57).
local deferred, ran = {}, false
function K.defer(fn)
	deferred[#deferred + 1] = fn
end
local function run_deferred()
	-- `--verify-config` also emits config.reloaded, but has no screens.
	if ran or #(hl.get_monitors() or {}) == 0 then
		return
	end
	ran = true
	for _, fn in ipairs(deferred) do
		local ok, err = pcall(fn)
		if not ok then
			K.err("deferred: " .. tostring(err))
		end
	end
end
hl.on("hyprland.start", run_deferred)
hl.on("config.reloaded", run_deferred)

function K.on_start(cmd)
	hl.on("hyprland.start", function()
		K.run(cmd)
	end)
end

---------------------------------------------------------------------------
-- Binds
--
--   K.group("Windows")                      -- sets the panel group
--   K.bind("SUPER + Q", "Close window", hl.dsp.window.close())
--   K.bind("SUPER + T", "Terminal", "kitty")              -- string = command
--   K.bind("SUPER + W", "Float toggle", function() ... end)
--
-- Re-binding the same keys later (e.g. in user.lua) replaces the earlier one.
---------------------------------------------------------------------------
local group = nil
local submap = "" -- binds inside K.submap() are keyed apart from global ones
K.binds = {} -- submap|keys -> handle, so a later bind on the same keys replaces it
K.bind_desc = {} -- submap|keys -> its description
K.conflicts = {} -- kuwai binds that replaced another kuwai bind (kuwai doctor)
_G.kuwai = _G.kuwai or {}
_G.kuwai.bind_conflicts = function()
	return table.concat(K.conflicts, "\n")
end

local function bind_id(keys, release)
	return submap .. "|" .. keys:upper():gsub("%s+", "") .. (release and "#release" or "")
end

function K.group(name)
	group = name
end

function K.bind(keys, desc, action, opts)
	opts = opts or {}
	if desc and desc ~= "" then
		opts.description = group and ("[" .. group .. "] " .. desc) or desc
	end
	local d = action
	if type(action) == "string" then
		d = hl.dsp.exec_cmd(action)
	end
	local id = bind_id(keys, opts.release)
	if K.binds[id] then
		-- Replacing is how user.lua overrides a kuwai bind. Two of kuwai's
		-- own files on the same keys is a mistake: kept for `kuwai doctor`.
		local src = (debug.getinfo(2, "S") or {}).short_src or ""
		local was = K.bind_desc[id]
		if not src:find("user%.lua") and was and was ~= opts.description then
			K.conflicts[#K.conflicts + 1] = keys .. ": " .. tostring(was) .. " ← replaced by " .. tostring(opts.description)
		end
		pcall(function()
			K.binds[id]:remove()
		end)
	end
	local ok, b = pcall(hl.bind, keys, d, opts)
	if not ok then
		K.err("bind '" .. keys .. "': " .. tostring(b))
		return nil
	end
	K.binds[id] = b
	K.bind_desc[id] = opts.description
	-- The palette (Super+/ in the shell) lists and runs every described,
	-- pressable bind of the main keymap.
	if desc and desc ~= "" and submap == "" and not opts.mouse and not opts.release and not keys:find("^switch:") then
		if not K.palette_index[id] then
			K.palette_order[#K.palette_order + 1] = id
		end
		K.palette_index[id] = { group = group or "Other", text = desc, keys = keys, action = d }
	end
	return b
end

K.palette_order, K.palette_index = {}, {}

local function json_str(v)
	return '"' .. tostring(v):gsub('[%c"\\]', function(c)
		return ({ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" })[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end
K.json_str = json_str

function K.unbind(keys)
	for _, release in ipairs({ false, true }) do
		local id = bind_id(keys, release)
		if K.binds[id] then
			pcall(function()
				K.binds[id]:remove()
			end)
			K.binds[id] = nil
		end
	end
end

-- Define a submap; binds made inside `fn` belong to it.
function K.submap(name, fn)
	local ok, err = pcall(hl.define_submap, name, function()
		local prev = submap
		submap = name
		local ok2, err2 = pcall(fn)
		submap = prev
		if not ok2 then
			K.err("submap " .. name .. ": " .. tostring(err2))
		end
	end)
	if not ok then
		K.err("submap " .. name .. ": " .. tostring(err))
	end
end

-- Press runs one action, release another (push-to-talk). A plain release bind
-- is skipped once any other key is released during the hold, so the release
-- half is transparent, ignores mods, doesn't consume, and only fires after its
-- own press did. (Pattern from Omarchy's helpers.lua.)
function K.bind_hold(keys, desc, press, release, opts)
	local held = false
	local p = {}
	for k, v in pairs(opts or {}) do
		p[k] = v
	end
	K.bind(keys, desc, function()
		held = true
		K.run(press)
	end, p)
	K.bind(keys, nil, function()
		if held then
			held = false
			K.run(release)
		end
	end, { release = true, transparent = true, ignore_mods = true, non_consuming = true })
end

return K
