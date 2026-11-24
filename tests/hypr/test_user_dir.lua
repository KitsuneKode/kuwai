package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path
local dir = os.tmpname()
os.remove(dir)
assert(os.execute('mkdir -p ' .. dir .. '/kuwai/hypr'))
local entry = dir .. '/kuwai/hypr/hyprland.lua'
assert(os.execute('cp hypr/templates/hyprland.lua ' .. entry))
_G.hl = setmetatable({}, { __index = function() return function() end end })
local real_dofile = dofile
dofile = function() return true end
assert(loadfile(entry))()
dofile = real_dofile
assert(KUWAI_USER_DIR == dir .. '/kuwai/hypr', 'the entry names its own directory: ' .. tostring(KUWAI_USER_DIR))
package.path = 'hypr/?.lua;' .. package.path
package.loaded['kuwai.core'] = nil
local K = require('kuwai.core')
assert(K.user_dir == dir .. '/kuwai/hypr', 'user.lua and monitors.lua are read beside the entry')
assert(K.hypr == K.config_home .. '/hypr', "HyDE's ~/.config/hypr stays where HyDE writes it")
KUWAI_USER_DIR = nil
package.loaded['kuwai.core'] = nil
assert(require('kuwai.core').user_dir == K.config_home .. '/hypr', 'an older entry keeps ~/.config/hypr')
os.execute('rm -rf ' .. dir)
print('user dir fixtures pass')
