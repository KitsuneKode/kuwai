-- kuwai.voxtype — dictation, wired into the compositor.
--
--   Super+Ctrl+D / Super+Shift+F23 (Copilot key)  toggle, app-aware profile
--   F9 (hold)                                     push-to-talk
--   Super+Shift+D                                 cancel now
--   Esc Esc (while dictating)                     cancel (first press arms)
--   Super+Ctrl+Shift+D                            teach a correction
--
-- Escape used to be a systemd service polling voxtype's state file and
-- (un)binding Escape through `hyprctl keyword`. Now it's one auto-consuming
-- bind: while voxtype is recording/transcribing it cancels, otherwise the
-- press goes to the app untouched — no service, no race, no latency.
--
-- During text output voxtype enters the voxtype_suppress submap (its
-- pre/post_output_command hooks), which swallows modifiers so a held Super or
-- Ctrl can't turn typed text into shortcuts.

local K = require("kuwai.core")

if not K.has("voxtype") and not K.exists(K.home .. "/.local/lib/voxtype-fork/voxtype") then
	return
end

local bind, group = K.bind, K.group
-- The dictation scripts belong to your voxtype setup, not the rice: they live
-- with it (~/Scripts by default; user.lua can set K.voxtype_scripts).
local SCRIPTS = K.voxtype_scripts or (K.home .. "/Scripts/")
local TOGGLE = SCRIPTS .. "voxtype-toggle.sh"
local CANCEL = SCRIPTS .. "voxtype-cancel.sh"
if not K.exists(TOGGLE) then
	return
end
local STATE = K.runtime .. "/voxtype/state"

local function dictating()
	local s = K.read_line(STATE)
	return s == "recording" or s == "streaming" or s == "transcribing"
end

group("Dictation")
bind("SUPER + CTRL + D", "Dictate (again to stop)", TOGGLE)
bind("SUPER + SHIFT + F23", "Dictate (again to stop)", TOGGLE)
bind("SUPER + SHIFT + D", "Cancel dictation", CANCEL .. " now")
bind("SUPER + CTRL + SHIFT + D", "Teach a dictation fix", SCRIPTS .. "voxtype_learn.py fix")
K.bind_hold("F9", "Dictate while held", "voxtype record start", "voxtype record stop")

bind("Escape", "", function()
	if dictating() then
		hl.exec_cmd(CANCEL)
		return
	end
	return { ok = false } -- not ours: hand Escape to the app
end, { auto_consuming = true })

-- Output: swallow modifiers while voxtype types. Escape is deliberately not
-- bound here (it drops wtype's first character, hyprwm/Hyprland#3165).
K.submap("voxtype_suppress", function()
	for _, key in ipairs({ "Super_L", "Super_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Shift_L", "Shift_R" }) do
		bind(key, "", hl.dsp.no_op())
	end
	bind("SUPER + CTRL + D", "", TOGGLE)
	bind("SUPER + SHIFT + F23", "", TOGGLE)
	bind("SUPER + SHIFT + D", "", function()
		hl.exec_cmd(CANCEL .. " now")
		hl.dispatch(hl.dsp.submap("reset"))
	end)
	bind("F12", "", function()
		hl.exec_cmd("voxtype record cancel")
		hl.dispatch(hl.dsp.submap("reset"))
	end)
end)
group(nil)
