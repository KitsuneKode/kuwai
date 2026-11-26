local K = {}

local env = os.getenv
K.home = env("HOME") or ""
K.config_home = env("XDG_CONFIG_HOME") or (K.home .. "/.config")
K.state_home = env("XDG_STATE_HOME") or (K.home .. "/.local/state")
K.data_home = env("XDG_DATA_HOME") or (K.home .. "/.local/share")
K.runtime = env("XDG_RUNTIME_DIR") or "/tmp"
K.hypr = K.config_home .. "/hypr"
K.user_dir = KUWAI_USER_DIR or K.hypr
K.root = KUWAI_ROOT or (K.data_home .. "/kuwai")
K.bin = K.root .. "/bin"
K.state_dir = K.state_home .. "/kuwai"

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

K.hyde_lib = K.home .. "/.local/lib/hyde"
K.hyde = K.exists(K.hyde_lib .. "/globalcontrol.sh")

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

K.errors = {}

function K.err(msg)
	K.errors[#K.errors + 1] = msg
	print("[kuwai] " .. msg)
end

function K.load(name)
	local ok, res = pcall(require, name)
	if not ok then
		K.err(name .. ": " .. tostring(res))
		K.reload_again()
		return nil
	end
	return res
end

local again_mark = K.runtime .. "/kuwai-reload-again"
function K.reload_again()
	if K.reloading_again then
		return
	end
	K.reloading_again = true
	K.defer(function()
		if os.time() - (tonumber(K.read_line(again_mark) or "") or 0) < 10 then
			return
		end
		local f = io.open(again_mark, "w")
		if f then
			f:write(tostring(os.time()))
			f:close()
		end
		hl.timer(function()
			hl.exec_cmd("hyprctl reload")
		end, { timeout = 500, type = "oneshot" })
	end)
end

function K.load_user(file)
	local path = K.user_dir .. "/" .. file
	if not K.exists(path) then
		return false
	end
	local ok, err = pcall(dofile, path)
	if not ok then
		K.err(file .. ": " .. tostring(err))
	end
	return ok
end

function K.config(t)
	local ok, err = pcall(hl.config, t)
	if not ok then
		K.err("hl.config: " .. tostring(err))
	end
end

function K.get(key)
	local ok, v = pcall(hl.get_config, key)
	if ok then
		return v
	end
	return nil
end

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
		os.execute("mkdir -p -m 700 " .. K.q(K.state_dir))
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

function K.run(d)
	if type(d) == "string" then
		hl.exec_cmd(d)
	elseif type(d) == "function" then
		d()
	elseif d ~= nil then
		hl.dispatch(d)
	end
end

K.night_off = "hyprctl hyprsunset temperature 6500; hyprctl hyprsunset identity"

function K.notify(text, ms, icon)
	pcall(hl.notification.create, { text = text, timeout = ms or 2500, icon = icon or "ok" })
end

local deferred, ran = {}, false
function K.defer(fn)
	deferred[#deferred + 1] = fn
end
local function run_deferred()
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

local group = nil
local submap = ""
K.binds = {}
K.bind_desc = {}
K.conflicts = {}
_G.kuwai = _G.kuwai or {}
_G.kuwai.bind_conflicts = function()
	return table.concat(K.conflicts, "\n")
end

local mod_names = { SUPER = "SUPER", WIN = "SUPER", LOGO = "SUPER", MOD4 = "SUPER", META = "SUPER", CTRL = "CTRL", CONTROL = "CTRL", ALT = "ALT", MOD1 = "ALT", SHIFT = "SHIFT" }
local mod_order = { "SUPER", "CTRL", "ALT", "SHIFT" }

function K.chord(keys)
	local mods, key = {}, ""
	for part in tostring(keys or ""):gmatch("[^+]+") do
		local p = part:gsub("^%s+", ""):gsub("%s+$", ""):upper()
		if mod_names[p] then
			mods[mod_names[p]] = true
		elseif p ~= "" then
			key = p
		end
	end
	local out = {}
	for _, m in ipairs(mod_order) do
		if mods[m] then
			out[#out + 1] = m
		end
	end
	out[#out + 1] = key
	return table.concat(out, "+")
end

function K.show(keys)
	return (tostring(keys or ""):gsub("code:(%d+)", function(n)
		n = tonumber(n)
		if n >= 10 and n <= 19 then
			return tostring((n - 9) % 10)
		end
	end))
end

local function bind_id(keys, release)
	return submap .. "|" .. K.chord(keys) .. (release and "#release" or "")
end
K.bind_id = bind_id
K.bind_spec = {}

function K.group(name)
	group = name
end

function K.bind(keys, desc, action, opts)
	opts = opts or {}
	local show = opts.show or keys
	opts.show = nil
	if desc and desc ~= "" then
		opts.description = group and ("[" .. group .. "] " .. desc) or desc
	end
	local d = action
	if type(action) == "string" then
		d = hl.dsp.exec_cmd(action)
	end
	local id = bind_id(keys, opts.release)
	if K.binds[id] then
		local src = (debug.getinfo(2, "S") or {}).short_src or ""
		local was = K.bind_desc[id]
		if not src:find("user%.lua") and was and was ~= opts.description then
			K.conflicts[#K.conflicts + 1] = keys .. ": " .. tostring(was) .. " ← replaced by " .. tostring(opts.description)
		end
		pcall(function()
			K.binds[id]:remove()
		end)
	end
	local spec = {}
	for k, v in pairs(opts) do
		spec[k] = v
	end
	local ok, b = pcall(hl.bind, keys, d, opts)
	if not ok then
		K.err("bind '" .. keys .. "': " .. tostring(b))
		return nil
	end
	K.binds[id] = b
	K.bind_desc[id] = opts.description
	K.bind_spec[id] = { keys = keys, d = d, opts = spec }
	if desc and desc ~= "" and submap == "" and not opts.mouse and not opts.release and not keys:find("^switch:") then
		if not K.palette_index[id] then
			K.palette_order[#K.palette_order + 1] = id
		end
		K.palette_index[id] = { id = id, aid = K.chord(keys), group = group or "Other", text = desc, keys = show, action = d }
	end
	return b
end

function K.setting(key)
	local s = K.read(K.config_home .. "/kuwai/settings.json")
	if not s then
		return nil
	end
	local v = s:match('"' .. key .. '"%s*:%s*("[^"]*")') or s:match('"' .. key .. '"%s*:%s*([%w%.%-]+)')
	if not v then
		return nil
	end
	if v:sub(1, 1) == '"' then
		return v:sub(2, -2)
	end
	if v == "true" or v == "false" then
		return v == "true"
	end
	return tonumber(v)
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
