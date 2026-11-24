-- Without HyDE, Hyprland's side asks once (K.hyde) and the bridge adds nothing:
-- no startup commands, no binds that would run scripts that aren't there.
-- With it, the bridge starts HyDE's wallpaper and binds its pickers.
package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local real_getenv = os.getenv
local function core_with_home(home)
    os.getenv = function(k) if k == 'HOME' then return home end return real_getenv(k) end
    -- core registers a few start hooks at load; nothing runs here.
    _G.hl = setmetatable({ on = function() end }, { __index = function() return function() end end })
    package.loaded['kuwai.core'] = nil
    local K = dofile('hypr/kuwai/core.lua')
    os.getenv = real_getenv
    return K
end

local tmp = os.tmpname()
os.remove(tmp)
assert(os.execute('mkdir -p ' .. tmp .. '/without ' .. tmp .. '/with/.local/lib/hyde'))
local f = assert(io.open(tmp .. '/with/.local/lib/hyde/globalcontrol.sh', 'w'))
f:write('# HyDE\n')
f:close()

local without = core_with_home(tmp .. '/without')
assert(without.hyde == false, 'no HyDE: K.hyde must be false')
assert(without.hyde_lib == tmp .. '/without/.local/lib/hyde')
local with = core_with_home(tmp .. '/with')
assert(with.hyde == true, 'HyDE installed: K.hyde must be true')

-- The bridge, against a stand-in core that records what it would do.
local function bridge(hyde)
    local execs, binds, starts = {}, {}, {}
    _G.hl = {
        on = function(event, fn) starts[#starts + 1] = event; fn() end,
        exec_cmd = function(cmd) execs[#execs + 1] = cmd end,
        dsp = { global = function(name) return name end },
    }
    package.loaded['kuwai.core'] = {
        home = '/fixture', hyde = hyde, hyde_lib = '/fixture/.local/lib/hyde', apps = {},
        has = function() return false end,
        bind = function(keys, what) binds[#binds + 1] = keys .. ' ' .. what end,
        group = function() end,
    }
    dofile('hypr/kuwai/hyde.lua')
    return execs, binds, starts
end
local execs, binds, starts = bridge(false)
assert(#execs == 0 and #binds == 0 and #starts == 0, 'no HyDE: the bridge must add nothing')
execs, binds = bridge(true)
assert(#binds > 0, 'HyDE: its pickers are bound')
local wall = false
for _, c in ipairs(execs) do if c:find('/fixture/.local/lib/hyde/wallpaper.sh', 1, true) then wall = true end end
assert(wall, "HyDE: its wallpaper starts from HyDE's own folder")

local native_binds = {}
_G.hl = {
    dsp = {
        global = function(name) return 'global:' .. name end,
        window = setmetatable({}, { __index = function() return function() return '' end end }),
        group = setmetatable({}, { __index = function() return function() return '' end end }),
        workspace = setmetatable({}, { __index = function() return function() return '' end end }),
        focus = function() return '' end,
        layout = function() return '' end,
    },
    exec_cmd = function() end,
    dispatch = function() end,
    get_active_window = function() return nil end,
}
package.loaded['kuwai.core'] = {
    home = '/fixture', bin = '/fixture/bin', hyde = false, hyde_lib = '/fixture/.local/lib/hyde', apps = {},
    has = function() return false end,
    exists = function() return false end,
    feature = function() return false end,
    get = function() return 'us' end,
    bind = function(keys, _, act) native_binds[keys] = act end,
    group = function() end,
}
package.loaded['kuwai.actions'] = setmetatable({}, { __index = function() return function() return '' end end })
package.loaded['kuwai.workspaces'] = setmetatable({}, { __index = function() return function() return '' end end })
dofile('hypr/kuwai/binds.lua')
assert(native_binds['SUPER + comma'] == 'global:kuwai:emoji', 'no HyDE: emoji bind still exists')
assert(native_binds['SUPER + period'] == 'global:kuwai:glyphs', 'no HyDE: glyphs bind still exists')
assert(native_binds['CTRL + ALT + W'] == 'global:kuwai:island-tuck', 'no HyDE: island-tuck bind still exists')
assert(native_binds['CTRL + ALT + SHIFT + W'] == 'global:kuwai:island-style', 'no HyDE: island-style bind still exists')

os.execute('rm -rf ' .. tmp)
print('test_hyde: ok')
