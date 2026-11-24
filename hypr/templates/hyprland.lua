do
	local ok, info = pcall(function() return debug.getinfo(1, "S") end)
	KUWAI_USER_DIR = ok and info and type(info.source) == "string" and info.source:match("^@(.+)/[^/]+$") or nil
	local home = os.getenv("HOME") or ""
	local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
	local tries = { home .. "/Projects/kuwai", home .. "/Projects/rice", data .. "/kuwai" }
	local state = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/kuwai/channel"
	local cf, channel = io.open(state, "r"), nil
	if cf then
		channel = (cf:read("l") or ""):match("^%s*(%a+)")
		cf:close()
	end
	if channel == "stable" then
		tries = { data .. "/kuwai", home .. "/Projects/kuwai", home .. "/Projects/rice" }
	elseif channel ~= "dev" and os.getenv("KUWAI_ROOT") then
		table.insert(tries, 1, os.getenv("KUWAI_ROOT"))
	end
	for _, dir in ipairs(tries) do
		local f = io.open(dir .. "/hypr/init.lua", "r")
		if f then
			f:close()
			KUWAI_ROOT = dir
			break
		end
	end
	KUWAI_ROOT = KUWAI_ROOT or (data .. "/kuwai")
end
package.path = KUWAI_ROOT .. "/hypr/?.lua;" .. package.path

local ok, err = pcall(dofile, KUWAI_ROOT .. "/hypr/init.lua")

if not ok then
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
