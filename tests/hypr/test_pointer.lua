package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path
local applied, state = {}, {}
_G.kuwai = {}
_G.hl = setmetatable({ env = function() end, dsp = setmetatable({}, { __index = function() return function() return {} end end }) },
    { __index = function() return function() return {} end end })
package.loaded['kuwai.core'] = {
    state = state, set_state = function(k, v) state[k] = v end,
    config = function(c) table.insert(applied, c) end,
    feature = function() return false end, has = function() return false end, err = function() end, on_start = function() end,
    bin = '/fixture/bin', exists = function() return false end,
}
dofile('hypr/kuwai/input.lua')
local first = applied[1].input
assert(first.sensitivity == -0.5 and first.accel_profile == 'flat' and first.touchpad.natural_scroll == true, 'defaults as before')
assert(kuwai.pointer('speed', '0.25') == 'speed 0.25' and state['ptr.speed'] == '0.25', 'speed saved')
assert(applied[#applied].input.sensitivity == 0.25, 'speed applied live')
assert(kuwai.pointer('speed', '4'):find('from %-1 to 1'), 'out of range refused')
assert(kuwai.pointer('tap', 'maybe'):find('not a choice'), 'not a choice refused')
kuwai.pointer('accel', 'adaptive')
assert(applied[#applied].input.force_no_accel == false, 'acceleration on')
kuwai.pointer('speed', '-0.5')
assert(state['ptr.speed'] == nil, 'the default is not stored')
print('pointer settings pass')
