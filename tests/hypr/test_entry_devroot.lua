local tmp = os.tmpname()
os.remove(tmp)
local function sh(c) assert(os.execute(c)) end
sh("mkdir -p " .. tmp .. "/home/.local/state/kuwai " .. tmp .. "/src/kuwai/hypr " .. tmp .. "/home/Projects/kuwai/hypr")
local function write(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
write(tmp .. "/src/kuwai/hypr/init.lua", "PICKED = 'recorded'\n")
write(tmp .. "/home/Projects/kuwai/hypr/init.lua", "PICKED = 'projects'\n")
write(tmp .. "/home/.local/state/kuwai/channel", "dev\n")
write(tmp .. "/home/.local/state/kuwai/dev-root", tmp .. "/src/kuwai\n")
local function pick()
	local p = io.popen("env -i HOME=" .. tmp .. "/home lua -e \"dofile('hypr/templates/hyprland.lua'); print(KUWAI_ROOT, PICKED)\" 2>&1")
	local out = p:read("*a"); p:close(); return out
end
local out = pick()
assert(out:find(tmp .. "/src/kuwai", 1, true) and out:find("recorded", 1, true), "the dev channel loads the recorded clone: " .. out)
os.remove(tmp .. "/home/.local/state/kuwai/dev-root")
out = pick()
assert(out:find("projects", 1, true), "without a record it falls back to ~/Projects: " .. out)
sh("rm -rf " .. tmp)
print("entry dev-root fixtures pass")
