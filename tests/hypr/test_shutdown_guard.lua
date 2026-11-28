package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local function clear_modules()
    for k in pairs(package.loaded) do
        if k:match('^kuwai') then package.loaded[k] = nil end
    end
    _G.kuwai = nil
    _G.__kuwai_raw_monitor = nil
end

local core_handlers = {}
_G.hl = {
    on = function(ev, fn) core_handlers[ev] = fn end,
    get_monitors = function() return {} end,
}
clear_modules()
local real_core = require('kuwai.core')
assert(real_core.shutting_down == false, 'shutdown flag starts off')
core_handlers['hyprland.shutdown']()
assert(real_core.shutting_down == true, 'hyprland.shutdown sets the shared flag')

local function base_core(feature)
    local K = {
        state = {},
        home = '/nonexistent',
        bin = '/nonexistent/bin',
        config_home = '/nonexistent',
        night_off = 'true',
        colour_apps = {},
        shutting_down = false,
    }
    function K.feature(n) return feature[n] == true end
    function K.set_state(k, v) K.state[k] = v ~= nil and tostring(v) or nil end
    function K.config() end
    function K.notify() end
    function K.err(m) error(m) end
    function K.exists() return false end
    function K.read_line() return nil end
    function K.defer() end
    function K.group() end
    function K.bind() end
    function K.ac_online() return true end
    return K
end

local function reset(K, extra_hl)
    clear_modules()
    package.loaded['kuwai.core'] = K
    local handlers, timers, dispatched = {}, {}, {}
    local h = {
        on = function(ev, fn) handlers[ev] = fn end,
        timer = function(fn, o) local t = { fn = fn, timeout = o and o.timeout }; timers[#timers + 1] = t; return t end,
        dispatch = function(d) dispatched[#dispatched + 1] = d end,
        exec_cmd = function() end,
        window_rule = function() return { set_enabled = function() end, is_enabled = function() return true end } end,
        layer_rule = function() return { set_enabled = function() end } end,
        monitor = function() end,
        get_monitors = function() return {} end,
        get_windows = function() return {} end,
        get_active_window = function() return nil end,
        get_window = function() return nil end,
        dsp = {
            reload_config = function() return 'reload' end,
            no_op = function() return 'noop' end,
            window = {
                resize = function(a) return { op = 'resize', a = a } end,
                move = function(a) return { op = 'move', a = a } end,
                float = function(a) return { op = 'float', a = a } end,
                tag = function(a) return { op = 'tag', a = a } end,
            },
        },
    }
    for k, v in pairs(extra_hl or {}) do h[k] = v end
    _G.hl = h
    _G.kuwai = {}
    return handlers, timers, dispatched
end

clear_modules()
local K = base_core({ auto_display = true })
package.loaded['kuwai.core'] = K
local dp = { name = 'DP-1', width = 1920, height = 1080, available_modes = { { width = 1920, height = 1080, refresh_rate = 120 } } }
local handlers, dtimers = reset(K, {
    get_monitors = function() return { dp } end,
})
package.loaded['kuwai.core'] = K
local D = require('kuwai.display')
assert(type(D) == 'table', 'display fake loads')
hl.get_windows = function() error('windows touched during shutdown') end
hl.get_active_window = function() error('active window touched during shutdown') end
local armed = #dtimers
handlers['window.destroy']({ address = '0xs', class = 'kitty' })
handlers['window.destroy']({ address = '0xt', class = 'mpv' })
assert(#dtimers == armed + 1, 'a destroy before the flag is set (SIGTERM never sends hyprland.shutdown) only arms one timer')
local walked = 0
hl.get_windows = function() walked = walked + 1; return {} end
hl.get_active_window = function() return nil end
dtimers[#dtimers].fn()
assert(walked > 0, 'the deferred reconcile runs once the event loop is still going')
hl.get_windows = function() error('windows touched during shutdown') end
hl.get_active_window = function() error('active window touched during shutdown') end
handlers['window.destroy'](nil)
K.shutting_down = true
handlers['window.destroy']({ address = '0xd', class = 'kitty' })
D.reconcile({ address = '0xd', class = 'kitty' })

clear_modules()
K = base_core({ chat_autoexpand = true })
package.loaded['kuwai.actions'] = { usable = function(m) return { x = 0, y = 0, w = 1920, h = 1080 } end }
handlers = reset(K, {
    get_active_monitor = function() return { x = 0, y = 0, width = 1920, height = 1080, scale = 1, reserved = {} } end,
})
package.loaded['kuwai.core'] = K
package.loaded['kuwai.actions'] = { usable = function(m) return { x = 0, y = 0, w = 1920, h = 1080 } end }
local C = dofile('hypr/kuwai/chatwin.lua')
C.big['0xc'] = true
K.shutting_down = true
handlers['window.destroy']({ address = '0xc' })
assert(C.big['0xc'] == true, 'chat destroy is a shutdown no-op')

clear_modules()
K = base_core({ auto_game = true })
local dispatched
handlers, timers, dispatched = reset(K)
package.loaded['kuwai.core'] = K
dofile('hypr/kuwai/automation.lua')
local game = { address = '0xg', class = 'cs2', fullscreen = 1 }
handlers['window.fullscreen'](game)
local before = #dispatched
hl.get_windows = function() error('windows touched during shutdown') end
local armed_game = #timers
handlers['window.destroy'](game)
assert(#timers == armed_game + 1 and #dispatched == before, 'a destroy while gaming defers the window walk to a timer')
K.shutting_down = true
handlers['window.destroy'](game)
assert(#timers == armed_game + 1 and #dispatched == before, 'automation destroy is a shutdown no-op')

clear_modules()
K = base_core({ remember_place = true })
handlers = reset(K)
package.loaded['kuwai.core'] = K
dofile('hypr/kuwai/extras.lua')
local floating = { floating = true, class = 'kitty', at = { x = 120, y = 130 }, monitor = { x = 0, y = 0 } }
handlers['window.close'](floating)
assert(K.state['place.kitty'] == '120,130', 'close normally remembers a floating place')
K.shutting_down = true
floating.class = 'shutdown-test'
handlers['window.close'](floating)
assert(K.state['place.shutdown-test'] == nil, 'close is a shutdown no-op')

clear_modules()
K = base_core({})
package.loaded['kuwai.actions'] = { usable = function(m) return { x = 0, y = 0, w = 1920, h = 1080, mx = 0, my = 0, mw = 1920, mh = 1080 } end }
local timers
handlers, timers, dispatched = reset(K, {
    get_active_monitor = function() return { x = 0, y = 0, width = 1920, height = 1080, scale = 1, reserved = {} } end,
})
package.loaded['kuwai.core'] = K
package.loaded['kuwai.actions'] = { usable = function(m) return { x = 0, y = 0, w = 1920, h = 1080, mx = 0, my = 0, mw = 1920, mh = 1080 } end }
dofile('hypr/kuwai/browsers.lua')
local browser = { address = '0xb', class = 'firefox', floating = true, title = 'Mozilla Firefox' }
handlers['window.open'](browser)
assert(#timers == 1, 'browser popup timer armed')
before = #dispatched
K.shutting_down = true
hl.get_window = function() error('window touched during shutdown') end
timers[1].fn()
assert(#dispatched == before, 'browser delayed styling is a shutdown no-op')

print('test_shutdown_guard: ok')
