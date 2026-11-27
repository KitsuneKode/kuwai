package.path = 'hypr/?.lua;hypr/?/init.lua;' .. package.path

local function run(state, keys)
    local esc, execs = nil, {}
    _G.hl = {
        exec_cmd = function(cmd) execs[#execs + 1] = cmd end,
        dispatch = function() end,
        dsp = { no_op = function() end, submap = function() end, global = function(n) return n end },
    }
    local files = { ['/run/voxtype/state'] = state, ['/run/kuwai/keys'] = keys }
    package.loaded['kuwai.core'] = {
        home = '/fixture', runtime = '/run', voxtype_scripts = '/s/', bin = '/kuwai/bin',
        has = function() return true end,
        exists = function() return true end,
        read_line = function(path) return files[path] end,
        bind = function(keys_, _, fn) if keys_ == 'Escape' then esc = fn end end,
        bind_hold = function() end,
        group = function() end,
        submap = function() end,
    }
    dofile('hypr/kuwai/voxtype.lua')
    assert(esc, 'Escape is bound')
    return esc(), execs
end

local r, execs = run('recording', 'panel')
assert(type(r) == 'table' and r.ok == false and #execs == 0, 'a kuwai panel has the keys: Esc is the panel\'s, dictation untouched')
r, execs = run('recording', '')
assert(r == nil and #execs == 1 and execs[1]:find('voxtype-cancel.sh', 1, true), 'dictating, no panel: Esc goes to the cancel (twice to cancel)')
r, execs = run('transcribing', nil)
assert(r == nil and #execs == 1, 'transcribing counts as dictating')
r, execs = run('idle', '')
assert(type(r) == 'table' and r.ok == false and #execs == 0, 'not dictating: Esc passes through')
print('test_voxtype_escape: ok')
