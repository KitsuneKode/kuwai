local K = require("kuwai.core")

local function unit(name)
	return "systemctl --user start " .. name
end

hl.on("hyprland.start", function()
    print("[kuwai-handoff " .. (os.getenv("KUWAI_HANDOFF_ID") or "unknown") .. "] hyprland-start-hook")
	hl.exec_cmd(K.bin .. "/kuwai-session-env")
	hl.exec_cmd("hyprctl setcursor " .. K.cursor.theme .. " " .. K.cursor.size)

	hl.exec_cmd(unit("gcr-ssh-agent.socket"))
	local f = os.getenv("HOME") and io.open(os.getenv("HOME") .. "/.config/systemd/user/kuwai-auth.service", "r")
	if f then
		f:close()
		hl.exec_cmd(unit("kuwai-auth.service"))
	else
		hl.exec_cmd(unit("plasma-polkit-agent.service"))
	end

	hl.exec_cmd(K.bin .. "/kuwai-shell")
	if not K.hyde then
		hl.exec_cmd(K.bin .. "/kuwai-wall restore")
	end
	hl.exec_cmd(KUWAI_ROOT .. "/greeter/sync")

	hl.exec_cmd(unit("kuwai-clipboard.service"))
	hl.exec_cmd(unit("kuwai-feeds.service"))

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
