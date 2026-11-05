-- kuwai.startup — what a kuwai session runs once, at login.
-- Personal apps (launchers, trackers, sync) go in user.lua with K.on_start.
--
-- Hyprland 0.57 exports WAYLAND_DISPLAY/HYPRLAND_INSTANCE_SIGNATURE to systemd
-- before graphical-session.target starts, so user units (voxtype, hypridle…)
-- already see the session. The export below adds what kuwai sets on top.

local K = require("kuwai.core")

local EXPORT = table.concat({
	"WAYLAND_DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE", "XDG_SESSION_DESKTOP",
	"HYPRLAND_INSTANCE_SIGNATURE", "QT_QPA_PLATFORMTHEME", "QT_QPA_PLATFORM", "SSH_AUTH_SOCK",
	"XCURSOR_THEME", "XCURSOR_SIZE", "HYPRCURSOR_THEME", "HYPRCURSOR_SIZE", "KUWAI_ROOT", "PATH",
}, " ")

local function unit(name)
	return "systemctl --user start " .. name
end

hl.on("hyprland.start", function()
	hl.exec_cmd("dbus-update-activation-environment --systemd " .. EXPORT)
	hl.exec_cmd("hyprctl setcursor " .. K.cursor.theme .. " " .. K.cursor.size)

	-- Session services (packaged user units: restarted on failure, logged).
	hl.exec_cmd(unit("gcr-ssh-agent.socket"))
	-- Password prompts: kuwai's own (shell-auth/, a separate small process);
	-- its unit falls back to KDE's agent if it can't run.
	local f = os.getenv("HOME") and io.open(os.getenv("HOME") .. "/.config/systemd/user/rice-auth.service", "r")
	if f then
		f:close()
		hl.exec_cmd(unit("rice-auth.service"))
	else
		hl.exec_cmd(unit("plasma-polkit-agent.service"))
	end
	-- Idle (dim, lock, screens off, sleep) is the shell's (services/Idle);
	-- rice-shell starts hypridle only as the fallback when the shell can't run.

	-- The rice: shell (island, HUD, notifications, lock) — it also decides
	-- whether Waybar or the island is the bar (`rice bar apply`).
	hl.exec_cmd(K.bin .. "/rice-shell")
	-- The login screen's copy of the shell and your picture (greeter/sync;
	-- does nothing until greeter/install has run).
	hl.exec_cmd(KUWAI_ROOT .. "/greeter/sync")

	-- Clipboard history (cliphist is the store) and the rice's copy times.
	-- A user service (systemd/rice-clipboard.service): restarted if it dies,
	-- instead of bare watchers that silently stopped history when they did.
	hl.exec_cmd(unit("rice-clipboard.service"))
	-- GitHub and Gmail as notifications (systemd/rice-feeds.service).
	hl.exec_cmd(unit("rice-feeds.service"))

	-- Copies outlive the window they came from. On Wayland the copying app
	-- serves the text at paste time, so closing it (the drop-down terminal is
	-- its own kitty) left Ctrl+V empty. wl-clip-persist takes each copy over.
	if K.has("wl-clip-persist") then
		hl.exec_cmd("wl-clip-persist --clipboard regular")
	end

	-- Wi-Fi secrets agent: the island lists and switches networks but can't
	-- ask a new network's password; nm-applet does (its tray icon is hidden,
	-- TrayRow). udiskie used to run here too (60 MB of Python for a hidden
	-- tray with automount off); the island's device card announces drives
	-- and file managers mount them. KUWAI_UDISKIE=1 brings it back.
	if K.has("nm-applet") then
		hl.exec_cmd("nm-applet --indicator")
	end
	if os.getenv("KUWAI_UDISKIE") == "1" and K.has("udiskie") then
		hl.exec_cmd("udiskie --no-automount --smart-tray")
	end
end)

-- Re-applied on every reload (cheap, idempotent).
hl.exec_cmd("hyprctl setcursor " .. K.cursor.theme .. " " .. K.cursor.size)
