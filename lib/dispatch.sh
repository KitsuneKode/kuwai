# shellcheck shell=bash

_DSP_MODE=""
_dsp_lua_string() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    printf '"%s"' "$value"
}
_dsp_number() {
    [[ $1 =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 2
    printf '%s' "$1"
}
_dsp_is_lua() {
    if [ -z "$_DSP_MODE" ]; then
        if hyprctl repl 'return "__LUA__"' 2>/dev/null | grep -q "__LUA__"; then
            _DSP_MODE=lua
        else
            _DSP_MODE=conf
        fi
    fi
    [ "$_DSP_MODE" = "lua" ]
}

d_focus() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.focus({window=$(_dsp_lua_string "address:$1")})" >/dev/null 2>&1
    else
        hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
    fi
}

d_unmaximize() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.fullscreen_state({window=$(_dsp_lua_string "address:$1"), internal=0, client=0, action='set'})" >/dev/null 2>&1
    else
        hyprctl --batch "dispatch focuswindow address:$1 ; dispatch fullscreenstate 0 0" >/dev/null 2>&1
    fi
}

d_move_pixel() {
    local x y
    x=$(_dsp_number "$2") || return 2
    y=$(_dsp_number "$3") || return 2
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.move({window=$(_dsp_lua_string "address:$1"), x=$x, y=$y})" >/dev/null 2>&1
    else
        hyprctl dispatch movewindowpixel exact "$2" "$3,address:$1" >/dev/null 2>&1
    fi
}

d_resize_pixel() {
    local x y
    x=$(_dsp_number "$2") || return 2
    y=$(_dsp_number "$3") || return 2
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.resize({window=$(_dsp_lua_string "address:$1"), x=$x, y=$y})" >/dev/null 2>&1
    else
        hyprctl dispatch resizewindowpixel exact "$2" "$3,address:$1" >/dev/null 2>&1
    fi
}

d_float() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.float({window=$(_dsp_lua_string "address:$1"), action='on'})" >/dev/null 2>&1
    else
        hyprctl dispatch setfloating "address:$1" >/dev/null 2>&1
    fi
}

d_pin() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.pin({window=$(_dsp_lua_string "address:$1"), action='toggle'})" >/dev/null 2>&1
    else
        hyprctl dispatch pin "address:$1" >/dev/null 2>&1
    fi
}

d_movetows() {
    local FL="${3:-1}"
    if _dsp_is_lua; then
        local L=true; [ "$FL" = 0 ] && L=false
        hyprctl dispatch "hl.dsp.window.move({window=$(_dsp_lua_string "address:$1"), workspace=$(_dsp_lua_string "$2"), follow=$L})" >/dev/null 2>&1
    elif [ "$FL" = 1 ]; then
        hyprctl dispatch movetoworkspace "$2,address:$1" >/dev/null 2>&1
    else
        hyprctl dispatch movetoworkspacesilent "$2,address:$1" >/dev/null 2>&1
    fi
}

d_sendshortcut() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.send_shortcut({window=$(_dsp_lua_string "address:$1"), mods=$(_dsp_lua_string "$2"), key=$(_dsp_lua_string "$3")})" >/dev/null 2>&1
    else
        hyprctl dispatch sendshortcut "$2,$3,address:$1" >/dev/null 2>&1
    fi
}

d_close_window() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.close({window=$(_dsp_lua_string "address:$1")})" >/dev/null 2>&1
    else
        hyprctl dispatch closewindow "address:$1" >/dev/null 2>&1
    fi
}

d_killactive() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.close()" >/dev/null 2>&1
    else
        hyprctl dispatch killactive "" >/dev/null 2>&1
    fi
}

d_exec_float() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.exec_cmd($(_dsp_lua_string "$1"), {float=true})" >/dev/null 2>&1
    else
        hyprctl dispatch exec "[float] $1" >/dev/null 2>&1
    fi
}

d_layoutmsg() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.layout($(_dsp_lua_string "$1"))" >/dev/null 2>&1
    else
        hyprctl dispatch layoutmsg "$1" >/dev/null 2>&1
    fi
}

d_focus_monitor() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.focus({monitor=$(_dsp_lua_string "$1")})" >/dev/null 2>&1
    else
        hyprctl dispatch focusmonitor "$1" >/dev/null 2>&1
    fi
}

d_ws_to_monitor() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.workspace.move({workspace=$(_dsp_lua_string "$1"), monitor=$(_dsp_lua_string "$2")})" >/dev/null 2>&1
    else
        hyprctl dispatch moveworkspacetomonitor "$1" "$2" >/dev/null 2>&1
    fi
}

d_workspace() {
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.focus({workspace=$(_dsp_lua_string "$1")})" >/dev/null 2>&1
    else
        hyprctl dispatch workspace "$1" >/dev/null 2>&1
    fi
}
