package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local cfg = {}
local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == 'table' and type(dst[k]) == 'table' and v.colors == nil then merge(dst[k], v)
        else dst[k] = v end
    end
end
package.loaded['kuwai.core'] = { config = function(t) merge(cfg, t) end, err = function(m) error(m) end }
package.loaded['kuwai.theme'] = {
    colors = {},
    load_colors = function() end,
    rgba = function() return nil end,
    apply = function()
        merge(cfg, { general = { border_size = 4, gaps_in = 2, gaps_out = 4, col = { active_border = 'rgba(ff0000ff)' } },
                     decoration = { rounding = 10, rounding_power = 2, dim_inactive = true, dim_strength = 0.06,
                                    active_opacity = 0.95, inactive_opacity = 0.9,
                                    glow = { enabled = false, range = 30 },
                                    shadow = { range = 60, offset = '0 2', color = 'rgba(5d3d4ad0)' } } })
    end,
}
_G.hl = setmetatable({}, { __index = function() return function() end end })
package.loaded['kuwai.look'] = nil
local L = dofile('hypr/kuwai/look.lua')

assert(cfg.decoration.rounding == 18, 'corners are kuwai\'s: ' .. tostring(cfg.decoration.rounding))
assert(cfg.decoration.rounding_power == 4, 'a squircle')
assert(cfg.general.border_size == 2, 'the frame is 2 px')
assert(cfg.general.gaps_in == 5 and cfg.general.gaps_out == 10, 'gaps are kuwai\'s')
assert(cfg.decoration.dim_inactive == false, 'no dimming: Focus mode is the quiet option')
assert(cfg.decoration.active_opacity == 1.0 and cfg.decoration.inactive_opacity == 1.0, 'windows stay opaque')
assert(cfg.decoration.glow.enabled == true and cfg.decoration.glow.range == 12, 'the glow is kuwai\'s rim light')
assert(cfg.decoration.shadow.range == 40 and cfg.decoration.shadow.offset == '0 12', 'one shadow size')
assert(cfg.general.col.active_border == 'rgba(ff0000ff)', 'the theme keeps its border colour')
assert(cfg.decoration.shadow.color == 'rgba(5d3d4ad0)', 'the theme keeps its shadow tint')
assert(cfg.decoration.dim_strength == 0.06, 'what the shape does not name stays the theme\'s')
assert(type(L.SHAPE) == 'table', 'the shape is one table others can read')
print('ok look shape')
