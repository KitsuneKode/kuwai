-- kuwai.browsers — browser popups appear in place, floating, instantly.
--
-- A sign-in or wallet popup maps with the same class and the same generic
-- initial title as the browser's main window, so no static rule can tell them
-- apart. But a popup always has a parent: the browser already has a window.
--
--   window.open_early (before rules apply): if this browser already has a
--     window, enable its "<class>-extra" rule — the new window maps floating,
--     centred and without animation. The first window maps tiled, as normal.
--   window.title: once a floating extra window's title arrives, a known popup
--     (Google sign-in, a wallet) is sized/placed; a normal page (Ctrl+N) is
--     tiled; a still-loading title keeps waiting, up to 10 s.
--
-- Main windows are never touched, so fullscreen video keeps working.
-- (Replaces ~/.config/hypr/zen_popups.py, which did this from a socket
-- watcher with a `hyprctl keyword` round trip per event.)

local K = require("kuwai.core")
local A = require("kuwai.actions")

local B = {}

B.classes = { "zen", "google-chrome", "brave-browser", "chromium", "firefox", "floorp" }

-- title (Lua pattern, lowercased), width, height, placement
B.popups = {
	{ "google accounts?", 500, 650, "center" },
	{ "metamask", 420, 620, "topright" },
	{ "phantom", 420, 620, "topright" },
	{ "bitwarden", 420, 620, "topright" },
	{ "1password", 420, 620, "topright" },
	{ "rabby", 420, 620, "topright" },
	{ "keplr", 420, 620, "topright" },
	{ "coinbase", 420, 620, "topright" },
	{ "solflare", 420, 620, "topright" },
	{ "backpack", 420, 620, "topright" },
	{ "^developer tools", 960, 600, "center" },
	{ "^devtools", 960, 600, "center" },
	{ "^library —", 900, 650, "center" },
}

local GENERIC = {
	"^zen browser$", "^zen browser — ", "^about:blank", "^untitled %- ", "^chrome$", "^brave$",
	"^mozilla firefox$", "^new tab", "^$",
}
local WAIT = { "sign ?in", "log ?in", "oauth", "authoriz", "authenticat", "verify" }
local NEVER = "picture.?in.?picture"

local is_browser = {}
for _, c in ipairs(B.classes) do
	is_browser[c] = true
end

local function matches_any(s, list)
	for _, p in ipairs(list) do
		if s:find(p) then
			return true
		end
	end
	return false
end

-- Static parts: one disabled "extra window" rule per browser, DevTools sizes.
local extra = {}
for _, cls in ipairs(B.classes) do
	local ok, h = pcall(hl.window_rule, {
		name = cls .. "-extra",
		match = {
			class = "^(" .. cls .. ")$",
			initial_title = "negative:^(Picture.in.[Pp]icture.*|Developer Tools.*|DevTools.*)$",
		},
		float = true,
		center = true,
		no_anim = true,
		enabled = false,
	})
	if ok and h then
		extra[cls] = h
		pcall(function()
			h:set_enabled(false)
		end)
	else
		K.err("browsers: rule for " .. cls .. ": " .. tostring(h))
	end
end

pcall(hl.window_rule, {
	name = "browser-devtools",
	match = { class = "^(zen|firefox|floorp|google-chrome|brave-browser|chromium)$", initial_title = "^(Developer Tools|DevTools)(.*)$" },
	float = true,
	center = true,
	size = "960 600",
})
-- The glide spring resizes a window on every frame of a fullscreen toggle.
-- A browser lays the page out again at each size, and it is already playing
-- its own toolbar animation, so the two run together and the transition
-- stutters. Snap the compositor's geometry. The browser's animation is the
-- one that should be seen. Popups above already opt out on their own.
pcall(hl.window_rule, {
	name = "browser-no-geometry-anim",
	match = { class = "^(zen|google-chrome|brave-browser|chromium|firefox|floorp)$" },
	no_anim = true,
})

-- Dynamic part ----------------------------------------------------------------
local pending = {} -- address -> true while we wait for a meaningful title

local function others_of(cls, except)
	for _, w in ipairs(hl.get_windows() or {}) do
		if w.class == cls and w.address ~= except then
			return true
		end
	end
	return false
end

local function style(w, width, height, where)
	local s = "address:" .. w.address
	hl.dispatch(hl.dsp.window.tag({ window = s, tag = "+browser-popup" }))
	if where == "topright" or not w.floating then
		if not w.floating then
			hl.dispatch(hl.dsp.window.float({ window = s, action = "enable" }))
		end
		local u = A.usable(w.monitor or hl.get_active_monitor())
		local x = (where == "topright") and (u.mx + u.mw - width - 40) or (u.mx + math.floor((u.mw - width) / 2))
		local y = (where == "topright") and (u.my + 120) or (u.my + math.floor((u.mh - height) / 2))
		hl.dispatch(hl.dsp.window.resize({ window = s, x = width, y = height }))
		hl.dispatch(hl.dsp.window.move({ window = s, x = x, y = y }))
	end
end

local function decide(w)
	if not w or not pending[w.address] then
		return
	end
	local t = (w.title or ""):lower()
	if t:find(NEVER) then
		pending[w.address] = nil
		return
	end
	for _, p in ipairs(B.popups) do
		if t:find(p[1]) then
			pending[w.address] = nil
			style(w, p[2], p[3], p[4])
			return
		end
	end
	if matches_any(t, GENERIC) or matches_any(t, WAIT) then
		return -- still loading, or mid-redirect in an OAuth flow
	end
	pending[w.address] = nil
	if w.floating then -- Ctrl+N: a real page, give it back to the layout
		hl.dispatch(hl.dsp.window.float({ window = "address:" .. w.address, action = "disable" }))
	end
end

hl.on("window.open_early", function(w)
	if w and is_browser[w.class] and extra[w.class] then
		extra[w.class]:set_enabled(others_of(w.class, w.address))
	end
end)

hl.on("window.open", function(w)
	if not (w and is_browser[w.class] and w.floating) then
		return
	end
	if not (extra[w.class] and extra[w.class]:is_enabled()) then
		return -- floated by some other rule (DevTools, PiP…): not ours
	end
	pending[w.address] = true
	local addr = w.address
	decide(w)
	if pending[addr] then
		hl.timer(function()
			if not pending[addr] then
				return
			end
			pending[addr] = nil
			local cur = hl.get_window("address:" .. addr)
			if cur and cur.floating and matches_any((cur.title or ""):lower(), GENERIC) then
				hl.dispatch(hl.dsp.window.float({ window = "address:" .. addr, action = "disable" }))
			end
		end, { timeout = 10000, type = "oneshot" })
	end
end)

hl.on("window.title", function(w)
	if w and pending[w.address] then
		decide(w)
	end
end)

hl.on("window.destroy", function(w)
	if w then
		pending[w.address] = nil
	end
end)

return B
