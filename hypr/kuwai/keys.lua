local K = require("kuwai.core")

local M = { applied = {}, displaced = {}, hidden = {}, overrides = {}, fkeys = { "F7", "F8", "F10" } }

function M.path()
	return K.config_home .. "/kuwai/keys.tsv"
end

local mods = { SUPER = true, CTRL = true, ALT = true, SHIFT = true }

function M.valid(keys)
	if keys == "" then
		return true
	end
	local n, key = 0, nil
	for part in keys:gmatch("[^+]+") do
		local p = part:gsub("^%s+", ""):gsub("%s+$", "")
		if key then
			return false
		end
		if mods[p:upper()] then
			n = n + 1
		elseif p:match("^[%w_]+$") or p:match("^code:%d+$") then
			key = p
		else
			return false
		end
	end
	return key ~= nil and n <= 4
end

function M.read()
	local out = {}
	local s = K.read(M.path())
	if not s then
		return out
	end
	for line in s:gmatch("[^\n]+") do
		local aid, keys, text = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)$")
		if aid and M.valid(keys) then
			out[#out + 1] = { aid = aid, keys = keys, text = text }
		end
	end
	return out
end

function M.fixed(e)
	return K.bind_spec[e.id .. "#release"] ~= nil
end

function M.plain()
	if M.plain_fkeys == nil then
		M.plain_fkeys = K.setting("fKeys") == "plain"
	end
	return M.plain_fkeys
end

local function copy(t)
	local o = {}
	for k, v in pairs(t or {}) do
		o[k] = v
	end
	return o
end

local function drop(id)
	local b = K.binds[id]
	if not b then
		return false
	end
	pcall(function()
		b:remove()
	end)
	K.binds[id] = nil
	M.displaced[id] = true
	return true
end

local function restore(id)
	local spec = K.bind_spec[id]
	if not spec or K.binds[id] then
		return
	end
	local ok, b = pcall(hl.bind, spec.keys, spec.d, copy(spec.opts))
	if ok and b then
		K.binds[id] = b
	end
end

function M.apply()
	for _, r in pairs(M.applied) do
		if K.binds[r.id] == r.bind then
			pcall(function()
				r.bind:remove()
			end)
			K.binds[r.id] = nil
		end
	end
	local back = M.displaced
	M.applied, M.displaced, M.hidden, M.overrides = {}, {}, {}, {}
	for id in pairs(back) do
		restore(id)
	end
	local list = {}
	for _, o in ipairs(M.read()) do
		local e = K.palette_index["|" .. o.aid]
		if e and e.text == o.text and not M.fixed(e) and not M.overrides[e.id] then
			o.entry = e
			list[#list + 1] = o
			M.overrides[e.id] = o.keys
			drop(e.id)
		end
	end
	if M.plain() then
		for _, k in ipairs(M.fkeys) do
			local id = K.bind_id(k)
			if K.palette_index[id] and not M.overrides[id] and drop(id) then
				M.hidden[id] = true
			end
		end
	end
	for _, o in ipairs(list) do
		local spec = K.bind_spec[o.entry.id]
		if o.keys ~= "" and spec then
			local nid = K.bind_id(o.keys)
			drop(nid)
			if K.palette_index[nid] and M.overrides[nid] == nil then
				M.overrides[nid] = ""
			end
			local ok, b = pcall(hl.bind, o.keys, spec.d, copy(spec.opts))
			if ok and b then
				K.binds[nid] = b
				M.applied[o.entry.id] = { id = nid, bind = b, keys = o.keys }
			else
				K.err("bind '" .. o.keys .. "': " .. tostring(b))
			end
		end
	end
end

function M.current(e)
	local o = M.overrides[e.id]
	if o == nil then
		return e.keys, false
	end
	return K.show(o), true
end

M.capture = "kuwai_capture"
K.submap(M.capture, function()
	K.bind("SUPER + CTRL + ALT + SHIFT + Escape", "", hl.dsp.submap("reset"))
end)
local turn = 0
pcall(hl.on, "keybinds.submap", function(name)
	turn = turn + 1
	if name ~= M.capture then
		return
	end
	local mine = turn
	pcall(hl.timer, function()
		if turn == mine then
			hl.dispatch(hl.dsp.submap("reset"))
		end
	end, { timeout = 30000, type = "oneshot" })
end)

_G.kuwai = _G.kuwai or {}

function kuwai.keys_apply()
	local ok, err = pcall(M.apply)
	if not ok then
		K.notify("kuwai: " .. tostring(err), 4000, "error")
	end
	return hl.dsp.no_op()
end

function kuwai.fkeys(plain)
	M.plain_fkeys = plain and true or false
	return kuwai.keys_apply()
end

return M
