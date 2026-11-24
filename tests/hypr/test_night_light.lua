package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local real_date = os.date
local function run_case(hour, night_cfg)
    local state = {}
    local commands = {}
    _G.kuwai = {}
    _G.hl = {
        dsp = { no_op = function() return {} end },
        exec_cmd = function(cmd) table.insert(commands, cmd) end,
        window_rule = function() return { set_enabled = function() end } end,
        layer_rule = function() return { set_enabled = function() end } end,
        on = function() end,
        timer = function() end,
    }
    local core = {
        bin = '/fixture/bin',
        feature = function(name) return name == 'night_light' end,
        config = function() end,
        read_line = function() return nil end,
        notify = function() end,
        defer = function() end,
        state = state,
        set_state = function(k, v) state[k] = v end,
        night = night_cfg,
    }
    package.loaded['kuwai.core'] = core
    os.date = function(fmt)
        if fmt == '*t' then
            return { hour = hour, min = 0 }
        end
        return real_date(fmt)
    end
    dofile('hypr/kuwai/automation.lua')
    core.night_sync()
    os.date = real_date
    return state.night_phase, commands
end

assert(run_case(22, { warm = 4200, start = 20, stop = 6 }) == 'night', '22:00 must be night for 20..6')
assert(run_case(3, { warm = 4200, start = 20, stop = 6 }) == 'night', '03:00 must be night for 20..6')
assert(run_case(12, { warm = 4200, start = 20, stop = 6 }) == 'day', '12:00 must be day for 20..6')
assert(run_case(3, { warm = 4200, start = 1, stop = 6 }) == 'night', '03:00 must be night for 1..6')
assert(run_case(12, { warm = 4200, start = 1, stop = 6 }) == 'day', '12:00 must be day for 1..6')
assert(run_case(23, { warm = 4200, start = 1, stop = 6 }) == 'day', '23:00 must be day for 1..6')
print('night light schedule fixtures pass')
