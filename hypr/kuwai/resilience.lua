-- kuwai.resilience — what happens when the world changes under you.
--
--   clamshell        lid closed with an external screen: the panel turns off,
--                    nothing locks (logind ignores the lid while docked). Lid
--                    closed with no external screen: lock (logind suspends).
--   hotplug notice   the GPU that renders is chosen at login; plugging the
--                    Acer into an iGPU session (or unplugging it from an
--                    NVIDIA one) says what that costs and how to fix it.
--   battery_guard    ≤10%: one warning. ≤4% and still discharging: the session
--                    is snapshotted and the machine suspends 30 s later unless
--                    you plug in (K.battery.critical_action = "hibernate" if
--                    hibernation is set up on this machine).
--   session_restore  every 5 minutes (and at logout) the open apps and where
--                    they were are saved; at the next login you're offered to
--                    put them back. `kuwai session save|restore`.

local K = require("kuwai.core")

local dsp = hl.dsp
local R = {}

local function internal(m)
	return m and m.name and m.name:match("^eDP") ~= nil
end

local function externals()
	local n = 0
	for _, m in ipairs(hl.get_monitors() or {}) do
		if not internal(m) then
			n = n + 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Lid / clamshell
---------------------------------------------------------------------------
-- The shell's lock (it falls back to hyprlock when the shell is down).
local LOCK = K.bin .. "/rice lock"

if K.feature("clamshell") then
	K.bind("switch:on:Lid Switch", "", function()
		if externals() > 0 and K.panel then
			local spec = {}
			for k, v in pairs(K.panel) do
				spec[k] = v
			end
			spec.disabled = true
			pcall(hl.monitor, spec)
		else
			hl.exec_cmd(LOCK)
		end
	end, { locked = true })
	K.bind("switch:off:Lid Switch", "", function()
		if K.panel then
			pcall(hl.monitor, K.panel)
		end
	end, { locked = true })
else
	K.bind("switch:on:Lid Switch", "", LOCK, { locked = true })
end

---------------------------------------------------------------------------
-- Hotplug: say when the renderer choice no longer fits the screens
---------------------------------------------------------------------------
hl.on("monitor.added", function(m)
	local g = K.gpu or {}
	if internal(m) or not g.nvidia or g.mode ~= "auto" then
		return
	end
	if g.primary == "intel" then
		K.notify(
			(m.description or m.name) .. " is on the NVIDIA GPU, but the Intel GPU is drawing this session: "
				.. "fine for desktop work. Log out and back in for full speed and smooth fullscreen.",
			9000,
			"info"
		)
	end
end)

hl.on("monitor.removed", function()
	local g = K.gpu or {}
	if g.primary == "nvidia" and g.mode == "auto" and externals() == 0 then
		K.notify("Only the laptop screen is left, but NVIDIA is still drawing (more battery). Log out and back in to switch to Intel.", 9000, "info")
	end
end)

---------------------------------------------------------------------------
-- Session snapshot / restore
---------------------------------------------------------------------------
local SNAP = K.state_dir .. "/session"
local SKIP = {
	"^xdg%-desktop%-portal", "polkit", "pinentry", "gcr%-prompter", "^hyprland%-", "^rice%-", "^kuwai%-",
	"^steam_app_", "^gamescope", "xwaylandvideobridge", "^org%.kde%.polkit", "^$",
}

local function skip(cls)
	for _, p in ipairs(SKIP) do
		if cls:find(p) then
			return true
		end
	end
	return false
end

local function cmdline(pid)
	local s = K.read("/proc/" .. tostring(pid) .. "/cmdline")
	if not s or s == "" then
		return nil
	end
	local parts = {}
	for arg in s:gmatch("([^%z]+)") do
		parts[#parts + 1] = K.q(arg)
	end
	return table.concat(parts, " ")
end

function R.save()
	local lines, seen = {}, {}
	for _, w in ipairs(hl.get_windows() or {}) do
		local cls = (w.class or ""):lower()
		local ws = w.workspace
		if not skip(cls) and ws and ws.id and ws.id > 0 and not seen[cls] then
			local cmd = cmdline(w.pid)
			if cmd then
				seen[cls] = true -- one launch per app: browsers/editors restore their own windows
				local at, sz, m = w.at or {}, w.size or {}, w.monitor or {}
				lines[#lines + 1] = table.concat({
					ws.id,
					w.floating and 1 or 0,
					math.floor((at.x or 0) - (m.x or 0)) .. "," .. math.floor((at.y or 0) - (m.y or 0)),
					math.floor(sz.x or 0) .. "," .. math.floor(sz.y or 0),
					cls,
					cmd,
				}, "\t")
			end
		end
	end
	if #lines == 0 then
		return 0
	end
	local f = io.open(SNAP, "w")
	if not f then
		return 0
	end
	f:write("# kuwai session ", os.date("%Y-%m-%d %H:%M"), "\n", table.concat(lines, "\n"), "\n")
	f:close()
	return #lines
end

function R.restore()
	-- The snapshot is a list of commands to run: only trust one that is ours and
	-- not writable by anyone else (the state dir is created 0700 for this).
	-- (os.execute can't see exit codes inside Hyprland, it reaps its children:
	-- read stat's output instead. Rare, user-triggered, so a popen is fine.)
	local h = io.popen("stat -c '%a %u' " .. K.q(SNAP) .. " 2>/dev/null; id -u")
	local out = h and h:read("*a") or ""
	if h then
		h:close()
	end
	local mode, owner, me = out:match("^(%d+) (%d+)%s+(%d+)")
	local m = tonumber(mode or "", 8)
	if not m or owner ~= me or (m % 64) & 18 ~= 0 then -- group/other write bits (0o022)
		K.notify("kuwai: not restoring — " .. SNAP .. " isn't private to you", 4000, "error")
		return "unsafe snapshot"
	end
	local s = K.read(SNAP)
	if not s then
		return "no saved session"
	end
	local running = {}
	for _, w in ipairs(hl.get_windows() or {}) do
		running[(w.class or ""):lower()] = true
	end
	local n = 0
	for line in s:gmatch("[^\n]+") do
		local ws, fl, pos, size, cls, cmd = line:match("^(%-?%d+)\t(%d)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.+)$")
		if ws and not running[cls] then
			local rules = { workspace = ws .. " silent" }
			if fl == "1" then
				local x, y = pos:match("(%-?%d+),(%-?%d+)")
				local w, h = size:match("(%d+),(%d+)")
				rules.float = true
				if w and tonumber(w) > 50 then
					rules.size = w .. " " .. h
				end
				if x then
					rules.move = x .. " " .. y
				end
			end
			hl.exec_cmd(cmd, rules)
			n = n + 1
		end
	end
	K.notify(n > 0 and ("Restoring " .. n .. " apps to their workspaces") or "Everything from the last session is already open", 2500)
	return n
end

_G.kuwai = _G.kuwai or {}
kuwai.session_save = R.save
kuwai.session_restore = R.restore

if K.feature("session_restore") then
	K.defer(function()
		hl.timer(function()
			R.save()
		end, { timeout = 300000, type = "repeat" })
	end)
	hl.on("hyprland.shutdown", function()
		R.save()
	end)
	hl.on("hyprland.start", function()
		-- Offer once the shell (notifications) is up, only if little is open yet.
		hl.timer(function()
			if K.exists(SNAP) and #(hl.get_windows() or {}) <= 2 then
				hl.exec_cmd(K.bin .. "/kuwai session offer")
			end
		end, { timeout = 8000, type = "oneshot" })
	end)
end

---------------------------------------------------------------------------
-- Battery guard
---------------------------------------------------------------------------
K.battery = K.battery or { low = 10, critical = 4, critical_action = "suspend" }

local BAT
for _, b in ipairs({ "BAT0", "BAT1", "BAT2", "CMB0" }) do
	if K.read_line("/sys/class/power_supply/" .. b .. "/capacity") then
		BAT = "/sys/class/power_supply/" .. b
		break
	end
end

if K.feature("battery_guard") and BAT then
	local warned, pending = false, false
	local function check()
		local cap = tonumber(K.read_line(BAT .. "/capacity") or "")
		local discharging = K.read_line(BAT .. "/status") == "Discharging"
		if not cap then
			return
		end
		if not discharging then
			warned, pending = false, false
			return
		end
		if cap <= K.battery.critical and not pending then
			pending = true
			R.save()
			hl.exec_cmd(K.bin .. "/rice-notify -u critical -a kuwai -i battery-empty 'Battery " .. cap .. "% — saving your session' 'Plug in within 30 seconds, or the laptop will " .. K.battery.critical_action .. ".'")
			hl.timer(function()
				pending = false
				if K.read_line(BAT .. "/status") == "Discharging" then
					hl.exec_cmd("systemctl " .. (K.battery.critical_action == "hibernate" and "hibernate" or "suspend"))
				end
			end, { timeout = 30000, type = "oneshot" })
		elseif cap <= K.battery.low and not warned then
			warned = true
			hl.exec_cmd(K.bin .. "/rice-notify -u critical -a kuwai -i battery-caution 'Battery " .. cap .. "%' 'Plug in soon. At " .. K.battery.critical .. "% kuwai saves your session and suspends.'")
		end
	end
	K.defer(function()
		hl.timer(check, { timeout = 60000, type = "repeat" })
		check()
	end)
end

return R
