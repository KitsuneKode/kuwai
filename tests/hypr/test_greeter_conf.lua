-- greeter/hyprland.lua reads your screens and keyboard from a file you can
-- write (home/.config/kuwai-greeter.conf, by greeter/sync). It runs as the
-- greeter, before a password is typed: the file is data, checked, and on
-- anything unexpected ignored whole (preferred modes, a US keyboard).
-- No compositor: hl is a recorder; the file is served from a string.
local CONF = "/var/lib/kuwai-greeter/home/.config/kuwai-greeter.conf"
local real_open = io.open
local XKB = real_open("/usr/share/X11/xkb/symbols/us", "r")
if XKB then XKB:close() end

local function load(text)
	local monitors, config, ran = {}, nil, {}
	_G.hl = {
		monitor = function(m) monitors[#monitors + 1] = m end,
		config = function(c) config = c end,
		env = function() end,
		on = function() end,
		bind = function() end,
		exec_cmd = function() end,
		dsp = { exec_cmd = function() return {} end },
	}
	io.open = function(path, mode)
		if path == CONF then
			if text == nil then return nil end
			local served = false
			return { read = function() if served then return nil end served = true return text end, close = function() end }
		end
		return real_open(path, mode)
	end
	local exec, popen = os.execute, io.popen
	os.execute = function(...) ran[#ran + 1] = { ... } end
	io.popen = function(...) ran[#ran + 1] = { ... } end
	local ok, err = pcall(dofile, "greeter/hyprland.lua")
	io.open, os.execute, io.popen = real_open, exec, popen
	assert(ok, err)
	assert(#ran == 0, "the greeter's config ran a command")
	assert(config and config.input, "no input config")
	return monitors, config.input
end

local function defaults(text, why)
	local m, input = load(text)
	assert(#m == 1 and m[1].output == "" and m[1].mode == "preferred" and m[1].position == "auto" and m[1].scale == 1,
		why .. ": expected only the preferred-mode rule, got " .. #m)
	assert(input.kb_layout == "us" and input.kb_variant == "" and input.kb_options == "", why .. ": keyboard not the default")
end

local GOOD = table.concat({
	"# Written by greeter/sync",
	"kb_layout=us",
	"monitor=2560x1440@200;1920;0;1;0;10;srgb;Acer Technologies XV272U X1 7626041D84232",
	"monitor=2560x1440@165.003;0;360;1.333333;0;8;srgb;California Institute of Technology 0x1509",
}, "\n") .. "\n"

-- What sync writes on the author's machine is the old hard-coded setup.
do
	local m, input = load(GOOD)
	assert(#m == 3, "two screens and the fallback")
	assert(m[1].output == "desc:Acer Technologies XV272U X1 7626041D84232")
	assert(m[1].mode == "2560x1440@200.000" and m[1].position == "1920x0" and m[1].scale == 1)
	assert(m[1].bitdepth == 10 and m[1].cm == "srgb", "10-bit and its colour carried to the login screen")
	assert(m[2].output == "desc:California Institute of Technology 0x1509" and m[2].mode == "2560x1440@165.003")
	assert(m[2].position == "0x360" and math.abs(m[2].scale - 4 / 3) < 1e-5 and m[2].bitdepth == nil)
	assert(m[3].output == "" and m[3].mode == "preferred")
	assert(input.kb_layout == "us")
end

defaults(nil, "missing file")
defaults("", "empty file")
defaults("\0\0\0", "binary")

-- Descriptions with quotes, brackets, newlines and Lua or shell syntax.
defaults('monitor=1920x1080@60;0;0;1;0;8;;Dell "]] os.execute("id") --[[\n', "quotes and long brackets")
defaults("monitor=1920x1080@60;0;0;1;0;8;;Dell [U2720Q]\n", "square brackets")
defaults("monitor=1920x1080@60;0;0;1;0;8;;Dell\nos.execute('id')\n", "a newline splitting the description")
defaults("monitor=1920x1080@60;0;0;1;0;8;;Dell U2720Q\r\n", "a carriage return")
defaults("monitor=1920x1080@60;0;0;1;0;8;;$(reboot)\n", "command substitution")
defaults("monitor=1920x1080@60;0;0;1;0;8;;Dell, Inc.\n", "a comma (a separator in Hyprland's own rules)")
defaults("monitor=1920x1080@60;0;0;1;0;8;;" .. string.rep("A", 121) .. "\n", "a 121-character description")
defaults("monitor=1920x1080@60;0;0;1;0;8;;\n", "an empty description")
defaults("monitor=1920x1080@60;0;0;1;0;8;srgb\n", "a field missing")
defaults("monitor=1920x1080@60;0;0;1;0;8;hdr;Dell U2720Q\n", "a colour mode not on the list")

-- Layouts with shell or Lua metacharacters, and other keyboard tricks.
defaults("kb_layout=us;rm -rf ~\n", "shell metacharacters")
defaults("kb_layout=us$(id)\n", "command substitution in a layout")
defaults('kb_layout=us"..os.execute("id").."\n', "Lua in a layout")
defaults("kb_layout=../../../../etc/passwd\n", "a path as a layout")
defaults("kb_layout=US\n", "upper case")
defaults("kb_layout=\n", "an empty layout")
defaults("kb_layout=us\nkb_layout=de\n", "a key twice")
defaults("kb_variant=nodeadkeys\n", "a variant without a layout")
defaults("kb_options=grp:alt_shift_toggle;x\n", "options with a semicolon")
defaults("kb_layout=" .. string.rep("us,", 30) .. "us\n", "a 92-character layout")
defaults("kb_layout=us\nkb_model=pc105\n", "a key that isn't on the list")
defaults("KB_LAYOUT=us\n", "a key in capitals")
defaults("kb_layout us\n", "a line without =")

-- Huge, odd and non-decimal numbers.
defaults("monitor=99999999999x1440@60;0;0;1;0;8;;Dell U2720Q\n", "a huge width")
defaults("monitor=1920x1080@100000;0;0;1;0;8;;Dell U2720Q\n", "a huge refresh rate")
defaults("monitor=1920x1080@60;0;0;1e308;0;8;;Dell U2720Q\n", "an exponent")
defaults("monitor=1920x1080@60;0;0;inf;0;8;;Dell U2720Q\n", "infinity")
defaults("monitor=1920x1080@60;0;0;nan;0;8;;Dell U2720Q\n", "not a number")
defaults("monitor=1920x1080@60;0x10;0;1;0;8;;Dell U2720Q\n", "hex")
defaults("monitor=1920x1080@60;0;0;-1;0;8;;Dell U2720Q\n", "a negative scale")
defaults("monitor=1920x1080@60;0;0;9;0;8;;Dell U2720Q\n", "a scale above 4")
defaults("monitor=1920x1080@60;999999;0;1;0;8;;Dell U2720Q\n", "a position off the map")
defaults("monitor=1920x1080@60;0;0;1;8;8;;Dell U2720Q\n", "a transform above 7")
defaults("monitor=1920x1080@60;0;0;1;0;9;;Dell U2720Q\n", "9-bit")
defaults("monitor=1920x1080@60;0;0;1;0;12;;Dell U2720Q\n", "12-bit")

-- Too much of it.
local many = {}
for i = 1, 9 do many[#many + 1] = "monitor=1920x1080@60;" .. (i * 1920) .. ";0;1;0;8;;Screen " .. i end
defaults(table.concat(many, "\n") .. "\n", "nine screens")
defaults(string.rep("# padding\n", 33), "33 lines")
defaults("kb_layout=us\n" .. string.rep("#", 8200) .. "\n", "over 8 KiB")

-- One bad line spoils the file: the good monitor before it isn't used either.
defaults(GOOD .. "monitor=1920x1080@60;0;0;1;0;8;;Dell \"x\"\n", "a bad line after good ones")

-- A layout xkb knows, with its variant and switch, does reach the config.
if XKB then
	local m, input = load("kb_layout=us,de\nkb_variant=,nodeadkeys\nkb_options=grp:alt_shift_toggle\n")
	assert(#m == 1 and input.kb_layout == "us,de" and input.kb_variant == ",nodeadkeys" and input.kb_options == "grp:alt_shift_toggle")
	defaults("kb_layout=zz\n", "a layout xkb doesn't have")
	defaults("kb_layout=us,zz\n", "one layout xkb doesn't have")
end

print("greeter conf fixtures pass")
