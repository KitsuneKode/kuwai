-- No compositor: the actual automation module emits only collected commands.
package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path
local commands, timers, handlers, state
local function setup(enabled)
    commands, timers, handlers, state = {}, {}, {}, {}
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
        state=state, set_state=function(k, v) state[k]=v end,
    }
    dofile('hypr/kuwai/automation.lua')
end
setup(true)
assert(state.sharing=='0','initial share state must be written as 0')
kuwai.privacy_resync()
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-off','idle resync must acknowledge known-not-sharing')
assert(state.sharing=='0','idle resync must keep sharing=0')
handlers['screenshare.state'](true)
table.remove(timers,1)()
assert(state.sharing=='1','engaged share must write sharing=1')
kuwai.privacy_resync()
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-on','restart must recover active share')
assert(state.sharing=='1','active resync must keep sharing=1')
handlers['screenshare.state'](false)
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-off','end must release share state')
assert(state.sharing=='0','end must reset sharing=0')
setup(false)
kuwai.privacy_resync()
assert(commands[#commands]=='/fixture/bin/kuwai notifs mute-off','disabled automation must acknowledge deliberate opt-out')
assert(state.sharing=='0','disabled resync must write sharing=0')
print('privacy handshake fixtures pass')
