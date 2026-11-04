-- The login screen's compositor. greetd runs it as its `greeter` user
-- (greeter/install), from the copy greeter/sync keeps in /var/lib/kuwai-greeter.
-- It only lights the screens and runs one client, the rice's login face
-- (shell/greeter.qml); when that exits (a login went through, or it couldn't
-- start), Hyprland exits too and greetd moves on.
--
-- Hyprland is what brings up the NVIDIA card, so this shows on the Acer as
-- well as the panel (GRUB and SDDM only ever had the panel).

local ROOT = "/var/lib/kuwai-greeter"

local function read_line(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local l = f:read("l")
	f:close()
	return l
end

-- GPUs: every card that drives a screen, NVIDIA first when a screen hangs
-- off it (kuwai.gpu's auto rule, so the handoff to your session is the same).
local nvidia, others = nil, {}
for n = 0, 7 do
	local vendor = read_line("/sys/class/drm/card" .. n .. "/device/vendor")
	if vendor == "0x10de" then
		nvidia = "/dev/dri/card" .. n
	elseif vendor then
		others[#others + 1] = "/dev/dri/card" .. n
	end
end
if nvidia then
	local lit = false
	for _, kind in ipairs({ "DP", "HDMI-A", "eDP" }) do
		for i = 1, 8 do
			if read_line("/sys/class/drm/" .. nvidia:match("card%d+") .. "-" .. kind .. "-" .. i .. "/status") == "connected" then
				lit = true
			end
		end
	end
	if lit then
		table.insert(others, 1, nvidia)
	else
		others[#others + 1] = nvidia
	end
end
if #others > 1 then
	hl.env("AQ_DRM_DEVICES", table.concat(others, ":"))
end

-- The screens, as in ~/.config/hypr/monitors.lua.
hl.monitor({ output = "desc:California Institute of Technology 0x1509", mode = "2560x1440@165", position = "0x360", scale = 4 / 3 })
hl.monitor({ output = "desc:Acer Technologies XV272U X1", mode = "2560x1440@200", position = "1920x0", scale = 1, bitdepth = 8 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
	input = { kb_layout = "us", numlock_by_default = false, repeat_delay = 250, repeat_rate = 35 },
	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		background_color = 0x000000,
		session_lock_xray = false,
	},
	animations = { enabled = false },
	ecosystem = { no_update_news = true, no_donation_nag = true },
})

hl.on("hyprland.start", function()
	hl.exec_cmd(ROOT .. "/start")
end)
