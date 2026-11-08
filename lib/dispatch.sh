# lib/dispatch.sh (was ~/Scripts/lib-dispatch.sh) — dual-mode Hyprland dispatcher calls.
#
# Classic `hyprctl dispatch <name> <args>` syntax is REMOVED under Lua configs
# (upstream issue HyDE #2114 — the dispatch table is gone). Under the Lua
# config manager, `hyprctl dispatch <expr>` wraps the arg as hl.dispatch(<expr>),
# so dispatchers are invoked as hl.dsp.* builder calls instead.
#
# Detection: `hyprctl eval` exists only with the Lua config manager.
#
# Source this file, then call d_* helpers — each handles both modes:
#   source "$KUWAI_ROOT/lib/dispatch.sh"

_DSP_MODE=""
_dsp_is_lua() {
    if [ -z "$_DSP_MODE" ]; then
        # `hyprctl eval` only ever answers "ok"; `hyprctl repl` returns values.
        if hyprctl repl 'return "__LUA__"' 2>/dev/null | grep -q "__LUA__"; then
            _DSP_MODE=lua
        else
            _DSP_MODE=conf
        fi
    fi
    [ "$_DSP_MODE" = "lua" ]
}

# --- window ops (all take a raw address like 0x5c9f...) ---

d_focus() { # $1 = addr
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.focus({window='address:$1'})" >/dev/null 2>&1
    else
        hyprctl dispatch focuswindow "address:$1" >/dev/null 2>&1
    fi
}

# Clear the maximize flag the scrolling layout puts on solo-column windows.
# Classic fullscreenstate acts on the FOCUSED window only (no selector), so the
# conf path focuses first. The Lua path takes a window arg — no focus steal.
d_unmaximize() { # $1 = addr
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.fullscreen_state({window='address:$1', internal=0, client=0, action='set'})" >/dev/null 2>&1
    else
        hyprctl --batch "dispatch focuswindow address:$1 ; dispatch fullscreenstate 0 0" >/dev/null 2>&1
    fi
}

d_move_pixel() { # $1=addr $2=x $3=y (absolute, global logical coords)
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.move({window='address:$1', x=$2, y=$3})" >/dev/null 2>&1
    else
        hyprctl dispatch movewindowpixel exact "$2" "$3,address:$1" >/dev/null 2>&1
    fi
}

d_resize_pixel() { # $1=addr $2=w $3=h
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.resize({window='address:$1', x=$2, y=$3})" >/dev/null 2>&1
    else
        hyprctl dispatch resizewindowpixel exact "$2" "$3,address:$1" >/dev/null 2>&1
    fi
}

d_float() { # $1=addr — set floating ON
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.float({window='address:$1', action='on'})" >/dev/null 2>&1
    else
        hyprctl dispatch setfloating "address:$1" >/dev/null 2>&1
    fi
}

d_pin() { # $1=addr — toggle (mirrors legacy `pin` semantics)
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.pin({window='address:$1', action='toggle'})" >/dev/null 2>&1
    else
        hyprctl dispatch pin "address:$1" >/dev/null 2>&1
    fi
}

# $1=addr $2=workspace $3=follow(1|0, default 1)
d_movetows() {
    local FL="${3:-1}"
    if _dsp_is_lua; then
        local L=true; [ "$FL" = 0 ] && L=false
        hyprctl dispatch "hl.dsp.window.move({window='address:$1', workspace='$2', follow=$L})" >/dev/null 2>&1
    elif [ "$FL" = 1 ]; then
        hyprctl dispatch movetoworkspace "$2,address:$1" >/dev/null 2>&1
    else
        hyprctl dispatch movetoworkspacesilent "$2,address:$1" >/dev/null 2>&1
    fi
}

d_sendshortcut() { # $1=addr $2=mods $3=key
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.send_shortcut({window='address:$1', mods='$2', key='$3'})" >/dev/null 2>&1
    else
        hyprctl dispatch sendshortcut "$2,$3,address:$1" >/dev/null 2>&1
    fi
}

d_close_window() { # $1 = addr
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.close({window='address:$1'})" >/dev/null 2>&1
    else
        hyprctl dispatch closewindow "address:$1" >/dev/null 2>&1
    fi
}

# --- everything else ---

d_killactive() { # graceful close of active window (lua `kill` is SIGKILL)
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.window.close()" >/dev/null 2>&1
    else
        hyprctl dispatch killactive "" >/dev/null 2>&1
    fi
}

d_exec_float() { # $1 = command — long-bracket quoting survives embedded quotes
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.exec_cmd([==[$1]==], {float=true})" >/dev/null 2>&1
    else
        hyprctl dispatch exec "[float] $1" >/dev/null 2>&1
    fi
}

d_layoutmsg() { # $1 = layout message
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.layout([==[$1]==])" >/dev/null 2>&1
    else
        hyprctl dispatch layoutmsg "$1" >/dev/null 2>&1
    fi
}

d_focus_monitor() { # $1 = monitor name/id
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.focus({monitor='$1'})" >/dev/null 2>&1
    else
        hyprctl dispatch focusmonitor "$1" >/dev/null 2>&1
    fi
}

d_ws_to_monitor() { # $1 = workspace, $2 = monitor
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.workspace.move({workspace='$1', monitor='$2'})" >/dev/null 2>&1
    else
        hyprctl dispatch moveworkspacetomonitor "$1" "$2" >/dev/null 2>&1
    fi
}

d_workspace() { # $1 = workspace to focus
    if _dsp_is_lua; then
        hyprctl dispatch "hl.dsp.focus({workspace='$1'})" >/dev/null 2>&1
    else
        hyprctl dispatch workspace "$1" >/dev/null 2>&1
    fi
}
