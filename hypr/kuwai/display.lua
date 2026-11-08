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
--   Movie is never automatic: changing the rate as a video goes fullscreen
--   would blank the screen each time.
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
local raw_monitor = hl.monitor
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

local function apply_screens(preset)
	for _, m in ipairs(hl.get_monitors() or {}) do
		local r = rule_for(m)
		if r then
			local mode = mode_for(m, r.base.mode, preset) or r.base.mode
			r.ref.mode = mode -- the lid switch re-issues K.panel: keep the preset's rate
			if mode ~= r.base.mode then
				local spec = {}
				for k, v in pairs(r.base) do
					spec[k] = v
				end
				spec.mode = mode
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
		if p == "accurate" then
			K.config({ render = { non_shader_cm = 0, direct_scanout = 0 } })
			hl.exec_cmd(K.night_off)
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

function kuwai.displays()
	return table.concat(D.list, " ")
end

---------------------------------------------------------------------------
-- Automatic: colour apps → accurate
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

local function sync_colour(gone)
	if not K.feature("auto_display") then
		return
	end
	local why
	for _, w in ipairs(hl.get_windows() or {}) do
		if w ~= gone and (not gone or w.address ~= gone.address) then
			why = why or colour_app(w)
		end
	end
	if why then
		D.auto("accurate", why)
	elseif K.state["display_auto"] == "accurate" then
		D.auto(D.battery_auto())
	end
end

-- Unplugged (and auto_battery on) → battery underneath anything else.
function D.battery_auto()
	if K.feature("auto_display") and K.feature("auto_battery") and K.ac_online and K.ac_online() == false then
		return "battery", "On battery"
	end
end

hl.on("window.open", function(w)
	if colour_app(w) then
		sync_colour()
	end
end)
hl.on("window.destroy", function(w)
	if K.state["display_auto"] == "accurate" and colour_app(w) then
		sync_colour(w)
	end
end)
K.defer(function()
	sync_colour() -- e.g. Krita already open across a reload or restart
end)

kuwai.display_module = D
return D
