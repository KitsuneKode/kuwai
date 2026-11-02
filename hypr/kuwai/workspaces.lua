-- kuwai.workspaces — where windows live.
--
-- Per-monitor workspaces (feature per_monitor_ws). Hyprland numbers workspaces
-- globally, so each screen owns a block of ten: the laptop panel 1–10, the
-- next screen 11–20, … Super+3 is the third workspace *of the focused screen*.
-- A block belongs to the physical monitor (its description: make, model,
-- serial), remembered in kuwai's state, so the Acer gets 11–20 back whether it
-- arrives as DP-3 or HDMI-A-5. Off: plain global 1–10, as before.
--
-- Layout per workspace (feature layouts): Super+Alt+L cycles the current
-- workspace through scrolling → dwindle → monocle → floating. Remembered.
--
-- Quake console (feature quake): Super+` drops a terminal over whatever you're
-- on — its own special workspace, spawned the first time it's opened.
--
-- Minimize (feature minimize): Super+O tucks a window into special:minimized,
-- Super+Shift+O brings the most recent back to where you are.

local K = require("kuwai.core")

local W = {}
local dsp = hl.dsp

---------------------------------------------------------------------------
-- Monitor blocks
---------------------------------------------------------------------------
local function ident(m)
	return (m and m.description and m.description ~= "") and m.description or (m and m.name) or "?"
end

local function is_internal(m)
	return m and m.name and m.name:match("^eDP") ~= nil
end

-- Block index for a monitor; assigns and persists the next free one on first sight.
function W.block(m)
	if not K.feature("per_monitor_ws") or not m then
		return 0
	end
	if is_internal(m) then
		return 0
	end
	local key = "wsblock." .. ident(m):gsub("[^%w]", "_")
	local b = tonumber(K.state[key])
	if b then
		return b
	end
	local used = { [0] = true }
	for k, v in pairs(K.state) do
		if k:match("^wsblock%.") then
			used[tonumber(v) or -1] = true
		end
	end
	b = 1
	while used[b] do
		b = b + 1
	end
	K.set_state(key, b)
	return b
end

function W.base(m)
	return W.block(m or hl.get_active_monitor()) * 10
end

-- Bind each screen's block to it, so its workspaces open there and come back
-- there after an unplug.
local rules = {}
local function claim(m)
	if not K.feature("per_monitor_ws") or not m then
		return
	end
	local base = W.base(m)
	local sel = "desc:" .. ident(m)
	for n = 1, 10 do
		local id = tostring(base + n)
		if not rules[id] then
			local spec = { workspace = id, monitor = sel, default = (n == 1) }
			if base > 0 then
				spec.default_name = tostring(n) -- bars show 1–10 on every screen
			end
			local ok, h = pcall(hl.workspace_rule, spec)
			if ok then
				rules[id] = h
			end
		end
	end
end

local function reclaim(m)
	-- Workspaces of this block that drifted to another screen come home.
	local base = W.base(m)
	for _, ws in ipairs(hl.get_workspaces() or {}) do
		if ws.id and ws.id > base and ws.id <= base + 10 and ws.monitor and ws.monitor.name ~= m.name then
			hl.dispatch(dsp.workspace.move({ workspace = ws.id, monitor = m.name }))
		end
	end
end

for _, m in ipairs(hl.get_monitors() or {}) do
	claim(m)
end
hl.on("monitor.added", function(m)
	claim(m)
	if K.feature("per_monitor_ws") then
		reclaim(m)
	end
end)

-- Workspace n of the focused screen.
function W.ws(n)
	return W.base() + n
end

---------------------------------------------------------------------------
-- Desktops (feature desktops): "desktop n" is workspace n of every screen
-- (each screen's own block: laptop n, the next screen 10+n…). Switching a
-- desktop switches every screen together; keys, pills and the island all
-- speak in desktops, so there is one row, the same on every screen.
---------------------------------------------------------------------------
local function desktops()
	return K.feature("desktops") and K.feature("per_monitor_ws")
end
W.desktops = desktops
K.set_state("workspace_model", desktops() and "desktops" or (K.feature("per_monitor_ws") and "per_screen" or "global"))

-- The desktop you're on: the focused screen's workspace, within its block.
function W.current()
	local cur = hl.get_active_workspace()
	local base = W.base()
	local id = cur and cur.id or 0
	if id > base and id <= base + 10 then
		return id - base
	end
	return 1
end

-- Show desktop n: every other screen first (cursor warps off, so neither the
-- pointer nor focus leaves you), then your own screen last, so focus ends
-- where you are and all screens slide together.
function W.go(n)
	n = math.max(1, math.min(10, n))
	if not desktops() then
		hl.dispatch(dsp.focus({ workspace = W.ws(n) }))
		return
	end
	local here = hl.get_active_monitor()
	K.config({ cursor = { no_warps = true } })
	for _, m in ipairs(hl.get_monitors() or {}) do
		if not here or m.name ~= here.name then
			hl.dispatch(dsp.focus({ workspace = W.base(m) + n }))
		end
	end
	if here then
		hl.dispatch(dsp.focus({ workspace = W.base(here) + n }))
	end
	K.config({ cursor = { no_warps = false } })
	K.set_state("desktop", n)
end

function W.focus(n)
	return function()
		W.go(n)
	end
end

function W.send(n, follow)
	return function()
		hl.dispatch(dsp.window.move({ workspace = W.ws(n), follow = false }))
		if follow then
			W.go(n)
		end
	end
end

-- Step through this screen's block (clamped, empty ones included).
function W.step(delta, carry)
	return function()
		local cur = hl.get_active_workspace()
		local base = W.base()
		local id = (cur and cur.id and cur.id > 0) and cur.id or (base + 1)
		-- On a workspace from another screen's block (a guest after an unplug),
		-- step from this screen's first one instead of jumping to its edge.
		if id <= base or id > base + 10 then
			id = base + 1 - (delta > 0 and 1 or -1)
		end
		local n = math.max(1, math.min(10, (id - base) + delta))
		if carry then
			hl.dispatch(dsp.window.move({ workspace = base + n, follow = false }))
		end
		W.go(n)
	end
end

-- The first empty workspace of the focused screen's own block (Hyprland's
-- "empty" picks the lowest empty id anywhere, which can be another screen's).
function W.empty()
	return function()
		local base = W.base()
		local used = {}
		for _, ws in ipairs(hl.get_workspaces() or {}) do
			if ws.id and (ws.windows or 0) > 0 then
				used[ws.id] = true
			end
		end
		for n = 1, 10 do
			local empty = not used[base + n]
			if empty and desktops() then
				-- a desktop is empty only if it's empty on every screen
				for _, m in ipairs(hl.get_monitors() or {}) do
					if used[W.base(m) + n] then
						empty = false
					end
				end
			end
			if empty then
				W.go(n)
				return
			end
		end
	end
end

---------------------------------------------------------------------------
-- Layout per workspace
---------------------------------------------------------------------------
W.cycle = { "scrolling", "dwindle", "monocle", "floating" }
local layout_rules, float_rules = {}, {}

local function set_layout(id, name, quiet)
	local key = tostring(id)
	if layout_rules[key] then
		pcall(function()
			layout_rules[key]:set_enabled(false)
		end)
		layout_rules[key] = nil
	end
	if float_rules[key] then
		pcall(function()
			float_rules[key]:set_enabled(false)
		end)
		float_rules[key] = nil
	end
	local tiled = (name == "floating") and "scrolling" or name
	local ok, h = pcall(hl.workspace_rule, { workspace = key, layout = tiled })
	if ok then
		layout_rules[key] = h
	end
	if name == "floating" then
		-- New windows on this workspace float; existing ones are floated and
		-- tagged so leaving the mode tiles exactly those again.
		local ok2, r = pcall(hl.window_rule, { name = "kuwai-floatws-" .. key, match = { workspace = key }, float = true })
		if ok2 then
			float_rules[key] = r
		end
		if not quiet then
			for _, w in ipairs(hl.get_workspace_windows(id) or {}) do
				if not w.floating then
					local s = "address:" .. w.address
					hl.dispatch(dsp.window.tag({ window = s, tag = "+kuwai-floated" }))
					hl.dispatch(dsp.window.float({ window = s, action = "enable" }))
				end
			end
		end
	elseif not quiet then
		for _, w in ipairs(hl.get_workspace_windows(id) or {}) do
			local tags = type(w.tags) == "table" and table.concat(w.tags, " ") or tostring(w.tags or "")
			if w.floating and tags:find("kuwai%-floated") then
				local s = "address:" .. w.address
				hl.dispatch(dsp.window.tag({ window = s, tag = "-kuwai-floated" }))
				hl.dispatch(dsp.window.float({ window = s, action = "disable" }))
			end
		end
	end
end

if K.feature("layouts") then
	for k, v in pairs(K.state) do
		local id = k:match("^layout%.(%-?%d+)$")
		if id then
			set_layout(tonumber(id), v, true)
		end
	end
end

function W.layout_next(dir)
	return function()
		local ws = hl.get_active_workspace()
		if not ws or not ws.id or ws.id <= 0 then
			return
		end
		local cur = K.state["layout." .. ws.id] or ws.tiled_layout or "scrolling"
		local i = 1
		for j, n in ipairs(W.cycle) do
			if n == cur then
				i = j
			end
		end
		local nxt = W.cycle[((i - 1 + (dir or 1)) % #W.cycle) + 1]
		set_layout(ws.id, nxt)
		K.set_state("layout." .. ws.id, nxt)
		K.notify("Workspace " .. (ws.id - W.base()) .. ": " .. nxt, 1200)
	end
end

---------------------------------------------------------------------------
-- Next / previous, whatever the context
---------------------------------------------------------------------------
-- In a group: the next tab. Monocle: the next window. Scrolling: the next
-- column. Otherwise: the next window on the workspace.
function W.next(forward)
	return function()
		local w = hl.get_active_window()
		if w and w.group and (w.group.size or 0) > 1 then
			hl.dispatch(forward and dsp.group.next() or dsp.group.prev())
			return
		end
		local ws = hl.get_active_workspace()
		local lay = ws and ws.tiled_layout
		if lay == "monocle" then
			hl.dispatch(dsp.layout(forward and "cyclenext" or "cycleprev"))
		elseif lay == "scrolling" and not (w and w.floating) then
			hl.dispatch(dsp.layout(forward and "focus r" or "focus l"))
		else
			hl.dispatch(dsp.window.cycle_next({ next = forward }))
		end
	end
end

-- Super+J: rearrange, per layout.
function W.arrange()
	local ws = hl.get_active_workspace()
	local lay = ws and ws.tiled_layout
	if lay == "dwindle" then
		hl.dispatch(dsp.layout("togglesplit"))
	elseif lay == "scrolling" then
		hl.dispatch(dsp.layout("consume_or_expel prev"))
	elseif lay == "monocle" then
		hl.dispatch(dsp.layout("cyclenext"))
	elseif lay == "master" then
		hl.dispatch(dsp.layout("swapwithmaster"))
	end
end

---------------------------------------------------------------------------
-- Quake console
---------------------------------------------------------------------------
local function windows_on(name)
	local out = {}
	for _, w in ipairs(hl.get_windows() or {}) do
		if w.workspace and w.workspace.name == name then
			out[#out + 1] = w
		end
	end
	return out
end

if K.feature("quake") then
	pcall(hl.window_rule, {
		name = "kuwai-console",
		match = { class = "^(kuwai-console)$" },
		workspace = "special:console",
		float = true,
		size = "monitor_w*0.72 monitor_h*0.5",
		move = "(monitor_w*0.14) 56",
		no_shadow = false,
	})
	pcall(hl.workspace_rule, { workspace = "special:console", gaps_out = 0, animation = "slidevert" })
end

function W.console()
	hl.dispatch(dsp.workspace.toggle_special("console"))
	if #windows_on("special:console") == 0 then
		hl.exec_cmd((K.apps.terminal_raw or "kitty") .. " --class kuwai-console")
	end
end

---------------------------------------------------------------------------
-- Minimize
---------------------------------------------------------------------------
local hidden = {}

function W.minimize()
	local w = hl.get_active_window()
	if not w then
		return
	end
	hidden[#hidden + 1] = w.address
	hl.dispatch(dsp.window.move({ window = "address:" .. w.address, workspace = "special:minimized", follow = false }))
end

function W.restore()
	local present = {}
	for _, w in ipairs(windows_on("special:minimized")) do
		present[w.address] = w
	end
	local target
	while #hidden > 0 and not target do
		target = present[table.remove(hidden)]
	end
	if not target then -- after a reload the stack is gone: newest by focus history
		for _, w in pairs(present) do
			if not target or (w.focus_history_id or 99) < (target.focus_history_id or 99) then
				target = w
			end
		end
	end
	if not target then
		K.notify("Nothing minimized", 1200)
		return
	end
	local ws = hl.get_active_workspace()
	hl.dispatch(dsp.window.move({ window = "address:" .. target.address, workspace = ws and ws.id or 1 }))
	hl.dispatch(dsp.focus({ window = "address:" .. target.address }))
end

_G.kuwai = _G.kuwai or {}
kuwai.workspaces = W
-- A screen goes away (unplugged, lid shut on the second screen…): in desktops
-- mode its windows fold into the same desktop on a remaining screen (desktop
-- 3 stays desktop 3), each remembered; when that screen comes back they go
-- home. Without desktops, Hyprland's own behaviour (its workspaces move over).
local homes = {} -- window address → the workspace id it came from
local function wsid(w)
	local ws = w and w.workspace
	if not ws then
		return nil
	end
	return ws.id or tonumber(tostring(ws):match("%((%-?%d+):"))
end
hl.on("monitor.removed", function()
	if not desktops() then
		return
	end
	hl.timer(function()
		local here = hl.get_active_monitor()
		local base = here and W.base(here) or 0
		for _, w in ipairs(hl.get_windows() or {}) do
			local id = wsid(w)
			if id and id > 0 and (id <= base or id > base + 10) then
				local n = (id - 1) % 10 + 1
				homes[tostring(w.address)] = id
				hl.dispatch(dsp.window.move({ window = "address:" .. tostring(w.address), workspace = base + n, follow = false }))
			end
		end
	end, { timeout = 700, type = "oneshot" })
end)
hl.on("monitor.added", function()
	if not desktops() or next(homes) == nil then
		return
	end
	hl.timer(function()
		for _, w in ipairs(hl.get_windows() or {}) do
			local home = homes[tostring(w.address)]
			if home then
				hl.dispatch(dsp.window.move({ window = "address:" .. tostring(w.address), workspace = home, follow = false }))
			end
		end
		homes = {}
		W.go(W.current())
	end, { timeout = 700, type = "oneshot" })
end)

-- The island speaks in desktops too: a pill click → kuwai.desktop(n).
function kuwai.desktop(n)
	W.go(tonumber(n) or 1)
	return hl.dsp.no_op()
end
-- The island steps the same way the keys do (pills scroll → kuwai.ws_step(±1)).
function kuwai.ws_step(d)
	W.step(d >= 0 and 1 or -1)()
	return hl.dsp.no_op()
end

return W
