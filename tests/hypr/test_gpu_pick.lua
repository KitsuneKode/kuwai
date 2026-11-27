package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path
local function pick(files, mode)
    local env = {}
    _G.hl = { env = function(k, v) env[k] = v end }
    package.loaded['kuwai.core'] = {
        state = { gpu = mode }, config = function() end,
        read_line = function(p) return files[p] end,
        exists = function(p) return files[p] ~= nil or p:find('nvidia_drv_video') ~= nil end,
    }
    local real_print = print
    print = function() end
    local G = dofile('hypr/kuwai/gpu.lua')
    print = real_print
    return G.primary, env
end
local function machine(t)
    local f = {
        ['/sys/class/drm/card0/device/vendor'] = '0x10de',
        ['/sys/class/drm/card1/device/vendor'] = '0x8086',
        ['/sys/class/drm/card1-eDP-1/status'] = 'connected',
        ['/sys/class/power_supply/ACAD/online'] = t.ac and '1' or '0',
        ['/proc/uptime'] = tostring(t.up or 3600) .. ' 1000.0',
    }
    if t.external then f['/sys/class/drm/card0-DP-3/status'] = 'connected' end
    return f
end
assert(pick(machine{ ac = true, up = 3600 }) == 'intel', 'laptop screen alone on AC: Intel renders the screen it drives')
assert(pick(machine{ ac = false }) == 'intel', 'on battery: Intel')
assert(pick(machine{ external = true }) == 'nvidia', 'a screen on NVIDIA: NVIDIA renders')
assert(pick(machine{ ac = true, up = 20 }) == 'nvidia', 'just booted on AC: NVIDIA, the dock screen may not have answered yet')
assert(pick(machine{ ac = true, up = 3600 }, 'nvidia') == 'nvidia', 'KUWAI_GPU/state nvidia still wins')
local _, env = pick(machine{ ac = true, up = 3600 })
assert(env.AQ_DRM_DEVICES == '/dev/dri/card1:/dev/dri/card0', 'Intel first in AQ_DRM_DEVICES')
print('gpu pick fixtures pass')
