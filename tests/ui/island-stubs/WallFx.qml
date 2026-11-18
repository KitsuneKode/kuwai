// Wallpaper effects require a compositor; the capsule fixture does not use them.
pragma Singleton
import QtQml
QtObject {
    function play(path, start) { if (start) start(); }
}
