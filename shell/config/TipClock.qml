pragma Singleton
// One clock for every tooltip (components/Tip): how many are showing and
// when the last one went. The first tip waits Theme.tipMs; while one shows,
// or within 400 ms of one closing, the next shows at once, so moving along a
// row of marks reads instantly (Emil Kowalski's rule; vibrant.design's
// tooltip-delay study shows the same).
import Quickshell

Singleton {
    property int showing: 0
    property real lastHidden: 0
    function warm() { return showing > 0 || Date.now() - lastHidden < 400; }
}
