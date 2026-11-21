pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool unit: Quickshell.env("KUWAI_SHELL_UNIT") === "1"
    readonly property string home: Quickshell.env("HOME") || "/"

    function command(cmd, dir) {
        if (!unit) return cmd;
        return ["systemd-run", "--user", "--collect", "--quiet", "--slice=app.slice",
                "--description=kuwai: opened from the shell",
                "--property=StandardOutput=null", "--property=StandardError=null",
                "--working-directory=" + (dir || home), "--"].concat(cmd);
    }

    function run(cmd, dir) {
        if (!cmd || !cmd.length) return;
        const argv = Array.from(cmd, String);
        if (unit || !dir) Quickshell.execDetached(command(argv, dir));
        else Quickshell.execDetached({ command: argv, workingDirectory: dir });
    }

    function open(target) {
        if (target) run(["xdg-open", String(target)]);
    }

    function launch(entry) {
        if (entry && entry.command && entry.command.length) run(entry.command, entry.workingDirectory || "");
    }
}
