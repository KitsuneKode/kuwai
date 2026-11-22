package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local timers, dispatched, handlers = {}, {}, {}
local windows, active = {}, nil
_G.hl = {
    on = function(ev, fn) handlers[ev] = fn end,
    timer = function(fn, o) timers[#timers + 1] = { fn = fn, t = o.timeout } end,
    dispatch = function(d) dispatched[#dispatched + 1] = d end,
    dsp = { window = {
        resize = function(a) return { op = 'resize', x = a.x, y = a.y } end,
        move = function(a) return { op = 'move', x = a.x, y = a.y } end,
    } },
    get_active_window = function() return active end,
    get_active_monitor = function() return { x = 0, y = 0, width = 2560, height = 1440, scale = 1, reserved = {} } end,
    get_window = function(sel) for _, w in ipairs(windows) do if 'address:' .. w.address == sel then return w end end end,
    get_windows = function() return windows end,
}
local feats = { chat_autoexpand = true }
package.loaded['kuwai.core'] = { feature = function(n) return feats[n] end }
package.loaded['kuwai.actions'] = { usable = function(m) return { x = m.x, y = m.y, w = m.width, h = m.height } end }
local C = dofile('hypr/kuwai/chatwin.lua')
local K = package.loaded['kuwai.core']
local function run() local t = timers; timers = {}; for _, x in ipairs(t) do x.fn() end end
local function last(op) for i = #dispatched, 1, -1 do if dispatched[i].op == op then return dispatched[i] end end end

local u = { x = 0, y = 0, w = 2560, h = 1440 }
local right = { address = '0xa', class = 'com.rtosta.zapzap', floating = true, at = { x = 2160, y = 50 }, size = { x = 380, y = 600 } }
local x, y, w = C.target(right, true, u)
assert(w == 870 and x == 2160 + 380 - 870 and y == 50, 'on the right half it grows to the left, its right edge kept')
local left = { address = '0xb', class = 'com.rtosta.zapzap', floating = true, at = { x = 100, y = 300 }, size = { x = 380, y = 600 } }
x, y = C.target(left, true, u)
assert(x == 100 and y == 300, 'on the left half it grows to the right, where it is')
local low = { address = '0xc', class = 'com.rtosta.zapzap', floating = true, at = { x = 2400, y = 1300 }, size = { x = 380, y = 600 } }
x, y = C.target(low, true, u)
assert(x + 870 <= 2560 and y + 600 <= 1440, 'never off the screen')
K.chat = { anchor = 'corner' }
x, y = C.target(left, true, u)
assert(x == 2560 - 870 - 20 and y == 50, 'corner: back where it was originally, top right')
K.chat = nil

assert(not C.is_chat({ class = 'com.rtosta.zapzap', floating = false }), 'a tiled ZapZap is left alone')
assert(not C.is_chat({ class = 'kitty', floating = true }))

windows = { right, { address = '0xk', class = 'kitty', floating = false } }
active = right
handlers['window.active'](right)
assert(#timers == 1 and timers[1].t == 350, 'it waits a moment before growing (passing by grows nothing)')
active = windows[2]
run()
assert(not last('resize'), 'the pointer went on: it did not grow')
active = right
handlers['window.active'](right)
run()
assert(last('resize').x == 870 and C.big['0xa'], 'stayed: it grew')
active = windows[2]
handlers['window.active'](windows[2])
assert(timers[1].t == 1200, 'leaving: it waits before folding')
run()
assert(last('resize').x == 380 and not C.big['0xa'], 'left: folded back')
feats.chat_autoexpand = false
dispatched = {}
active = right
handlers['window.active'](right)
assert(#timers == 0, 'switched off: nothing happens')
print('test_chatwin: ok')
