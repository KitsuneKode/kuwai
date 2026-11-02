-- kuwai.theme — HyDE themes and wallbash colours, read straight from the
-- hyprlang files HyDE's switcher writes:
--
--   ~/.config/hypr/themes/colors.conf   $wallbash_* colours (wallpaper palette)
--   ~/.config/hypr/themes/theme.conf    the theme's general/decoration/group
--
-- HyDE's switcher ends with `hyprctl reload`, which re-runs this, so switching
-- themes from the island (Super+Shift+T) or HyDE keeps working without HyDE's
-- Lua runtime or hyq. Only plain options are taken: rules, exec, source,
-- animations and anything unknown are skipped (kuwai owns motion and rules).
-- Each value is coerced to the type the live option has, so a theme saying
-- `blur:enabled = 1` lands as a boolean.

local K = require("kuwai.core")

local T = { colors = {}, vars = {}, applied = 0, skipped = {} }

local THEME = K.hypr .. "/themes/theme.conf"
local COLORS = K.hypr .. "/themes/colors.conf"
local SECTIONS = { general = true, decoration = true, group = true, misc = false }

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_comment(line)
	-- hyprlang: '#' starts a comment, '##' is a literal '#'
	local out = line:gsub("##", "\1"):gsub("#.*$", ""):gsub("\1", "#")
	return out
end

local function subst(v)
	return (v:gsub("%$([%w_]+)", function(name)
		return T.vars[name] or ("$" .. name)
	end))
end

-- "rgba(..) rgba(..) 45deg" -> gradient table; a single colour stays a string.
local function parse_color(v)
	local colors, angle = {}, nil
	for tok in v:gmatch("%S+%b()") do
		colors[#colors + 1] = tok
	end
	if #colors == 0 then
		for tok in v:gmatch("%S+") do
			if tok:match("^0x%x+$") or tok:match("^%x%x%x%x%x%x%x?%x?$") then
				colors[#colors + 1] = tok
			end
		end
	end
	angle = tonumber(v:match("(%-?[%d%.]+)deg"))
	if #colors == 0 then
		return nil
	end
	if #colors == 1 and not angle then
		return colors[1]
	end
	return { colors = colors, angle = angle or 0 }
end

local function coerce(key, raw)
	local cur = K.get(key)
	if cur == nil then
		return nil, "unknown option"
	end
	local v = trim(raw)
	local t = type(cur)
	if key:find("%.col%.") or key:find("%.color") or key:match("col%.[%w_]+$") then
		local c = parse_color(v)
		if c then
			return c
		end
	end
	if t == "boolean" then
		local l = v:lower()
		if l == "true" or l == "yes" or l == "on" or l == "1" then
			return true
		end
		if l == "false" or l == "no" or l == "off" or l == "0" then
			return false
		end
		return nil, "not a boolean: " .. v
	elseif t == "number" then
		local n = tonumber(v)
		if n == nil then
			return nil, "not a number: " .. v
		end
		return n
	elseif t == "table" then
		-- css gaps ("5" or "5 10 5 10"), vec2 ("0 6"), gradients
		local n = tonumber(v)
		if n then
			return n
		end
		local c = parse_color(v)
		if c then
			return c
		end
		return v
	end
	return v
end

local function parse_vars(path)
	local s = K.read(path)
	if not s then
		return false
	end
	for line in s:gmatch("[^\n]+") do
		local name, val = strip_comment(line):match("^%s*%$([%w_]+)%s*=%s*(.-)%s*$")
		if name then
			T.vars[name] = subst(val)
			if name:match("^wallbash_") then
				T.colors[name:sub(10)] = T.vars[name]
			end
		end
	end
	return true
end

-- Returns a flat { ["decoration.blur.size"] = 5, ... } table.
local function parse_theme(path)
	local s = K.read(path)
	if not s then
		return nil
	end
	local out, stack = {}, {}
	for raw in (s .. "\n"):gmatch("([^\n]*)\n") do
		local line = trim(strip_comment(raw))
		if line == "" or line:match("^/%*") then
			-- skip
		elseif line:match("^[%w_%.:%-]+%s*{$") then
			stack[#stack + 1] = (line:match("^([%w_%.:%-]+)"):gsub(":", "."))
		elseif line == "}" then
			stack[#stack] = nil
		else
			local name, val = line:match("^%$([%w_]+)%s*=%s*(.-)$")
			if name then
				T.vars[name] = subst(val)
			else
				local key
				key, val = line:match("^([%w_%.:%-]+)%s*=%s*(.-)$")
				if key then
					local full = table.concat(stack, ".")
					full = (full ~= "" and (full .. ".") or "") .. key:gsub(":", ".")
					local section = full:match("^([%w_]+)")
					if SECTIONS[section] then
						out[full] = subst(val)
					end
				end
			end
		end
	end
	return out
end

-- Palette only (cheap; safe to call more than once).
function T.load_colors()
	if not T._colors_loaded then
		T._colors_loaded = parse_vars(COLORS)
	end
	return T.colors
end

function T.apply()
	T.load_colors()
	local flat = parse_theme(THEME)
	if not flat then
		return T
	end
	-- HyDE themes sometimes say rounding:power; Hyprland calls it rounding_power.
	if flat["decoration.rounding.power"] then
		flat["decoration.rounding_power"] = flat["decoration.rounding.power"]
		flat["decoration.rounding.power"] = nil
	end
	-- Shadows used to be stripped by HyDE's sanitizer; themes still carry them.
	local keys = {}
	for k in pairs(flat) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local v, why = coerce(key, flat[key])
		if v == nil then
			T.skipped[#T.skipped + 1] = key .. " (" .. tostring(why) .. ")"
		else
			local ok = pcall(hl.config, { [key] = v })
			if ok then
				T.applied = T.applied + 1
			else
				T.skipped[#T.skipped + 1] = key .. " (rejected)"
			end
		end
	end
	local rc = K.read(K.state_home .. "/hyde/staterc") or ""
	T.name = T.vars.HYDE_THEME or rc:match('HYDE_THEME="?([^"\n]+)"?') or "?"
	return T
end

-- Wallbash palette as rgba() strings: T.rgba("pry1", "ee")
function T.rgba(name, alpha)
	local hex = T.colors[name]
	if not hex or not hex:match("^%x%x%x%x%x%x$") then
		return nil
	end
	return "rgba(" .. hex .. (alpha or "ff") .. ")"
end

return T
