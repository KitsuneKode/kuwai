-- kuwai.binds — the core keyboard. Personal app launchers live in user.lua.
--
-- Super is the main modifier. Groups (the [..] in each description) are what
-- the rice's Shortcuts panel (Super+/) shows as sections.
--
-- Apps are looked up when the key is pressed (K.apps.<name>), so user.lua can
-- change the terminal/browser/editor without rebinding anything.

local K = require("kuwai.core")
local A = require("kuwai.actions")
local W = require("kuwai.workspaces")

local bind, group = K.bind, K.group
local dsp = hl.dsp
local S = "SUPER"

local function rice(name)
	return dsp.global("rice:" .. name)
end

local function app(name)
	return function()
		local cmd = K.apps[name]
		if cmd and cmd ~= "" then
			hl.exec_cmd(cmd)
		end
	end
end

local RICE = K.bin

---------------------------------------------------------------------------
group("Windows")
---------------------------------------------------------------------------
bind(S .. " + Q", "Close window", A.close)
bind("ALT + F4", "Close window", A.close)
bind(S .. " + W", "Float / tile", A.float_toggle, { locked = true })
bind(S .. " + F", "Fullscreen", dsp.window.fullscreen({ mode = "fullscreen" }), { locked = true })
bind(S .. " + F11", "Fullscreen", dsp.window.fullscreen({ mode = "fullscreen" }), { locked = true })
bind(S .. " + SHIFT + F", "Maximize (bar and gaps stay)", dsp.window.fullscreen({ mode = "maximized" }), { locked = true })
bind(S .. " + CTRL + F", "Pin on every workspace", A.pin_toggle, { locked = true })
bind(S .. " + G", "Group (tabs)", dsp.group.toggle(), { locked = true })
-- [ and ] mean previous/next everywhere: the tab in a group, the window in
-- monocle, the column on the scrolling tape, else the next window.
bind(S .. " + bracketleft", "Previous (tab / window / column)", W.next(false))
bind(S .. " + bracketright", "Next (tab / window / column)", W.next(true))
bind(S .. " + J", "Rearrange (split / column / next)", W.arrange, { locked = true })
bind(S .. " + Escape", "Jump to the window that needs you, or back", dsp.focus({ urgent_or_last = true }))
bind(S .. " + CTRL + K", "Click a window to kill it", "hyprctl kill")
bind(S .. " + DELETE", "Quit Hyprland", A.exit)
bind(S .. " + L", "Lock", "pidof hypridle >/dev/null && loginctl lock-session || rice lock")

group("Windows|Focus")
bind(S .. " + left", "Focus left", dsp.focus({ direction = "left" }))
bind(S .. " + right", "Focus right", dsp.focus({ direction = "right" }))
bind(S .. " + up", "Focus up", dsp.focus({ direction = "up" }))
bind(S .. " + down", "Focus down", dsp.focus({ direction = "down" }))

-- Alt+Tab: the island's switcher (hold Alt, tap Tab, let go to switch; a
-- quick flick switches with no UI). Alt coming up is caught in
-- kuwai.automation and sent as rice:switch-commit. Feature off: snappy-switcher.
if K.feature("island_switcher") then
	local function sw(which)
		return function()
			K.alt_switch = true
			hl.dispatch(dsp.global("rice:switch-" .. which))
		end
	end
	bind("ALT + Tab", "Switch windows (hold Alt)", sw("next"))
	bind("ALT + SHIFT + Tab", "Switch windows (back)", sw("prev"))
	bind("ALT + grave", "Switch between this app's windows", sw("app"))
	bind("ALT + SHIFT + grave", "Switch between this app's windows (back)", sw("prev"))
	-- snappy-switcher's --workspace: only the windows on this workspace
	-- (hold Super+Alt, tap Tab; letting go of Alt switches).
	bind(S .. " + ALT + Tab", "Switch between this workspace's windows", sw("ws"))
elseif K.has("snappy-switcher") then
	bind("ALT + Tab", "Switch windows", "snappy-switcher next --mod alt")
	bind("ALT + SHIFT + Tab", "Switch windows (back)", "snappy-switcher prev --mod alt")
else
	bind("ALT + Tab", "Switch windows", function()
		hl.dispatch(dsp.window.cycle_next())
		hl.dispatch(dsp.window.alter_zorder({ mode = "top" }))
	end)
end
if K.feature("overview") then
	bind(S .. " + Tab", "Mission Control: every workspace and window", rice("overview"))
	bind(S .. " + ALT + I", "Show the island's details (minimal island)", rice("island-peek"))
	bind(S .. " + SHIFT + C", "Caffeine: keep awake (no dim, lock or sleep)", rice("caffeine"))
else
	bind(S .. " + Tab", "Previous workspace", dsp.focus({ workspace = "previous_per_monitor" }))
end
bind(S .. " + SHIFT + Tab", "Previous workspace", dsp.focus({ workspace = "previous_per_monitor" }))

-- Arrows, one grammar: plain = look · Shift = carry the window · Ctrl = size
-- · Alt = workspaces · Ctrl+Alt = screens. (Ctrl+Alt alone = columns.)
local rep = { repeating = true }
group("Windows|Move")
bind(S .. " + SHIFT + left", "Move window left", A.move("left", -30, 0), rep)
bind(S .. " + SHIFT + right", "Move window right", A.move("right", 30, 0), rep)
bind(S .. " + SHIFT + up", "Move window up", A.move("up", 0, -30), rep)
bind(S .. " + SHIFT + down", "Move window down", A.move("down", 0, 30), rep)

group("Windows|Resize")
-- (Super+Ctrl+arrows are workspaces now, the Windows/GNOME habit.)
bind(S .. " + ALT + right", "Wider", dsp.window.resize({ x = 30, y = 0, relative = true }), rep)
bind(S .. " + ALT + left", "Narrower", dsp.window.resize({ x = -30, y = 0, relative = true }), rep)
bind(S .. " + ALT + up", "Shorter", dsp.window.resize({ x = 0, y = -30, relative = true }), rep)
bind(S .. " + ALT + down", "Taller", dsp.window.resize({ x = 0, y = 30, relative = true }), rep)

group("Windows|Move")
bind(S .. " + mouse:272", "Drag to move", dsp.window.drag(), { mouse = true })
bind(S .. " + mouse:273", "Drag to resize", dsp.window.resize(), { mouse = true })
bind(S .. " + Z", "Hold to move", dsp.window.drag(), { mouse = true })
bind(S .. " + X", "Hold to resize", dsp.window.resize(), { mouse = true })

group("Screens")
bind("CTRL + ALT + Tab", "Next screen", A.focus_screen(1))
bind("CTRL + ALT + SHIFT + Tab", "Previous screen", A.focus_screen(-1))
bind(S .. " + CTRL + ALT + left", "Window to the screen on the left", dsp.window.move({ monitor = "left" }))
bind(S .. " + CTRL + ALT + right", "Window to the screen on the right", dsp.window.move({ monitor = "right" }))
bind(S .. " + CTRL + ALT + SHIFT + left", "This workspace's windows to the screen on the left", W.windows_to_screen(-1))
bind(S .. " + CTRL + ALT + SHIFT + right", "This workspace's windows to the screen on the right", W.windows_to_screen(1))

---------------------------------------------------------------------------
group("Columns")
---------------------------------------------------------------------------
-- The scrolling tape: Ctrl+Alt is the column modifier.
bind("CTRL + ALT + mouse_up", "Scroll the tape right", dsp.layout("move +col"))
bind("CTRL + ALT + mouse_down", "Scroll the tape left", dsp.layout("move -col"))
bind("CTRL + ALT + left", "Focus column left", dsp.layout("focus l"))
bind("CTRL + ALT + right", "Focus column right", dsp.layout("focus r"))
bind("CTRL + ALT + up", "Focus up in column", dsp.layout("focus u"))
bind("CTRL + ALT + down", "Focus down in column", dsp.layout("focus d"))
bind("CTRL + ALT + equal", "Wider column", dsp.layout("colresize +0.1"), rep)
bind("CTRL + ALT + minus", "Narrower column", dsp.layout("colresize -0.1"), rep)
bind("CTRL + ALT + C", "Next preset width", dsp.layout("colresize +conf"))
bind("CTRL + ALT + X", "Previous preset width", dsp.layout("colresize -conf"))
bind("CTRL + ALT + P", "Window to its own column", dsp.layout("promote"))
bind("CTRL + ALT + S", "Swap column right", dsp.layout("swapcol r"))
bind("CTRL + ALT + A", "Swap column left", dsp.layout("swapcol l"))
bind("CTRL + ALT + F", "Fit column", dsp.layout("fit active"))
bind("CTRL + ALT + E", "Fit all visible", dsp.layout("fit visible"))
bind("CTRL + ALT + Return", "Centre column", dsp.layout("center"))
if K.exists(K.home .. "/Scripts/tile-two.sh") then
	bind(S .. " + ALT + F", "Tile two side by side", K.home .. "/Scripts/tile-two.sh r")
	bind(S .. " + ALT + SHIFT + F", "Tile two (left)", K.home .. "/Scripts/tile-two.sh l")
end

---------------------------------------------------------------------------
group("Workspaces")
---------------------------------------------------------------------------
-- 1–10 are the focused screen's own (kuwai.workspaces; global when
-- per_monitor_ws is off). Next/previous stay on this screen.
for i = 1, 10 do
	local key = tostring(i % 10)
	bind(S .. " + " .. key, "Workspace " .. i, W.focus(i))
	bind(S .. " + SHIFT + " .. key, "Move window to workspace " .. i, W.send(i, true))
	bind(S .. " + ALT + " .. key, "Send window to workspace " .. i .. " (stay)", W.send(i, false))
end
-- Super+Ctrl+← → steps through this screen's workspaces (Windows/GNOME
-- muscle memory); ↑ Mission Control (macOS's Ctrl+↑); ↓ an empty one.
bind(S .. " + CTRL + right", "Next workspace", W.step(1))
bind(S .. " + CTRL + left", "Previous workspace", W.step(-1))
bind(S .. " + CTRL + down", "First empty workspace on this screen", W.empty())
bind(S .. " + CTRL + up", "Mission Control", function() hl.dispatch(dsp.global("rice:overview")) end)
bind(S .. " + ALT + SHIFT + L", "Next busy workspace", W.busy(1))
bind(S .. " + ALT + SHIFT + H", "Previous busy workspace", W.busy(-1))
bind(S .. " + mouse_down", "Next busy workspace", W.busy(1))
bind(S .. " + mouse_up", "Previous busy workspace", W.busy(-1))
bind(S .. " + CTRL + SHIFT + right", "Carry window to the next workspace", W.step(1, true))
bind(S .. " + CTRL + SHIFT + left", "Carry window to the previous workspace", W.step(-1, true))
if K.feature("layouts") then
	bind(S .. " + ALT + L", "Cycle layout: scrolling, dwindle, monocle, floating", W.layout_next(1))
end

group("Workspaces|Scratchpad")
bind(S .. " + S", "Scratchpad", dsp.workspace.toggle_special("special"), { locked = true })
bind(S .. " + SHIFT + S", "Move window to scratchpad", dsp.window.move({ workspace = "special:special" }))
bind(S .. " + ALT + S", "Send window to scratchpad (stay)", dsp.window.move({ workspace = "special:special", follow = false }))
if K.feature("quake") then
	bind(S .. " + grave", "Drop-down console", W.console)
	bind(S .. " + SHIFT + grave", "Move window to the console", dsp.window.move({ workspace = "special:console" }))
end
if K.feature("minimize") then
	bind(S .. " + O", "Minimize window", W.minimize)
	bind(S .. " + SHIFT + O", "Bring back the last minimized", W.restore)
end

---------------------------------------------------------------------------
group("Launch")
---------------------------------------------------------------------------
bind(S .. " + T", "Terminal", app("terminal"))
bind(S .. " + RETURN", "Terminal", app("terminal"))
bind(S .. " + SHIFT + RETURN", "Terminal here (focused terminal's folder)", function()
	local w = hl.get_active_window()
	hl.exec_cmd(K.bin .. "/kuwai-term" .. (w and w.pid and (" " .. w.pid) or ""))
end)
-- Agents where you are: Claude / Codex in the focused terminal's folder, as a
-- kittymux tab when you're in kitty (bin/kuwai-agent).
local function agent(name)
	return function()
		local w = hl.get_active_window()
		hl.exec_cmd(K.bin .. "/kuwai-agent " .. name .. (w and w.pid and (" " .. w.pid) or ""))
	end
end
bind(S .. " + ALT + RETURN", "Claude here (kittymux tab in this folder)", agent("claude"))
bind(S .. " + ALT + SHIFT + RETURN", "Codex here (kittymux tab in this folder)", agent("codex"))
bind(S .. " + E", "Files", app("files"))
bind(S .. " + C", "Editor", app("editor"))
bind(S .. " + SHIFT + B", "Browser", app("browser"))
bind(S .. " + SHIFT + Escape", "System monitor", app("monitor"))
bind(S .. " + CTRL + T", "Drop-down terminal", function()
	hl.exec_cmd((K.apps.terminal_raw or "kitty") .. " --class drop-term")
end)
bind(S .. " + ALT + T", "Floating terminal", function()
	hl.exec_cmd((K.apps.terminal_raw or "kitty") .. " --class float-term")
end)

---------------------------------------------------------------------------
group("Shell")
---------------------------------------------------------------------------
-- Global shortcuts go straight into the running Quickshell (GlobalShortcut in
-- shell/modules/Shortcuts.qml): no process per keypress, same-frame response.
bind(S .. " + A", "Launcher", rice("launcher"))
bind(S .. " + CTRL + SHIFT + A", "AI Assistant", rice("assistant"))
bind(S .. " + N", "Notifications", rice("center"))
bind(S .. " + SHIFT + N", "Agents (kittymux)", rice("agents"))
bind(S .. " + ALT + N", "Do not disturb", rice("dnd"))
bind(S .. " + SHIFT + ALT + N", "Open the newest notification", rice("open-latest"))
bind(S .. " + CTRL + J", "Quick note (jot)", rice("note"))
bind(S .. " + CTRL + SHIFT + J", "Remind me", rice("remind"))
bind(S .. " + V", "Clipboard", rice("clipboard"))
bind(S .. " + SHIFT + V", "Clipboard pins", rice("clipboard-pins"))
bind(S .. " + ALT + V", "Clipboard pins", rice("clipboard-pins"))
bind(S .. " + BACKSPACE", "Power menu", rice("power"))
bind(S .. " + ALT + C", "Calendar", rice("calendar"))
bind(S .. " + CTRL + I", "Settings", rice("settings"))
bind(S .. " + SHIFT + T", "Themes", rice("themes"))
bind(S .. " + SHIFT + W", "Wallpapers", rice("wallpapers"))
bind(S .. " + slash", "Keyboard shortcuts", rice("keys"))
bind(S .. " + SHIFT + slash", "Desktop mode (focus, glass, gaming…)", RICE .. "/kuwai mode --pick")
bind(S .. " + ALT + G", "Game mode on/off", function()
	kuwai.mode_toggle("gaming")
end)

---------------------------------------------------------------------------
group("Capture")
---------------------------------------------------------------------------
local shot = RICE .. "/rice-shot "
bind(S .. " + P", "Screenshot a region and annotate", shot .. "area")
bind(S .. " + ALT + P", "Screenshot a region (no editor)", shot .. "quick")
bind(S .. " + CTRL + P", "Freeze, then screenshot a region", shot .. "freeze")
bind(S .. " + CTRL + ALT + P", "Screenshot the window you're in", shot .. "window")
bind(S .. " + SHIFT + ALT + P", "Copy the text in a region (OCR)", shot .. "ocr")
bind(S .. " + CTRL + SHIFT + P", "Screenshot this monitor", shot .. "monitor", { locked = true })
bind("Print", "Screenshot every monitor", shot .. "all", { locked = true })
bind("SHIFT + Print", "Screenshot this monitor in 3 seconds", shot .. "delay")
bind(S .. " + SHIFT + P", "Pick a colour", "hyprpicker -an")
bind(S .. " + SHIFT + ALT + R", "Screen recording: set up or stop", rice("record"))
bind(S .. " + CTRL + ALT + R", "Record a region (again to stop)", RICE .. "/rice-rec toggle region")

---------------------------------------------------------------------------
group("Hardware|Audio")
---------------------------------------------------------------------------
-- The glass HUD shows every change (it watches PipeWire), so these stay plain.
local VOL = "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "
local lr = { locked = true, repeating = true }
local l = { locked = true }
bind("XF86AudioRaiseVolume", "Volume up", VOL .. "5%+", lr)
bind("XF86AudioLowerVolume", "Volume down", VOL .. "5%-", lr)
bind("XF86AudioMute", "Mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", l)
bind("F10", "Mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", l)
bind("XF86AudioMicMute", "Microphone on/off", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", l)
bind("CTRL + ALT + M", "Microphone on/off", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", l)

group("Hardware|Media")
bind("XF86AudioPlay", "Play / pause", "playerctl play-pause", l)
bind("XF86AudioPause", "Play / pause", "playerctl play-pause", l)
bind("XF86AudioNext", "Next track", "playerctl next", l)
bind("XF86AudioPrev", "Previous track", "playerctl previous", l)
bind(S .. " + F6", "Previous track", "playerctl previous", l)
bind(S .. " + F7", "Play / pause", "playerctl play-pause", l)
bind(S .. " + F8", "Next track", "playerctl next", l)

group("Hardware|Brightness")
-- ~/Scripts/brightness.sh routes to the screen under focus (DDC for the
-- external) and feeds the HUD; plain brightnessctl otherwise.
local BR = K.exists(K.home .. "/Scripts/brightness.sh") and (K.home .. "/Scripts/brightness.sh ") or nil
bind("XF86MonBrightnessUp", "Brighter", BR and (BR .. "i") or "brightnessctl -e4 -n2 set 5%+", lr)
bind("XF86MonBrightnessDown", "Dimmer", BR and (BR .. "d") or "brightnessctl -e4 -n2 set 5%-", lr)
if BR then
	bind("F8", "Brighter", BR .. "i", lr)
	bind("F7", "Dimmer", BR .. "d", lr)
	bind(S .. " + ALT + F7", "Brightness: this screen / all", BR .. "toggle")
end

group("Hardware")
if tostring(K.get("input.kb_layout") or ""):find(",") then -- only with 2+ layouts
	bind(S .. " + K", "Next keyboard layout", "hyprctl switchxkblayout all next")
end
-- Lid: kuwai.resilience (clamshell with an external screen, lock otherwise).

---------------------------------------------------------------------------
group("Zoom")
---------------------------------------------------------------------------
bind("ALT + SHIFT + mouse_down", "Zoom in at the cursor", A.zoom(1.15))
bind("ALT + SHIFT + mouse_up", "Zoom out", A.zoom(1 / 1.15))
bind("ALT + SHIFT + mouse:274", "Reset zoom", A.zoom(0))
bind(S .. " + ALT + equal", "Zoom in at the cursor", A.zoom(1.25), rep)
bind(S .. " + ALT + minus", "Zoom out", A.zoom(0.8), rep)

group(nil)
