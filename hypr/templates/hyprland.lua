-- ~/.config/hypr/hyprland.lua — Hyprland's entry point.
--
-- The desktop itself is kuwai, in the rice repo (KUWAI_ROOT/hypr). This file
-- only finds it. Your own settings go next to this file:
--   monitors.lua   screens (names, modes, scale, VRR, 10-bit)
--   user.lua       apps, launchers, per-app rules, autostart
-- Check everything with `kuwai doctor`; reload with `hyprctl reload`.

-- Where kuwai lives: $KUWAI_ROOT, else the first of these that exists, so the
-- repo can be renamed (rice → kuwai) or moved without breaking login.
do
	local home = os.getenv("HOME") or ""
	local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
	local tries = { home .. "/Projects/kuwai", home .. "/Projects/rice", data .. "/kuwai" }
	-- The channel (`rice channel stable|dev`): stable is a checkout of the
	-- repo's `stable` branch in ~/.local/share/kuwai (moved forward with
	-- `rice promote`), so a half-saved edit in the repo never reaches your
	-- session; dev runs straight from the repo. It wins over $KUWAI_ROOT,
	-- which the live Hyprland keeps from its last load.
	local state = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/kuwai/channel"
	local cf, channel = io.open(state, "r"), nil
	if cf then
		channel = (cf:read("l") or ""):match("^%s*(%a+)")
		cf:close()
	end
	if channel == "stable" then
		tries = { data .. "/kuwai", home .. "/Projects/kuwai", home .. "/Projects/rice" }
	elseif channel ~= "dev" and os.getenv("KUWAI_ROOT") then
		table.insert(tries, 1, os.getenv("KUWAI_ROOT")) -- (a nil in the list would stop ipairs)
	end
	for _, dir in ipairs(tries) do
		local f = io.open(dir .. "/hypr/init.lua", "r")
		if f then
			f:close()
			KUWAI_ROOT = dir
			break
		end
	end
	KUWAI_ROOT = KUWAI_ROOT or (home .. "/Projects/rice")
end
package.path = KUWAI_ROOT .. "/hypr/?.lua;" .. package.path

local ok, err = pcall(dofile, KUWAI_ROOT .. "/hypr/init.lua")

if not ok then
	-- Safety net: kuwai itself failed to load. Keep the session usable —
	-- a terminal, closing windows, workspaces, quitting — and say why.
	local term = "kitty"
	hl.bind("SUPER + T", hl.dsp.exec_cmd(term))
	hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(term))
	hl.bind("SUPER + Q", hl.dsp.window.close())
	hl.bind("SUPER + DELETE", hl.dsp.exit())
	hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
	for i = 1, 9 do
		hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = i }))
	end
	pcall(hl.notification.create, {
		text = "kuwai failed to load (Super+T: terminal): " .. tostring(err),
		timeout = 30000,
		icon = "error",
	})
	print("[kuwai] fatal: " .. tostring(err))
end
