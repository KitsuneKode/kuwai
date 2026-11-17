-- No compositor: the actual automation module emits only collected commands.
package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path
local commands, timers, handlers
local function setup(enabled)
    commands, timers, handlers = {}, {}, {}
    _G.kuwai = {}
    _G.hl = {
        dsp = { no_op=function() return {} end },
        exec_cmd=function(command) table.insert(commands,command) end,
        window_rule=function() return {set_enabled=function() end} end,
        layer_rule=function() return {set_enabled=function() end} end,
        on=function(event, fn) handlers[event]=fn end,
        timer=function(fn) table.insert(timers,fn) end,
    }
    package.loaded['kuwai.core'] = {
        bin='/fixture/bin', feature=function(name) return enabled and name=='screenshare_privacy' end,
        config=function() end, read_line=function() return nil end, notify=function() end,
    }
    dofile('hypr/kuwai/automation.lua')
end
setup(true)
kuwai.privacy_resync()
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-off','idle resync must acknowledge known-not-sharing')
handlers['screenshare.state'](true)
table.remove(timers,1)()
kuwai.privacy_resync()
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-on','restart must recover active share')
handlers['screenshare.state'](false)
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-off','end must release share state')
setup(false)
kuwai.privacy_resync()
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-off','disabled automation must acknowledge deliberate opt-out')
print('privacy handshake fixtures pass')
