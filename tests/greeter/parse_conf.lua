-- lua tests/greeter/parse_conf.lua FILE: what greeter/hyprland.lua makes of
-- a kuwai-greeter.conf, one line per hl.monitor and the keyboard, for
-- tests/greeter/test_sync.py (sync's output must be what the greeter takes).
local file = assert(arg[1], "usage: parse_conf.lua FILE")
local CONF = "/var/lib/kuwai-greeter/home/.config/kuwai-greeter.conf"
local real_open = io.open
io.open = function(path, mode) return real_open(path == CONF and file or path, mode) end
local out = {}
_G.hl = {
	monitor = function(m)
		out[#out + 1] = string.format("monitor %s|%s|%s|%s|%s|%s|%s", m.output, m.mode, m.position, tostring(m.scale),
			tostring(m.transform or ""), tostring(m.bitdepth or ""), tostring(m.cm or ""))
	end,
	config = function(c)
		out[#out + 1] = string.format("keyboard %s|%s|%s", c.input.kb_layout, c.input.kb_variant, c.input.kb_options)
	end,
	env = function() end, on = function() end, bind = function() end, exec_cmd = function() end,
	dsp = { exec_cmd = function() return {} end },
}
dofile("greeter/hyprland.lua")
print(table.concat(out, "\n"))
