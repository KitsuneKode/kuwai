-- Picture-in-picture (hypr/kuwai/extras.lua): it steps aside for a pointer
-- passing fast, stays for one reaching for it or chasing it, and a drag
-- settles in the corner it was thrown toward, on that screen.
--   lua tests/hypr/test_pip.lua      (from the repo root)

package.path = "hypr/?.lua;hypr/?/init.lua;" .. package.path

local function auto(name)
	return setmetatable({}, {
		__index = function(t, k)
			local v = auto(name .. "." .. k)
			rawset(t, k, v)
			return v
		end,
		__call = function(_, args)
			return { op = name:gsub("^dsp%.", ""), args = args or {} }
		end,
	})
end

local world, handlers, tick, binds
local function setup()
	world = {
		monitors = {
			{ name = "eDP-1", x = 0, y = 0, width = 1920, height = 1080, scale = 1, reserved = {} },
			{ name = "DP-3", x = 1920, y = 0, width = 2560, height = 1440, scale = 1, reserved = {} },
		},
		cursor = { x = 100, y = 100 },
		shift = false,
	}
	world.pip = { address = "0xp", title = "Picture-in-Picture", floating = true,
		at = { x = 1920 + 2560 - 480 - 16, y = 1440 - 270 - 16 }, size = { x = 480, y = 270 } }
	world.pip.monitor = world.monitors[2]
	handlers, binds, tick = {}, {}, nil
	_G.hl = auto("hl")
	hl.dsp = auto("dsp")
	hl.on = function(ev, f)
		handlers[ev] = handlers[ev] or {}
		table.insert(handlers[ev], f)
	end
	hl.timer = function(f, o)
		if o.type == "repeat" then
			tick = f
		end
		return { set_enabled = function() end }
	end
	hl.dispatch = function(a)
		if type(a) == "table" and a.op == "window.move" and a.args.x then
			world.pip.at = { x = a.args.x, y = a.args.y }
			for _, m in ipairs(world.monitors) do
				if a.args.x >= m.x and a.args.x < m.x + m.width then
					world.pip.monitor = m
				end
			end
		end
	end
	hl.get_windows = function()
		return { world.pip }
	end
	hl.get_monitors = function()
		return world.monitors
	end
	hl.get_cursor_pos = function()
		return world.cursor
	end
	hl.is_key_down = function()
		return world.shift
	end
	local K = setmetatable({
		state = {},
		feature = function(f)
			return f == "pip_dodge"
		end,
		bind = function(keys, _, fn)
			binds[keys] = fn
		end,
	}, { __index = function(_, k)
		return auto("K." .. k)
	end })
	package.loaded["kuwai.core"] = K
	package.loaded["kuwai.actions"] = setmetatable({
		usable = function(m)
			return { x = m.x, y = m.y, w = m.width, h = m.height, mx = m.x, my = m.y, mw = m.width, mh = m.height }
		end,
		pip_toggle = function()
			return function() end
		end,
	}, { __index = function(_, k)
		return auto("A." .. k)
	end })
	dofile(os.getenv("EXTRAS_FILE") or "hypr/kuwai/extras.lua")
	for _, f in ipairs(handlers["window.open"] or {}) do
		f(world.pip)
	end
end
local function at(x, y)
	world.cursor = { x = x, y = y }
	tick()
end

local failed = 0
local function check(name, got, want)
	if got ~= want then
		failed = failed + 1
		print("FAIL " .. name .. ": got " .. tostring(got) .. ", want " .. tostring(want))
	else
		print("ok   " .. name)
	end
end
local home = 1920 + 2560 - 480 - 16

-- 1. Reaching for it slowly (to seek): it stays.
setup()
at(3600, 1000)
at(3700, 1080)
at(3790, 1140)
at(3850, 1170)
at(3900, 1200)
at(3950, 1220)
at(3975, 1230)
at(4010, 1240)
at(4060, 1250)
check("slow approach: stays", world.pip.at.x, home)

-- 2. Passing by fast: it steps aside to the other bottom corner.
setup()
at(3000, 1300)
at(3970, 1300)
check("fast pass: steps aside", world.pip.at.x, 1920 + 16)

-- 3. You chase it there: it stays put.
at(3000, 1300)
at(2100, 1300)
check("chased: stays", world.pip.at.x, 1920 + 16)

-- 4. Thrown up (Super+drag toward the top): it settles in a top corner.
setup()
at(100, 100)
world.pip.at = { x = home, y = 900 }
at(100, 100)
world.pip.at = { x = home, y = 500 }
at(100, 100)
at(100, 100)
at(100, 100)
check("thrown up: top corner y", world.pip.at.y, 16)
check("thrown up: same side", world.pip.at.x, home)

-- 5. Thrown across to the laptop: it lands in the laptop's corner.
setup()
at(100, 100)
world.pip.at = { x = 2200, y = 1150 }
at(100, 100)
world.pip.at = { x = 1700, y = 800 }
at(100, 100)
at(100, 100)
at(100, 100)
check("thrown across: on the laptop", world.pip.monitor.name, "eDP-1")
check("thrown across: a laptop corner x", world.pip.at.x == 16 or world.pip.at.x == 1920 - 480 - 16, true)

-- 6. Keys: next corner, then the other screen (same corner there).
setup()
binds["SUPER + ALT + W"]()
check("next corner: bottom-left", world.pip.at.x, 1920 + 16)
binds["SUPER + ALT + SHIFT + W"]()
check("other screen: the laptop", world.pip.monitor.name, "eDP-1")
check("other screen: same corner (bottom-left)", world.pip.at.x .. "," .. world.pip.at.y, 16 .. "," .. (1080 - 270 - 16))

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("all passed")
