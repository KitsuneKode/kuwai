package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

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

local base = os.time({ year = 2026, month = 6, day = 15, hour = 12, min = 0, sec = 0 })
local tz_offset = (os.time(os.date('*t', base)) - os.time(os.date('!*t', base))) / 3600
local lat, lon = 28.6, tz_offset * 15
local core = {
	bin = '/fixture/kuwai/bin',
	q = function(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end,
	json_str = function(s) return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end,
	feature = function() return false end,
	config = function() end,
	read_line = function() return nil end,
	notify = function() end,
	defer = function() end,
	state = {},
	set_state = function() end,
	night = { warm = 4200, lat = lat, lon = lon },
}
package.loaded['kuwai.core'] = core
dofile('hypr/kuwai/automation.lua')

local rise, set = core.sun_hours(lat, lon, base)
assert(rise and set and rise > 0 and set > rise, 'sun_hours must return valid sunrise and sunset')

local function at_hour(day, h)
	local hh = math.floor(h)
	local mm = math.floor((h - hh) * 60)
	return os.time({ year = 2026, month = 6, day = day, hour = hh, min = mm, sec = 0 })
end

local before_rise = at_hour(15, rise - 0.5)
local after_rise = at_hour(15, rise + 0.5)
local midday = at_hour(15, (rise + set) / 2)
local after_set = at_hour(15, set + 0.5)
local late_night = os.time({ year = 2026, month = 6, day = 15, hour = 23, min = 55, sec = 0 })
local after_midnight = os.time({ year = 2026, month = 6, day = 16, hour = 0, min = 5, sec = 0 })

local s0 = core.sun_schedule(before_rise)
local s1 = core.sun_schedule(after_rise)
local s2 = core.sun_schedule(midday)
local s3 = core.sun_schedule(after_set)
assert(s0.phase == 'night' and s0.boundary == '2026-06-14:night')
assert(s1.phase == 'day' and s1.boundary == '2026-06-15:day')
assert(s2.boundary == s1.boundary)
assert(s3.phase == 'night' and s3.boundary == '2026-06-15:night')
assert(core.sun_schedule(late_night).boundary == s3.boundary)
assert(core.sun_schedule(after_midnight).boundary == s3.boundary)
assert(#commands == 0)

local json = _G.kuwai.sun_schedule(midday)
assert(json:find('"phase":"day"') and json:find('"boundary":"2026%-06%-15:day"'), json)
print('ok sun boundary crossing')
