local K = require("kuwai.core")

_G.kuwai = _G.kuwai or {}
kuwai.K = K
kuwai.version = (K.read_line(K.root .. "/VERSION") or "0.1.0"):gsub("%s+$", "")
kuwai.loaded_at = os.time()

K.F = K.load("kuwai.features")
K.load_user("features.lua")

K.gpu = K.load("kuwai.gpu")
K.load("kuwai.env")
K.load("kuwai.system")
K.load("kuwai.input")
K.load("kuwai.layout")
K.look = K.load("kuwai.look")
K.theme = package.loaded["kuwai.theme"]
K.motion = K.load("kuwai.motion")
K.load("kuwai.apps")
K.rules = K.load("kuwai.rules")
K.load("kuwai.browsers")
K.workspaces = K.load("kuwai.workspaces")
K.load("kuwai.automation")
K.load("kuwai.binds")
K.load("kuwai.extras")
K.load("kuwai.chatwin")
K.load("kuwai.resilience")
K.load("kuwai.voxtype")
K.load("kuwai.hyde")
K.load("kuwai.startup")

pcall(hl.monitor, { output = "", mode = "preferred", position = "auto", scale = "auto" })
K.display = K.load("kuwai.display")
K.load_user("monitors.lua")

K.load_user("user.lua")

K.modes = K.load("kuwai.modes")
if K.modes then
	K.modes.apply()
end
if K.display then
	K.display.apply()
end

local report = K.state_dir .. "/errors"
local f = io.open(report, "w")
if not f then
	os.execute("mkdir -p -m 700 " .. K.q(K.state_dir))
	f = io.open(report, "w")
end
if f then
	f:write(table.concat(K.errors, "\n"), #K.errors > 0 and "\n" or "")
	f:close()
end
if #K.errors > 0 then
	K.notify("kuwai: " .. #K.errors .. " problem(s) — run `kuwai doctor`\n" .. K.errors[1], 10000, "error")
end

function kuwai.errors()
	return table.concat(K.errors, "\n")
end

function kuwai.info()
	local g = K.gpu or {}
	return ("kuwai %s · mode %s · gpu %s (%s) · theme %s"):format(
		kuwai.version,
		K.modes and K.modes.current or "?",
		g.primary or "?",
		g.mode or "?",
		(K.theme or {}).name or "?"
	)
end

function kuwai.palette()
	local j, out = K.json_str, {}
	for i, id in ipairs(K.palette_order) do
		local e = K.palette_index[id]
		out[#out + 1] = ('{"id":"b%d","kind":"bind","group":%s,"text":%s,"keys":%s}'):format(i, j(e.group), j(e.text), j(e.keys))
	end
	local F = K.F or { defaults = {}, describe = {} }
	local names = {}
	for n in pairs(F.defaults) do
		names[#names + 1] = n
	end
	table.sort(names)
	for _, n in ipairs(names) do
		out[#out + 1] = ('{"id":"f:%s","kind":"feature","group":"Features","text":%s,"name":%s,"on":%s}'):format(
			n, j(F.describe[n] or n), j(n), K.feature(n) and "true" or "false")
	end
	local M = K.modes
	if M then
		for _, m in ipairs(M.list) do
			out[#out + 1] = ('{"id":"m:%s","kind":"mode","group":"Modes","text":%s,"name":%s,"on":%s}'):format(
				m, j(M.describe[m] or m), j(m), M.current == m and "true" or "false")
		end
	end
	return "[" .. table.concat(out, ",") .. "]"
end

function kuwai.run(id)
	id = tostring(id)
	local ok, err = pcall(function()
		local b = id:match("^b(%d+)$")
		if b then
			local e = K.palette_index[K.palette_order[tonumber(b)]]
			if e then
				K.run(e.action)
			end
			return
		end
		local f = id:match("^f:([%w_]+)$")
		if f then
			kuwai.feature(f, not K.feature(f))
			return
		end
		local m = id:match("^m:([%w_]+)$")
		if m then
			kuwai.mode(m)
		end
	end)
	if not ok then
		K.notify("kuwai: " .. tostring(err), 4000, "error")
	end
	return hl.dsp.no_op()
end
