local K = require("kuwai.core")

if not K.has("voxtype") and not K.exists(K.home .. "/.local/lib/voxtype-fork/voxtype") then
	return
end

local bind, group = K.bind, K.group
local SCRIPTS = K.voxtype_scripts
	or (K.exists(K.home .. "/.local/share/shuush/libexec/voxtype-toggle.sh") and (K.home .. "/.local/share/shuush/libexec/"))
	or (K.home .. "/Scripts/")
local TOGGLE = SCRIPTS .. "voxtype-toggle.sh"
local CANCEL = SCRIPTS .. "voxtype-cancel.sh"
if not K.exists(TOGGLE) then
	return
end
local STATE = K.runtime .. "/voxtype/state"
local KEYS = K.runtime .. "/kuwai/keys"

local function dictating()
	local s = K.read_line(STATE)
	return s == "recording" or s == "streaming" or s == "transcribing"
end

group("Dictation")
bind("SUPER + CTRL + D", "Dictate (again to stop)", TOGGLE)
bind("SUPER + SHIFT + F23", "Dictate (again to stop)", TOGGLE)
bind("SUPER + SHIFT + D", "Cancel dictation", CANCEL .. " now")
bind("SUPER + CTRL + ALT + D", "Bring back the cancelled dictation",
	"sh -c 'voxtype record recover 2>/dev/null || \"$1\" -a Dictation \"Nothing to bring back\" \"A cancelled take is kept for 10 minutes when it held 2 seconds of speech\"' sh "
		.. K.bin .. "/kuwai-notify")
bind("SUPER + CTRL + SHIFT + D", "Teach a dictation fix", SCRIPTS .. "voxtype_learn.py fix")
if K.exists(SCRIPTS .. "voxtype-studio.py") then
	bind("SUPER + ALT + D", "Voxtype Studio (history, corrections, vocabulary, snippets)", SCRIPTS .. "voxtype-studio.py")
end
K.bind_hold("F9", "Dictate while held (tap: hands-free)", TOGGLE .. " hold", TOGGLE .. " release")
bind("SUPER + CTRL + E", "Edit the selection by voice", TOGGLE .. " command")

bind("Escape", "", function()
	if K.read_line(KEYS) == "panel" then
		return { ok = false }
	end
	if dictating() then
		hl.exec_cmd(CANCEL)
		return
	end
	return { ok = false }
end, { auto_consuming = true })

K.submap("voxtype_suppress", function()
	for _, key in ipairs({ "Super_L", "Super_R", "Control_L", "Control_R", "Alt_L", "Alt_R", "Shift_L", "Shift_R" }) do
		bind(key, "", hl.dsp.no_op())
	end
	bind("SUPER + CTRL + D", "", TOGGLE)
	bind("SUPER + SHIFT + F23", "", TOGGLE)
	bind("SUPER + CTRL + E", "", TOGGLE .. " command")
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
