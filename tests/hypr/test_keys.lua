package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local function stub()
	return setmetatable({}, {
		__index = function(t, k)
			local v = stub()
			rawset(t, k, v)
			return v
		end,
		__call = function()
			return stub()
		end,
	})
end

local live = {}
_G.hl = stub()
rawset(hl, 'bind', function(keys, d, opts)
	local b = { keys = keys, d = d, opts = opts }
	b.remove = function(self)
		live[self] = nil
	end
	live[b] = true
	return b
end)
rawset(hl, 'get_config', function() return nil end)
rawset(hl, 'get_monitors', function() return {} end)
rawset(hl, 'on', function() end)

local dir = os.tmpname()
os.remove(dir)
assert(os.execute('mkdir -p ' .. dir .. '/kuwai'))

local K = require('kuwai.core')
K.config_home = dir
K.state = {}
K.load('kuwai.features')
assert(K.load('kuwai.binds'), 'binds.lua loads: ' .. table.concat(K.errors, '; '))
assert(#K.conflicts == 0, 'no kuwai shortcut replaces another: ' .. table.concat(K.conflicts, '; '))
local M = require('kuwai.keys')

local function bound(keys)
	local want = K.chord(keys)
	local n, who = 0, nil
	for b in pairs(live) do
		if K.chord(b.keys) == want and not (b.opts or {}).release then
			n, who = n + 1, b
		end
	end
	return n, who
end
local function write(lines)
	local f = assert(io.open(dir .. '/kuwai/keys.tsv', 'w'))
	f:write(table.concat(lines, '\n'), '\n')
	f:close()
end
local function entry(text)
	for _, id in ipairs(K.palette_order) do
		if K.palette_index[id].text == text then
			return K.palette_index[id]
		end
	end
end

assert(K.chord('SUPER + SHIFT + ALT + n') == K.chord('ALT + SUPER + SHIFT + N'), 'modifier order does not make another chord')
assert(K.show('SUPER + code:10') == 'SUPER + 1' and K.show('SUPER + code:19') == 'SUPER + 0', 'keycodes 10…19 read as 1…0')
assert(M.valid('SUPER + SHIFT + E') and M.valid('SUPER + code:12') and M.valid(''), 'chords the editor writes are valid')
assert(not M.valid('SUPER + E + SHIFT') and not M.valid('SUPER + $(x)') and not M.valid('SUPER +'), 'anything else is not')
assert(not M.valid('Return') and not M.valid('A') and not M.valid('SHIFT + A') and not M.valid('code:36'), 'a bare key would take typing away')
assert(M.valid('F7') and M.valid('Print') and M.valid('SHIFT + F9'), 'F-keys, Print and Pause may stand alone')

local files = entry('Files')
assert(files and files.aid == 'SUPER+E', 'an action is known by its default chord: ' .. tostring(files and files.aid))
local ws1 = entry('Workspace 1')
assert(ws1.keys == 'SUPER + 1' and ws1.aid == 'SUPER+CODE:10', 'workspace keys stay keycodes, shown as digits')

write({ 'SUPER+E\tSUPER + CTRL + ALT + E\tFiles' })
M.apply()
assert(bound('SUPER + E') == 0, 'the default chord is free once moved')
local n, b = bound('SUPER + CTRL + ALT + E')
assert(n == 1 and b.d == K.bind_spec[files.id].d, 'the new chord runs the same action')
local keys, custom = M.current(files)
assert(keys == 'SUPER + CTRL + ALT + E' and custom, 'the palette shows the new chord as custom')

write({ 'SUPER+CODE:10\tSUPER + CTRL + code:10\tWorkspace 1', 'SUPER+T\tSUPER + E\tTerminal' })
M.apply()
assert(bound('SUPER + CTRL + ALT + E') == 0, 'an override taken out is gone')
n, b = bound('SUPER + E')
assert(n == 1 and b.d == K.bind_spec[entry('Terminal').id].d, 'a chord can go to another action')
assert(bound('SUPER + code:10') == 0 and bound('SUPER + CTRL + code:10') == 1, 'a workspace key moves by keycode')
assert(M.current(ws1) == 'SUPER + CTRL + 1', 'and still reads as its digit')
assert(bound('SUPER + T') == 0, "the moved action's old chord is free")
assert(M.current(files) == '', 'the action whose chord was taken reads as having none')

write({ 'SUPER+E\tSUPER + E\tSomething renamed', 'NOPE+Q\tSUPER + Q\tGhost' })
M.apply()
n, b = bound('SUPER + E')
assert(n == 1 and b.d == K.bind_spec[files.id].d, 'every default comes back when its override goes; a stale line is ignored')
assert(bound('SUPER + T') == 1 and bound('SUPER + code:10') == 1, 'defaults restored')

write({ 'SUPER+E\t\tFiles' })
M.apply()
assert(bound('SUPER + E') == 0 and M.current(files) == '', 'an action can be left without a chord')

K.bind_hold('CTRL + F12', 'Hold to talk', 'true', 'true')
assert(M.fixed(entry('Hold to talk')), 'a hold action is fixed')
write({ 'CTRL+F12\tSUPER + F12\tHold to talk' })
M.apply()
assert(bound('SUPER + F12') == 0 and bound('CTRL + F12') == 1, 'a hold action is not moved apart from its release')

write({ 'SUPER+L\t\tLock' })
M.apply()
assert(bound('SUPER + L') == 1, 'Lock never goes without a chord')

write({})
M.plain_fkeys = nil
assert(not M.plain(), 'F-keys act as kuwai actions by default')
M.apply()
assert(bound('F7') == 1 and bound('F8') == 1 and bound('F10') == 1, 'F7, F8 and F10 are bound by default')
local f = assert(io.open(dir .. '/kuwai/settings.json', 'w'))
f:write('{\n  "clock24": true,\n  "fKeys": "plain"\n}\n')
f:close()
M.plain_fkeys = nil
assert(M.plain(), 'the setting is read from the shell settings')
M.apply()
assert(bound('F7') == 0 and bound('F8') == 0 and bound('F10') == 0, 'plain F-keys leave F7, F8 and F10 to the apps')
assert(M.hidden[K.bind_id('F7')], 'and the palette leaves them out')
assert(bound('XF86MonBrightnessDown') == 1 and bound('SUPER + F7') == 1, 'the media keys and Super+F7 stay')
M.plain_fkeys = false
M.apply()
assert(bound('F7') == 1 and bound('F10') == 1 and not M.hidden[K.bind_id('F7')], 'switching back binds them again')

os.execute('rm -rf ' .. dir)
print('keys fixtures pass')
