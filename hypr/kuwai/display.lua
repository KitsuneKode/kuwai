-- kuwai.display — what the screens are for right now. The look modes
-- (modes.lua) change how windows look; this changes the signal the screens
-- get: refresh rate, Night Shift and how strictly colour is managed.
--
--   everyday  every screen at the rate monitors.lua gives it; Night Shift on
--             its sunset schedule
--   accurate  Night Shift off and held off (sunset won't warm it); colour
--             always goes through the shader pipeline and nothing is scanned
--             out directly, so what you see is the managed result. For
--             judging colour in client work
--   movie     external screens at 120 Hz (5×24, 4×30, 2×60 fps: even film
--             cadence in a window or a browser; fullscreen video already gets
--             VRR). Built-in panels keep their rate
--   gaming    the gaming look mode (nothing between you and the frame);
--             leaving restores the look you had
--   battery   built-in panel at its lowest rate (60 Hz); externals untouched
--
-- Automatic (feature auto_display), only while you've chosen everyday:
--   a colour app is open (Krita, GIMP, Inkscape, Darktable…) → accurate,
--   until the last one closes; unplugged → battery (with auto_battery).
--   A video player focused, and not fullscreen, for a little over a second
--   → movie (120 Hz, HDR ready). The rate is not touched while that picture
--   is fullscreen: a modeset there blanks the panel. Fullscreen HDR on the
--   current rate still arms (cm_auto_hdr 2). A fullscreen game arms HDR the
--   same way and does not take the gaming preset — that preset reloads, and
--   auto_game already drops the effects.
--
-- `kuwai.display("movie")`, `kuwai.display()` → the preset in effect.
-- State (~/.local/state/kuwai/state): display = your choice, display_auto =
-- what automation picked on top of everyday, display_why = the reason.
-- Applied by a config reload (like the look modes): leaving a preset gives
-- back exactly what the config says.

local K = require("kuwai.core")

local D = {
	list = { "everyday", "accurate", "movie", "gaming", "battery" },
	describe = {
		everyday = "Configured rates, Night Shift on schedule",
		accurate = "Night Shift held off, strict colour management",
		movie = "External screens at 120 Hz for even film cadence",
		gaming = "Gaming look: no effects, tearing allowed",
		battery = "Built-in panel at 60 Hz",
	},
}

-- Apps where colour is the work. user.lua can add to K.colour_apps.
K.colour_apps = K.colour_apps
	or {
		"^gimp", "^org%.gimp", "^krita$", "^org%.kde%.krita$", "^inkscape$", "^org%.inkscape",
		"^darktable$", "^org%.darktable", "^rawtherapee", "^com%.rawtherapee", "^kdenlive$",
		"^org%.kde%.kdenlive$", "^resolve$", "^blender$", "^figma", "^penpot", "^photopea",
		"^shotcut$", "^org%.shotcut", "^digikam$", "^org%.kde%.digikam",
	}

local function valid(name)
	return D.describe[name] ~= nil
end

function D.choice()
	local c = K.state["display"]
	return valid(c) and c or "everyday"
end

-- The preset in effect: your choice, or what automation put on top of everyday.
function D.current()
	local c = D.choice()
	if c == "everyday" and valid(K.state["display_auto"]) then
		return K.state["display_auto"]
	end
	return c
end

---------------------------------------------------------------------------
-- Screens: monitors.lua's rules are remembered as they're made, so a preset
-- can re-issue a screen's own rule with only the mode changed (position,
-- scale, VRR and bit depth stay what you wrote).
---------------------------------------------------------------------------
local rules = {} -- { ref = the table passed in, base = a copy as written }
-- The original, kept once: if the Lua state outlives a reload, wrapping the
-- previous load's wrapper would stack one more layer per reload.
_G.__kuwai_raw_monitor = _G.__kuwai_raw_monitor or hl.monitor
local raw_monitor = _G.__kuwai_raw_monitor
hl.monitor = function(spec, ...)
	if type(spec) == "table" and spec.output and spec.output ~= "" and not spec.disabled then
		local known
		for _, r in ipairs(rules) do
			if r.ref == spec then
				known = r
			end
		end
		if not known then
			local base = {}
			for k, v in pairs(spec) do
				base[k] = v
			end
			rules[#rules + 1] = { ref = spec, base = base }
		end
	end
	return raw_monitor(spec, ...)
end

local function internal(m)
	return (m.name or ""):match("^eDP") or (m.name or ""):match("^LVDS") or (m.name or ""):match("^DSI")
end

local function rule_for(m)
	for _, r in ipairs(rules) do
		local o = r.base.output
		if o == m.name or (o:sub(1, 5) == "desc:" and (m.description or ""):sub(1, #o - 5) == o:sub(6)) then
			return r
		end
	end
end

-- The mode a screen should run in for `preset`, or nil for its own rule's.
local function mode_for(m, base_mode, preset)
	local w, h = tostring(base_mode or ""):match("^(%d+)x(%d+)")
	w, h = tonumber(w) or m.width, tonumber(h) or m.height
	local rates = {}
	for _, am in ipairs(m.available_modes or {}) do
		if am.width == w and am.height == h then
			rates[#rates + 1] = am.refresh_rate
		end
	end
	local function pick(want)
		for _, r in ipairs(rates) do
			if math.abs(r - want) < 0.5 then
				return ("%dx%d@%d"):format(w, h, want)
			end
		end
	end
	if preset == "movie" and not internal(m) then
		return pick(120)
	elseif preset == "battery" and internal(m) then
		return pick(60)
	end
end

-- A measured profile for this screen (from a colorimeter; see `kuwai display
-- profile`): ~/.local/share/kuwai/icc/<screen>.icc, <screen> being its
-- description in lowercase with dashes (no serial number). Used only by the
-- accurate preset: an ICC replaces the screen's colour preset (so no automatic
-- HDR there), and the other presets are for watching and playing.
function D.icc_name(m)
	local d = (m.description or m.name or ""):gsub("%s+%x+$", "") -- drop a trailing serial
	return (d:lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", ""))
end
function D.icc_for(m)
	local path = K.home .. "/.local/share/kuwai/icc/" .. D.icc_name(m) .. ".icc"
	return K.exists(path) and path or nil
end

local function apply_screens(preset)
	for _, m in ipairs(hl.get_monitors() or {}) do
		local r = rule_for(m)
		if r then
			local mode = mode_for(m, r.base.mode, preset) or r.base.mode
			r.ref.mode = mode -- the lid switch re-issues K.panel: keep the preset's rate
			local icc = preset == "accurate" and D.icc_for(m) or nil
			if mode ~= r.base.mode or icc then
				local spec = {}
				for k, v in pairs(r.base) do
					spec[k] = v
				end
				spec.mode = mode
				if icc then
					spec.icc = icc
				end
				pcall(raw_monitor, spec)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Apply (every load, after monitors.lua, user.lua and the look mode)
---------------------------------------------------------------------------
function D.apply()
	local p = D.current()
	local ok, err = pcall(function()
		apply_screens(p)
		-- Movie and gaming are the presets where a modeset is the point
		-- (film cadence, a game's own HDR). Everyday, accurate and battery
		-- stay on the picture monitors.lua asked for.
		-- 2 = hdredid: the PQ signal with this screen's own primaries (its
		-- EDID), not BT.2020 (1): a DisplayHDR 400 panel covers ~90 % P3,
		-- two-thirds of Rec.2020, so 1 claimed colours the glass doesn't have.
		local auto_hdr = (p == "movie" or p == "gaming") and 2 or 0
		if p == "accurate" then
			K.config({ render = { non_shader_cm = 0, direct_scanout = 0, cm_auto_hdr = 0 } })
			hl.exec_cmd(K.night_off)
		else
			K.config({ render = { cm_auto_hdr = auto_hdr } })
		end
	end)
	if not ok then
		K.err("display " .. p .. ": " .. tostring(err))
	end
end

-- Change what's in effect: state first, then a reload re-runs the config.
local function switch(from, to)
	if from == to then
		return
	end
	-- The gaming look rides along with the gaming preset.
	local mode = K.state["mode"] or "focus"
	if to == "gaming" and mode ~= "gaming" then
		K.set_state("mode_before_display_gaming", mode)
		K.set_state("mode", "gaming")
	elseif from == "gaming" and to ~= "gaming" then
		local back = K.state["mode_before_display_gaming"]
		K.set_state("mode_before_display_gaming", nil)
		if mode == "gaming" then
			K.set_state("mode", back or "focus")
		end
	end
	if to == "accurate" then
		hl.exec_cmd(K.night_off)
	elseif from == "accurate" and K.night_sync then
		K.night_sync(true) -- back to what the schedule says now
	end
	hl.dispatch(hl.dsp.reload_config())
end

---------------------------------------------------------------------------
-- Runtime API (the center's Display row, the kuwai CLI, `hyprctl eval`)
---------------------------------------------------------------------------
_G.kuwai = _G.kuwai or {}

function kuwai.display(name)
	if name == nil then
		return D.current()
	end
	if not valid(name) then
		K.notify("kuwai: no display preset '" .. tostring(name) .. "'", 2500, "error")
		return D.current()
	end
	local from = D.current()
	K.set_state("display", name ~= "everyday" and name or nil)
	-- Choosing hands-off: a manual choice clears what automation picked.
	K.set_state("display_auto", nil)
	K.set_state("display_why", nil)
	switch(from, D.current())
	return name
end

-- Automation's layer: only on top of everyday; nil clears it.
function D.auto(preset, why)
	if K.state["display_auto"] == preset then
		return
	end
	local from = D.current()
	K.set_state("display_auto", preset)
	K.set_state("display_why", preset and why or nil)
	if D.choice() == "everyday" then
		switch(from, D.current())
	end
end

-- For `kuwai display profile`: each screen, its profile file, and whether it exists.
function kuwai.display_profiles()
	local out = {}
	for _, m in ipairs(hl.get_monitors() or {}) do
		local path = K.home .. "/.local/share/kuwai/icc/" .. D.icc_name(m) .. ".icc"
		out[#out + 1] = m.name .. "\t" .. (m.description or "") .. "\t" .. path .. "\t" .. (K.exists(path) and "yes" or "no")
	end
	return table.concat(out, "\n")
end

function kuwai.displays()
	return table.concat(D.list, " ")
end

---------------------------------------------------------------------------
-- Automatic, only on top of everyday.
-- Colour work wins. A player you have settled on takes Movie, but never by
-- modesetting under a fullscreen picture. A fullscreen game only arms HDR.
---------------------------------------------------------------------------
local function colour_app(w)
	local c = (w and (w.class or w.initial_class) or ""):lower()
	if c == "" then
		return nil
	end
	for _, pat in ipairs(K.colour_apps) do
		if c:match(pat) then
			return w.class
		end
	end
end

local function find_colour(gone)
	local why
	for _, w in ipairs(hl.get_windows() or {}) do
		if w ~= gone and (not gone or w.address ~= gone.address) then
			why = why or colour_app(w)
		end
	end
	return why
end

local function is_video(w)
	if not w then
		return false
	end
	if w.content_type == "video" then
		return true
	end
	local c = (w.class or w.initial_class or ""):lower()
	return c:find("mpv", 1, true) ~= nil
		or c == "vlc"
		or c:find("celluloid", 1, true) ~= nil
		or c:find("haruna", 1, true) ~= nil
		or c:find("clapper", 1, true) ~= nil
end

local function is_game(w)
	if not w then
		return false
	end
	if w.content_type == "game" then
		return true
	end
	local c = (w.class or w.initial_class or ""):lower()
	return c:match("^steam_app_") ~= nil or c == "gamescope" or c:match("%.exe$") ~= nil or c == "cs2"
end

local function fullscreen(w)
	return w and (w.fullscreen or 0) > 0
end

local function any_such(pred)
	for _, w in ipairs(hl.get_windows() or {}) do
		if pred(w) then
			return w
		end
	end
end

-- Unplugged (and auto_battery on) → battery underneath anything else.
function D.battery_auto()
	if K.feature("auto_display") and K.feature("auto_battery") and K.ac_online and K.ac_online() == false then
		return "battery", "On battery"
	end
end

-- cm_auto_hdr armed without a preset change. The preset's own apply() owns
-- the flag while Movie, Gaming or Accurate is in effect. Kept local so a
-- later "off" cannot run while one of those still wants it on.
local hdr_forced = false
local function preset_wants_hdr()
	local p = D.current()
	return p == "movie" or p == "gaming"
end
local function hdr_arm(on)
	if preset_wants_hdr() then
		return
	end
	if on == hdr_forced then
		return
	end
	hdr_forced = on
	K.config({ render = { cm_auto_hdr = on and 2 or 0 } })
end

-- One outstanding settle. A new reason cancels the previous timer.
local ticket, pending = 0, nil
local function cancel()
	pending = nil
	ticket = ticket + 1
end
local function schedule(kind, ms, fn)
	if pending == kind then
		return
	end
	pending = kind
	ticket = ticket + 1
	local mine = ticket
	hl.timer(function()
		if mine ~= ticket then
			return
		end
		pending = nil
		fn()
	end, { timeout = ms, type = "oneshot" })
end

local function go(preset, why)
	hdr_forced = false -- apply() sets the flag for the preset we land on
	D.auto(preset, why)
end

-- The window an event just handed us, when it is the one in front.
-- window.open runs before get_active_window() sees the new player, and a
-- fullscreen callback can run while the active window is still the one behind.
local function front(hint)
	local active = hl.get_active_window()
	if hint and (is_video(hint) or is_game(hint)) then
		if fullscreen(hint) or not active or active.address == hint.address then
			return hint
		end
	end
	return active
end

-- What everyday should be showing right now.
function D.reconcile(gone, hint)
	if not K.feature("auto_display") or D.choice() ~= "everyday" then
		return
	end
	local colour = find_colour(gone)
	local video_fs = any_such(function(w)
		return is_video(w) and fullscreen(w)
	end)
	local active = front(hint)
	local watching = is_video(active) or video_fs
	-- A colour app wins, except under a fullscreen picture: leaving Movie
	-- for Accurate there reloads sRGB while the PQ signal is still up and
	-- the panel keeps the wide primaries.
	if colour and not video_fs then
		cancel()
		go("accurate", colour)
		return
	end
	if watching then
		if pending == "idle" then
			cancel()
		end
		if video_fs and D.current() ~= "movie" then
			-- Same rate. Hyprland flips to PQ only if this frame is HDR.
			hdr_arm(true)
			return
		end
		if not video_fs and K.state["display_auto"] ~= "movie" and not colour then
			local why = (active and (active.class or active.initial_class)) or "video"
			schedule("movie", 1200, function()
				if D.choice() ~= "everyday" or find_colour() then
					return
				end
				local fs = any_such(function(w)
					return is_video(w) and fullscreen(w)
				end)
				if fs or not is_video(hl.get_active_window()) then
					return
				end
				go("movie", why)
			end)
		end
		return
	end
	if any_such(function(w)
		return is_game(w) and fullscreen(w)
	end) then
		cancel()
		hdr_arm(true)
		return
	end
	-- Focus has left the player and nothing is fullscreen. Wait, so a glance
	-- at another window does not modeset the Acer back to 200 Hz. Nothing to
	-- undo: don't arm a timer at all.
	local back = D.battery_auto()
	if not hdr_forced and K.state["display_auto"] == back then
		return
	end
	schedule("idle", 2500, function()
		if find_colour() then
			go("accurate", find_colour())
			return
		end
		if is_video(hl.get_active_window()) or any_such(function(w)
			return (is_video(w) or is_game(w)) and fullscreen(w)
		end) then
			return
		end
		hdr_arm(false)
		local preset, why = D.battery_auto()
		if K.state["display_auto"] ~= preset then
			go(preset, why)
		end
	end)
end

hl.on("window.open", function(w)
	D.reconcile(nil, w)
	-- Focus often lands a moment after open. A raw timer, so this retry
	-- cannot cancel a Movie settle that reconcile just armed.
	if is_video(w) then
		hl.timer(function()
			D.reconcile()
		end, { timeout = 500, type = "oneshot" })
	end
end)
hl.on("window.active", function(w)
	D.reconcile(nil, w)
end)
hl.on("window.class", function(w)
	D.reconcile(nil, w)
end)
hl.on("window.fullscreen", function(w)
	D.reconcile(nil, w)
end)
hl.on("window.update_rules", function(w)
	if is_video(w) or is_game(w) then
		D.reconcile(nil, w)
	end
end)
hl.on("window.destroy", function(w)
	D.reconcile(w)
end)
K.defer(function()
	D.reconcile() -- a colour app or a player already open across a reload
end)

kuwai.display_module = D
return D
