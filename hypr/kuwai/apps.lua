-- kuwai.apps — default apps for the Launch binds. user.lua overrides any of
-- them (K.apps.terminal = "..."); binds read this table when the key is
-- pressed, so no rebinding is needed.

local K = require("kuwai.core")

local function pick(...)
	for _, c in ipairs({ ... }) do
		local bin = c:match("^(%S+)")
		if bin == "prime-run" then
			bin = c:match("^%S+%s+(%S+)")
		end
		if bin and K.has(bin) then
			return c
		end
	end
	return nil
end

K.apps = {
	terminal = pick("kitty", "ghostty", "foot", "alacritty", "wezterm"),
	terminal_raw = pick("kitty", "ghostty", "foot", "alacritty"), -- for --class variants
	files = pick("dolphin", "nautilus", "thunar", "nemo"),
	editor = pick("zeditor", "code", "codium", "cursor"),
	browser = pick("zen-browser", "firefox", "google-chrome-stable", "chromium", "brave"),
	monitor = (pick("kitty") and "kitty --class kuwai-monitor -e btop") or pick("gnome-system-monitor", "plasma-systemmonitor"),
}

return K.apps
