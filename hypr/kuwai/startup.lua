local K = require("kuwai.core")

local function unit(name)
	return "systemctl --user start " .. name
end

hl.on("hyprland.start", function()
    print("[kuwai-handoff " .. (os.getenv("KUWAI_HANDOFF_ID") or "unknown") .. "] hyprland-start-hook")
	hl.exec_cmd("hyprctl setcursor " .. K.cursor.theme .. " " .. K.cursor.size)

	local auth_unit = "plasma-polkit-agent.service"
	local f = os.getenv("HOME") and io.open(os.getenv("HOME") .. "/.config/systemd/user/kuwai-auth.service", "r")
	if f then
		f:close()
		auth_unit = "kuwai-auth.service"
	end
	hl.exec_cmd(
		K.q(K.bin .. "/kuwai-session-env")
			.. "; "
			.. unit("gcr-ssh-agent.socket")
			.. "; "
			.. unit(auth_unit)
			.. "; "
			.. unit("kuwai-wallpaper.service")
			.. "; "
			.. unit("kuwai-clipboard.service")
			.. "; "
			.. unit("kuwai-feeds.service")
	)

	hl.exec_cmd(K.bin .. "/kuwai-look init --no-apply")
	hl.exec_cmd(K.bin .. "/kuwai-shell")
	if not K.hyde then
		hl.exec_cmd(K.bin .. "/kuwai-wall restore")
	end
	hl.exec_cmd(KUWAI_ROOT .. "/greeter/sync")

	if K.has("wl-clip-persist") then
		hl.exec_cmd("wl-clip-persist --clipboard regular")
	end

	if K.has("nm-applet") then
		hl.exec_cmd("nm-applet --indicator")
	end
	if os.getenv("KUWAI_UDISKIE") == "1" and K.has("udiskie") then
		hl.exec_cmd("udiskie --no-automount --smart-tray")
	end
end)

hl.exec_cmd("hyprctl setcursor " .. K.cursor.theme .. " " .. K.cursor.size)
