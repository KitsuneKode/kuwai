local K = require("kuwai.core")

local function unit(name)
	return "systemctl --user start " .. name
end

hl.on("hyprland.start", function()
    print("[kuwai-handoff " .. (os.getenv("KUWAI_HANDOFF_ID") or "unknown") .. "] hyprland-start-hook")

	local home = os.getenv("HOME") or ""
	local xdg = os.getenv("XDG_CONFIG_HOME") or (home ~= "" and (home .. "/.config") or "")
	local auth_unit = "plasma-polkit-agent.service"
	if home ~= "" and K.exists(home .. "/.config/systemd/user/kuwai-auth.service") then
		auth_unit = "kuwai-auth.service"
	end
	local units = {
		K.q(K.bin .. "/kuwai-session-env"),
		unit("gcr-ssh-agent.socket"),
		unit(auth_unit),
		unit("kuwai-wallpaper.service"),
		unit("kuwai-clipboard.service"),
	}
	if os.getenv("KUWAI_FEEDS") == "1" or (xdg ~= "" and (K.exists(xdg .. "/kuwai/feeds.json") or K.exists(xdg .. "/gh/hosts.yml"))) then
		units[#units + 1] = unit("kuwai-feeds.service")
	end
	hl.exec_cmd(table.concat(units, "; "))

	hl.exec_cmd(K.bin .. "/kuwai-look init --no-apply")
	hl.exec_cmd(K.bin .. "/kuwai-shell")
	if not K.hyde then
		hl.exec_cmd(K.bin .. "/kuwai-wall restore")
	end
	hl.exec_cmd(KUWAI_ROOT .. "/greeter/sync")

	if K.has("wl-clip-persist") then
		hl.exec_cmd("wl-clip-persist --clipboard regular")
	end

	if os.getenv("KUWAI_NM_APPLET") == "1" and K.has("nm-applet") then
		hl.exec_cmd("nm-applet --indicator")
	end
	if os.getenv("KUWAI_UDISKIE") == "1" and K.has("udiskie") then
		hl.exec_cmd("udiskie --no-automount --smart-tray")
	end
end)

hl.exec_cmd("hyprctl setcursor " .. K.cursor.theme .. " " .. K.cursor.size)
