// The offscreen fixture has no Wayland idle-inhibit surface.
pragma Singleton
import QtQml
QtObject {
    property bool on: false
    function toggle() { on = !on; }
}
