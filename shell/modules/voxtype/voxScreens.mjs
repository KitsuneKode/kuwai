// What VoxtypeHost does when the outputs change (tests/shell/vox-screens.test.mjs).
// A screen waking from power-off comes back as a new output of the same name
// (Hyprland removes and re-adds DP-3), and voxtype's UI used to be torn down
// and built again whole: every screen's HUD, the audio bridge, the engine
// picker, meeting controls, all allocating at once on a 6 GB card. Now only
// the HUDs whose output changed are touched.
//
//   have: { name: screenObject } the HUD surfaces there are, by output name
//   now:  [screenObject]         Quickshell.screens after they settled
//   →     { drop: [name], add: [name], keep: [name] }
//         drop: gone, or back as a new output (its surface died with it)
//         add:  new, or back (made again on the new output)
export function plan(have, now) {
    const was = have || {};
    const names = (now || []).map(s => s && s.name).filter(n => n);
    const drop = Object.keys(was).filter(n => {
        const s = (now || []).find(x => x && x.name === n);
        return !s || s !== was[n];
    });
    const add = names.filter(n => !(n in was) || drop.includes(n));
    const keep = names.filter(n => n in was && !drop.includes(n));
    return { drop, add, keep };
}
