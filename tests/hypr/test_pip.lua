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

local world, handlers, tick, binds, deferred
local function setup(title, wake_on, extra_wins)
	world = {
		monitors = {
			{ name = "eDP-1", x = 0, y = 0, width = 1920, height = 1080, scale = 1, reserved = {} },
			{ name = "DP-3", x = 1920, y = 0, width = 2560, height = 1440, scale = 1, reserved = {} },
		},
		cursor = { x = 100, y = 100 },
		shift = false,
	}
	world.pip = { address = "0xp", title = title or "Picture-in-Picture", floating = true,
		at = { x = 1920 + 2560 - 480 - 16, y = 1440 - 270 - 16 }, size = { x = 480, y = 270 } }
	world.pip.monitor = world.monitors[2]
	world.windows = { world.pip }
	for _, ew in ipairs(extra_wins or {}) do
		ew.monitor = ew.monitor or world.monitors[2]
		world.windows[#world.windows + 1] = ew
	end
	handlers, binds, tick, deferred = {}, {}, nil, {}
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
			local target = world.pip
			for _, w in ipairs(world.windows) do
				if a.args.window == "address:" .. w.address then
					target = w
					break
				end
			end
			target.at = { x = a.args.x, y = a.args.y }
			for _, m in ipairs(world.monitors) do
				if a.args.x >= m.x and a.args.x < m.x + m.width then
					target.monitor = m
				end
			end
		end
	end
	hl.get_windows = function()
		return world.windows
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
		defer = function(fn)
			deferred[#deferred + 1] = fn
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
	if wake_on == "defer" then
		for _, f in ipairs(deferred) do
			f()
		end
	else
		for _, f in ipairs(handlers[wake_on or "window.open"] or {}) do
			f(world.pip)
		end
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

-- A music app's compact player (Cider's Mini Player) is one too: passing fast, it steps aside.
setup("Cider - Mini Player")
at(3000, 1300)
at(3970, 1300)
check("mini player, fast pass: steps aside", world.pip.at.x, 1920 + 16)

-- A window that turns compact (its title changes to the mini player) starts the look.
setup("Cider - Mini Player", "window.title")
at(3000, 1300)
at(3970, 1300)
check("mini player by title change: steps aside", world.pip.at.x, 1920 + 16)

-- The app's main window is not one: no look starts for it at all.
setup("Cider")
check("the main window: no dodging look runs", tick, nil)

setup("Cider - Mini Player")
at(3000, 1300)
at(4150, 1300)
check("fast flick tunneling inside: still dodges", world.pip.at.x, 1920 + 16)

setup("Cider - Mini Player")
at(3970, 1300)
at(3000, 1300)
check("fast flick away: stays", world.pip.at.x, home)

setup("Cider - Mini Player")
world.shift = true
at(3000, 1300)
at(4150, 1300)
check("shift held on fast flick: stays", world.pip.at.x, home)

local mini = { address = "0xm", title = "Cider - Mini Player", floating = true,
	at = { x = 1920 + 2560 - 340 - 20, y = 54 }, size = { x = 340, y = 120 } }
setup("Picture-in-Picture", nil, { mini })
at(3950, 1220)
at(3975, 1230)
at(4020, 1245)
check("two pips: slow approach to first stays despite second", world.pip.at.x, home)
world.cursor = { x = mini.at.x + 50, y = mini.at.y + 50 }
binds["SUPER + ALT + W"]()
check("two pips: corner key moves hovered mini player", mini.at.x, 1920 + 2560 - 340 - 16)
check("two pips: unhovered pip untouched by corner key", world.pip.at.x, home)

setup("Cider - Mini Player")
at(100, 100)
local dock_x, dock_y = 1920 + 2560 - 480 - 20, 54
_G.kuwai.pip_note_move(world.pip.address, dock_x, dock_y)
world.pip.at = { x = dock_x, y = dock_y }
at(100, 100)
at(100, 100)
at(100, 100)
check("programmatic dock: not throw-snapped", world.pip.at.y, 54)

setup("Cider - Mini Player", "defer")
check("reload with existing mini player: wakes timer", tick ~= nil, true)

setup("Cider", "defer")
check("reload with only main window: no timer", tick, nil)

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("all passed")
