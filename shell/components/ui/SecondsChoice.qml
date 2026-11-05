// A duration setting as a choice: the values people pick, and Never (0).
//
//   SecondsChoice { key: "idleLockAc"; values: [180, 300, 900, 0] }
import QtQuick
import qs.config
import qs.components

Segmented {
    property string key
    property var values: [60, 120, 300, 600, 0]
    options: values.map(v => ({ id: String(v), label: v === 0 ? "Never" : v < 60 ? v + " s" : v < 3600 ? (v % 60 ? (v / 60).toFixed(1) : v / 60) + " min" : v / 3600 + " h" }))
    current: String(Settings[key])
    onPicked: id => Settings.set(key, Number(id))
}
