package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path
local function stub()
	return setmetatable({}, { __index = function(t, k) local v = stub(); rawset(t, k, v); return v end, __call = function() return stub() end })
end
_G.hl = stub()
local dir = os.tmpname()
os.remove(dir)
assert(os.execute('mkdir -p ' .. dir))
local K = require('kuwai.core')
K.state_dir = dir
K.feature = function() return false end
local procs = {
	[11] = 'kitty\0--title\0work\0',
	[12] = 'evil\0--x\0a\tb\0',
	[13] = 'zen\0https://example.com\0',
}
local real_read = K.read
K.read = function(path)
	local pid = path:match('^/proc/(%d+)/cmdline$')
	if pid then return procs[tonumber(pid)] end
	return real_read(path)
end
local wins = {
	{ class = 'kitty', pid = 11, workspace = { id = 1 }, at = { x = 0, y = 0 }, size = { x = 10, y = 10 }, monitor = { x = 0, y = 0 } },
	{ class = 'evil', pid = 12, workspace = { id = 2 }, at = {}, size = {}, monitor = {} },
	{ class = 'zen\tsh -c id', pid = 13, workspace = { id = 3 }, at = {}, size = {}, monitor = {} },
}
rawset(hl, 'get_windows', function() return wins end)
local R = require('kuwai.resilience')
local n = R.save()
local s = real_read(dir .. '/session') or ''
assert(n == 1, 'only the plain record is kept, got ' .. tostring(n))
assert(s:find("'kitty' '%-%-title' 'work'"), 'its command stays quoted argv')
assert(not s:find('evil') and not s:find('sh %-c id'), 'a tab in an argument or a class never reaches a record')
os.execute('rm -rf ' .. dir)
print('session record fixtures pass')
