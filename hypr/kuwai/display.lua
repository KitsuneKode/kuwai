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

function D.current()
	local c = D.choice()
	if c == "everyday" and valid(K.state["display_auto"]) then
		return K.state["display_auto"]
	end
	return c
end

function D.hdr_choice()
	return K.state["display_hdr"] == "on"
end

function D.hdr_active(preset)
	return D.hdr_choice() and (preset or D.current()) ~= "accurate"
end

local rules = {}
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

function D.icc_name(m)
	local d = (m.description or m.name or ""):gsub("%s+%x+$", "")
	return (d:lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", ""))
end
function D.icc_for(m)
	local path = K.home .. "/.local/share/kuwai-data/icc/" .. D.icc_name(m) .. ".icc"
	return K.exists(path) and path or nil
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

local function player_screens(gone)
	local on = {}
	for _, w in ipairs(hl.get_windows() or {}) do
		if is_video(w) and not (gone and w.address == gone.address) and w.monitor and w.monitor.name then
			on[w.monitor.name] = true
		end
	end
	return on
end

local function external_player(gone)
	for name in pairs(player_screens(gone)) do
		if not internal({ name = name }) then
			return true
		end
	end
	return false
end

local function hdr_capable(m, r)
	if r.base.hdr == false then
		return false
	end
	if r.base.hdr == true then
		return true
	end
	return not internal(m) and r.base.max_luminance ~= nil
end

local function apply_screens(preset)
	local players = preset == "movie" and D.choice() == "everyday" and player_screens() or nil
	local hdr = D.hdr_active(preset)
	for _, m in ipairs(hl.get_monitors() or {}) do
		local r = rule_for(m)
		if r then
			local mode = (players and not players[m.name]) and r.base.mode
				or mode_for(m, r.base.mode, preset) or r.base.mode
			local cm = (hdr and hdr_capable(m, r)) and "hdredid" or r.base.cm
			r.ref.mode = mode
			r.ref.cm = cm
			local icc = preset == "accurate" and D.icc_for(m) or nil
			if mode ~= r.base.mode or cm ~= r.base.cm or icc then
				local spec = {}
				for k, v in pairs(r.base) do
					spec[k] = v
				end
				spec.mode = mode
				if cm ~= nil then
					spec.cm = cm
				end
				if icc then
					spec.icc = icc
				end
				pcall(raw_monitor, spec)
			end
		end
	end
end

function D.apply()
	local p = D.current()
	local ok, err = pcall(function()
		apply_screens(p)
		local auto_hdr = (not D.hdr_active(p) and (p == "movie" or p == "gaming")) and 2 or 0
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

local function switch(from, to)
	if from == to then
		return
	end
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
		K.night_sync(true)
	end
	hl.dispatch(hl.dsp.reload_config())
end

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
	K.set_state("display_auto", nil)
	K.set_state("display_why", nil)
	switch(from, D.current())
	return name
end

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

function kuwai.display_profiles()
	local out = {}
	for _, m in ipairs(hl.get_monitors() or {}) do
		local path = K.home .. "/.local/share/kuwai-data/icc/" .. D.icc_name(m) .. ".icc"
		out[#out + 1] = m.name .. "\t" .. (m.description or "") .. "\t" .. path .. "\t" .. (K.exists(path) and "yes" or "no")
	end
	return table.concat(out, "\n")
end

function kuwai.display_hdr(val)
	if val == nil then
		if D.hdr_active() then
			return "on"
		end
		return D.hdr_choice() and "paused" or "off"
	end
	local want
	if val == true or val == "on" then
		want = true
	elseif val == false or val == "off" then
		want = false
	elseif val == "toggle" then
		want = not D.hdr_choice()
	else
		K.notify("kuwai: display_hdr expects on, off or toggle", 2500, "error")
		return kuwai.display_hdr()
	end
	if want == D.hdr_choice() then
		return kuwai.display_hdr()
	end
	K.set_state("display_hdr", want and "on" or nil)
	hl.dispatch(hl.dsp.reload_config())
	return kuwai.display_hdr()
end

function kuwai.displays()
	return table.concat(D.list, " ")
end

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

function D.battery_auto()
	if K.feature("auto_display") and K.feature("auto_battery") and K.ac_online and K.ac_online() == false then
		return "battery", "On battery"
	end
end

local hdr_forced = false
local function preset_wants_hdr()
	local p = D.current()
	return D.hdr_active(p) or p == "movie" or p == "gaming"
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
	hdr_forced = false
	D.auto(preset, why)
end

local function front(hint)
	local active = hl.get_active_window()
	if hint and (is_video(hint) or is_game(hint)) then
		if fullscreen(hint) or not active or active.address == hint.address then
			return hint
		end
	end
	return active
end

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
			hdr_arm(true)
			return
		end
		if not video_fs and K.state["display_auto"] ~= "movie" and not colour and external_player(gone) then
			local why = (active and (active.class or active.initial_class)) or "video"
			schedule("movie", 1200, function()
				if D.choice() ~= "everyday" or find_colour() then
					return
				end
				local fs = any_such(function(w)
					return is_video(w) and fullscreen(w)
				end)
				if fs or not is_video(hl.get_active_window()) or not external_player() then
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
	if K.state["display_auto"] == "movie" and external_player(gone) then
		if pending == "idle" then
			cancel()
		end
		return
	end
	local back = D.battery_auto()
	if not hdr_forced and K.state["display_auto"] == back then
		return
	end
	schedule("idle", 2500, function()
		if find_colour() then
			go("accurate", find_colour())
			return
		end
		if (is_video(hl.get_active_window()) and external_player()) or any_such(function(w)
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
	D.reconcile()
end)

kuwai.display_module = D
return D
