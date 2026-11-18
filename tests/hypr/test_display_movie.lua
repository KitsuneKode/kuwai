-- Automatic Movie (hypr/kuwai/display.lua): a player takes 120 Hz only on the external
-- screen it is on, and keeps it until it closes, not until focus wanders.
-- It modeset every external screen whenever any player was focused, and went back 2.5 s after
-- focus left: a film on the laptop panel blanked the Acer (nothing played there), and every
-- look at the terminal driving the player (kunai) was two more blackouts.
--   lua tests/hypr/test_display_movie.lua      (from the repo root)

package.path = "hypr/?.lua;hypr/?/init.lua;" .. package.path

local DP3 = { name = "DP-3", width = 2560, height = 1440, available_modes = {
	{ width = 2560, height = 1440, refresh_rate = 200 }, { width = 2560, height = 1440, refresh_rate = 120 } } }
local EDP = { name = "eDP-1", width = 2560, height = 1440, available_modes = {
	{ width = 2560, height = 1440, refresh_rate = 165 }, { width = 2560, height = 1440, refresh_rate = 60 } } }

local W, active, timers, modes, reloads, handlers
local function fresh()
	for k in pairs(package.loaded) do
		if k:match("^kuwai") then package.loaded[k] = nil end
	end
	_G.__kuwai_raw_monitor, _G.kuwai = nil, nil
	W, active, timers, modes, reloads, handlers = {}, nil, {}, {}, 0, {}
	local K = { state = {}, home = "/nonexistent", night_off = "true", colour_apps = {} }
	function K.set_state(k, v) K.state[k] = v ~= nil and tostring(v) or nil end
	function K.feature(name) return name == "auto_display" end
	function K.config() end
	function K.notify() end
	function K.err(m) error(m) end
	function K.exists() return false end
	function K.ac_online() return true end
	function K.defer() end
	package.loaded["kuwai.core"] = K
	_G.hl = {
		dsp = { reload_config = function() return "reload" end },
		monitor = function(spec) modes[spec.output] = spec.mode end,
		get_monitors = function() return { DP3, EDP } end,
		get_windows = function() return W end,
		get_active_window = function() return active end,
		on = function(ev, f) handlers[ev] = f end,
		timer = function(f) timers[#timers + 1] = f end,
		dispatch = function(a) if a == "reload" then reloads = reloads + 1 end end,
		exec_cmd = function() end,
	}
	local D = require("kuwai.display")
	hl.monitor({ output = "DP-3", mode = "2560x1440@200" })
	hl.monitor({ output = "eDP-1", mode = "2560x1440@165" })
	modes = {}
	return D, K
end
local function settle()   -- let every pending timer run (the settles are one-shot)
	for _ = 1, 10 do
		local t = timers; timers = {}
		if #t == 0 then return end
		for _, f in ipairs(t) do f() end
	end
end
local function open(w) W[#W + 1] = w; active = w; handlers["window.open"](w); settle() end
local function focus(w) active = w; handlers["window.active"](w); settle() end
local function close(w)
	for i, x in ipairs(W) do if x == w then table.remove(W, i) end end
	if active == w then active = W[1] end
	handlers["window.destroy"](w); settle()
end
local fails = 0
local function check(cond, what)
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end

do -- a film on the laptop panel leaves the Acer alone: no Movie, no reload, no modeset
	local D, K = fresh()
	open({ address = "0x1", class = "mpv", monitor = EDP, fullscreen = 0 })
	check(K.state.display_auto ~= "movie", "a player on the panel took Movie")
	check(reloads == 0, "a player on the panel reloaded the config")
	D.apply()
	check(modes["DP-3"] == nil, "the Acer was modeset for a player on the panel")
end

do -- a film on the Acer: Movie, and 120 Hz there only
	local D, K = fresh()
	open({ address = "0x1", class = "mpv", monitor = DP3, fullscreen = 0 })
	check(K.state.display_auto == "movie", "a player on the Acer didn't take Movie")
	check(reloads == 1, "taking Movie is one reload")
	modes = {}; D.apply()
	check(modes["DP-3"] == "2560x1440@120", "the Acer isn't at 120 Hz under its player")
	check(modes["eDP-1"] == nil, "the panel was modeset")
end

do -- looking at the terminal that drives the player keeps Movie; closing the player ends it
	local _, K = fresh()
	local mpv = { address = "0x1", class = "mpv", monitor = DP3, fullscreen = 0 }
	local term = { address = "0x2", class = "kitty", monitor = EDP, fullscreen = 0 }
	W[#W + 1] = term
	open(mpv)
	focus(term)
	check(K.state.display_auto == "movie", "a glance at the terminal left Movie")
	check(reloads == 1, "a glance at the terminal reloaded (a modeset, a blackout)")
	focus(mpv); focus(term); focus(mpv)
	check(reloads == 1, "moving focus back and forth reloaded")
	close(mpv)
	check(K.state.display_auto == nil, "Movie outlived the last player")
	check(reloads == 2, "closing the player is one reload back")
end

do -- Movie you chose yourself is for a browser too: every external screen, player or not
	local D, K = fresh()
	K.state.display = "movie"
	D.apply()
	check(modes["DP-3"] == "2560x1440@120", "a chosen Movie didn't take the Acer")
end

if fails > 0 then
	os.exit(1)
end
print("ok test_display_movie")
