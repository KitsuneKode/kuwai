package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local handlers = {}
local timers = {}
local cmds = {}

_G.hl = {
	config = function() end,
	on = function(ev, fn)
		handlers[ev] = handlers[ev] or {}
		table.insert(handlers[ev], fn)
	end,
	timer = function(fn, opts)
		table.insert(timers, { fn = fn, opts = opts })
	end,
	exec_cmd = function(cmd)
		table.insert(cmds, cmd)
	end,
}

package.loaded['kuwai.core'] = {
	bin = '/fixture/bin',
	q = function(s)
		return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
	end,
	config = function() end,
	err = function(m) error(m) end,
}

package.loaded['kuwai.theme'] = {
	colors = {},
	load_colors = function() end,
	rgba = function() return nil end,
	apply = function() end,
}

package.loaded['kuwai.look'] = nil
dofile('hypr/kuwai/look.lua')

assert(handlers['monitor.added'] and #handlers['monitor.added'] >= 1, 'look.lua must subscribe to monitor.added')
for _, fn in ipairs(handlers['monitor.added']) do
	fn({ name = 'HDMI-A-1', description = 'Acer XV272U' })
end
assert(#timers == 1, 'restore should wait briefly via hl.timer')
timers[1].fn()
assert(#cmds == 1, 'expected one restore command, got ' .. tostring(#cmds))
assert(cmds[1] == "'/fixture/bin/kuwai-look' restore --output 'HDMI-A-1'", 'unexpected command: ' .. tostring(cmds[1]))
print('ok monitor hotplug wallpaper restore')
