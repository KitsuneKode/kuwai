package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local function merged(calls)
    local out = {}
    local function into(dst, src)
        for k, v in pairs(src) do
            if type(v) == 'table' and type(dst[k]) == 'table' and v.colors == nil then
                into(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
    for _, t in ipairs(calls) do into(out, t) end
    return out
end

local function load_look(colors, kuwai_theme)
    local calls = {}
    _G.hl = { config = function(t) calls[#calls + 1] = t end }
    package.loaded['kuwai.core'] = {
        config = function(t) calls[#calls + 1] = t end,
        err = function(m) error(m) end,
    }
    local T = { colors = colors, kuwai = kuwai_theme }
    function T.load_colors() end
    function T.apply() end
    function T.rgba(name, alpha)
        local hex = T.colors[name]
        if not hex or not hex:match('^%x%x%x%x%x%x$') then return nil end
        return 'rgba(' .. hex .. (alpha or 'ff') .. ')'
    end
    package.loaded['kuwai.theme'] = T
    package.loaded['kuwai.look'] = nil
    dofile('hypr/kuwai/look.lua')
    return merged(calls)
end

local function alpha_of(rgba)
    return rgba:match('^rgba%(%x%x%x%x%x%x(%x%x)%)$')
end

local function stops(g)
    if type(g) == 'string' then return { g } end
    return g.colors
end

local plain = load_look({}, false).decoration.glow
assert(plain, 'decoration.glow must be configured')
assert(plain.enabled == true, 'glow must be enabled')
assert(plain.range >= 8 and plain.range <= 24, 'glow range should stay subtle (8..24 px), got ' .. tostring(plain.range))
assert(plain.color_inactive == 'rgba(00000000)', 'unfocused windows must not glow')
for _, s in ipairs(stops(plain.color)) do
    local a = tonumber(alpha_of(s), 16)
    assert(a and a > 0 and a <= 0x60, 'glow stop too loud or malformed: ' .. s)
end

local themed = load_look({ accent = '8aadf4', accentSoft = 'c6a0f6', border = '363a4f' }, true).decoration.glow
local first = stops(themed.color)[1]
assert(first:find('^rgba%(8aadf4'), 'glow must follow the theme accent, got ' .. first)
for _, st in ipairs(stops(themed.color)) do
    assert(st:find('^rgba%(8aadf4'), 'every glow stop must stay in the accent hue, got ' .. st)
end
assert(themed.color_inactive == 'rgba(00000000)', 'themed: unfocused windows must not glow')
for _, s in ipairs(stops(themed.color)) do
    local a = tonumber(alpha_of(s), 16)
    assert(a and a > 0 and a <= 0x60, 'themed glow stop too loud or malformed: ' .. s)
end

local rules = {}
_G.hl = {
    window_rule = function(spec) rules[#rules + 1] = spec; return {} end,
    layer_rule = function() end,
    workspace_rule = function() end,
}
package.loaded['kuwai.core'] = { err = function(m) error(m) end }
package.loaded['kuwai.rules'] = nil
dofile('hypr/kuwai/rules.lua')
local fs, games = false, false
for _, r in ipairs(rules) do
    if r.no_glow and r.match and r.match.fullscreen == true then fs = true end
    if r.name == 'games' and r.no_glow then games = true end
end
assert(fs, 'a rule must turn glow off for fullscreen windows')
assert(games, 'the games rule must turn glow off')
local function rule_named(n)
    for _, r in ipairs(rules) do if r.name == n then return r end end
end
for _, n in ipairs({ 'pip-look', 'video-no-glow', 'photo-no-glow', 'solo-tile-no-glow', 'jb-splash', 'jb-popup' }) do
    local r = rule_named(n)
    assert(r and r.no_glow == true, n .. ' must turn glow off')
end
local solo, lifted
for i, r in ipairs(rules) do
    if r.name == 'solo-tile-no-glow' then solo = i end
    if r.name == 'special-lifted' then lifted = i end
end
assert(lifted and solo and lifted > solo, 'special-lifted must come after solo-tile-no-glow so it wins')
assert(rule_named('special-lifted').no_glow == false and rule_named('special-lifted').no_shadow == false)

print('ok look glow')
