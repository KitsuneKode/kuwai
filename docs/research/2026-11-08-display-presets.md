# Display quality and proposed presets

Date: 2026-11-08. Recommendations and integration proposal; no live settings changed and no preset controller implemented.

## What was checked

Read the live Hyprland 0.57.1 monitor/options state, both EDIDs, NVIDIA connector properties, Acer DDC capabilities and selected values, the existing brightness controller, shell Display service, compositor modes and night-light automation. Read the playing mpv instance's color properties without changing playback. See [primary-source research](display-quality-primary-sources.md) for external evidence and version qualifications.

| Screen | Observed configuration | Advertised capabilities |
| --- | --- | --- |
| Acer XV272U X1, presently DP-3 | 2560×1440 at 200 Hz, scale 1, XRGB8888, sRGB SDR | 10-bit input, PQ HDR, VRR 48–200 Hz |
| Laptop CSOT MNF601CA1-3, presently eDP-1 | 2560×1440 at 165 Hz, scale 4/3, XRGB8888, sRGB SDR | 8-bit input, no HDR, VRR 60–165 Hz |

EDID describes supported signals; it does not establish native panel bit depth, measured gamut, accuracy, actual peak luminance or successful operation of every bit-depth/refresh combination. The laptop's reported manufacturer name in Hyprland is misleading; EDID identifies CSOT.

The Acer currently reports brightness 40/100, contrast 50/100 and 6500 K through DDC; laptop backlight is 43%. These values are not luminance measurements. Hyprsunset reports 6000 K, so the ordinary desktop currently has a software warmth adjustment in addition to the monitor's white-point selection.

The Acer's EDID advertises about 455.5 cd/m² HDR maximum luminance; this is metadata, not a measured or recommended brightness. Acer's India listing advertises 1440p200, 90% DCI-P3, HDR400 and DisplayPort 1.4: [manufacturer](https://store.acer.com/en-in/acer-nitro-xv272u-x1-27-inch-wqhd-2560-1440-ips-gaming-monitor-200hz-refresh-rate-0-5ms-gtg-amd-freesync-premium-hdr400-2-hdmi-dp-ergostand-2w-2-stereo-speakers-dci-p3-90-black).

## Common baseline

- Keep native resolution on both screens. Keep Acer scale 1 and laptop scale 4/3 for readable UI. Prefer native Wayland applications; the existing XWayland zero-scaling setting avoids compositor magnification, but each application's own HiDPI support still matters.
- Use DisplayPort for the Acer; its current 200 Hz mode is advertised and active. Higher refresh makes motion smoother; it does not increase static color accuracy.
- Use 6500 K/D65 as the starting white point for web and ordinary video. A menu label is not calibration. Leave contrast at the current neutral 50 until clipping tests or measurements justify a change; retain neutral saturation, hue and channel gains.
- For an unprofiled SDR baseline, pair Hyprland sRGB output with the Acer's actual sRGB gamut-clamp mode if the monitor offers one. A 6500 K preset alone does not clamp wide gamut to sRGB. Verify the actual monitor menu rather than assuming a named preset's behavior.
- Once measured, load a separate ICC profile for each physical screen and the OSD state used to measure it. Do not use a generic sRGB working-space profile as though it measured the monitor, copy another panel's ICC, or change RGB gains/picture modes behind the profile.
- Use one correct display conversion through the application/compositor pipeline. An application's source/document color management remains necessary; avoid applying the same physical display correction twice. Verify each important creative application, especially XWayland, separately.
- Disable dynamic contrast, black boosts, artificial sharpening, saturation boosts and blue-light adjustments for accurate work. Use default/neutral sharpening if the monitor's scale does not identify which numerical value is neutral. Disable any feature absent from the actual menu only if it exists; do not invent undocumented DDC mappings.
- If the Acer offers overdrive, start with Normal and compare visible trails/overshoot at both high refresh and lower VRR rates; the fastest label is not automatically the cleanest image. Leave VRB/backlight strobing off for the general preset; evaluate it only as a separate competitive-motion preference. Exact X1 menu availability and interaction with Adaptive Sync have not been verified, so do not automate these controls yet.
- Acer HDR menu: Auto is appropriate for a future verified automatic-HDR workflow. During the current fullscreen diagnosis, retain a controlled SDR baseline with computer HDR switching disabled and monitor HDR Off; change one variable at a time. A proper SDR signal should remain SDR when the monitor is in Auto.
- Preserve 8-bit output as the current working fallback. The personal monitor configuration records a previous NVIDIA 10-bit fullscreen primary-plane failure. Qualify 10-bit at 200 Hz separately, then advertised lower refresh modes if necessary. Prefer working RGB 4:4:4 over trading text clarity for chroma subsampling. Input support alone does not prove the combination works.

[Hyprland color/ICC documentation](https://wiki.hypr.land/configuring/core/monitors/colors/) and [ICC display-calibration guidance](https://www.color.org/displaycalibration/) support the color-management approach. A measured profile improves accuracy; it cannot increase native gamut, contrast, resolution or peak brightness.

## Presets worth offering

Brightness numbers below are suggested starting luminances, not standards or measured results. The equivalent slider positions must be found independently for each display, ideally with a meter. Room reflections, ambient light and comfort determine useful adjustments. Do not automatically change a calibrated preset's luminance during color decisions.

| Preset | Color and brightness | Motion / output | Purpose |
| --- | --- | --- | --- |
| Day / Coding | SDR, neutral sRGB presentation; roughly 120–160 cd/m² in an ordinary lit room | Acer 200 Hz; laptop 165 Hz on AC; desktop VRR off | Clear text, comfortable paper-like white, stable brightness |
| Evening / Reading | Same SDR baseline; roughly 80–120 cd/m²; optional warmth | Keep high refresh on AC; VRR off | Comfortable non-color-critical work |
| Night / Comfort | Lower brightness to suit the room; optional 4200–5000 K preference | Stable refresh; no automatic fullscreen tint change | Reading/coding; unsuitable for judging colors |
| Web / Design Accurate | Measured per-screen ICC; D65, sRGB-aware workflow; roughly 100–120 cd/m² in stable moderate light as a starting point | SDR; VRR off; full opacity; shader color conversion; direct scanout off while validating profiles | Websites, UI, social graphics and client color checks |
| Movie / Series SDR | SDR Rec.709-aware player; neutral white; roughly 80–120 cd/m² in dim light | Compare fixed 120 Hz for 24/30/60 fps sources, or verified player/compositor pacing; no frame interpolation by default | Preserve intended tone, color and cadence |
| YouTube / General Media | SDR baseline for SDR material; no forced HDR or vivid processing | Keep 200/165 Hz for general use; consider cadence only if visible judder matters | Mixed browser/video use without constant modesets |
| Gaming / Tear-free | Neutral SDR or genuine HDR after qualification; room-appropriate brightness; no black boost by default | Acer 200 Hz, fullscreen-game VRR; a below-ceiling frame cap as a tested starting point, vsync/pacing checked per game | Smooth motion without visible tearing |
| Gaming / Competitive | Same neutral baseline; brighter shadows only as an intentional visibility tradeoff | 200 Hz; separately test low-latency tearing; no blur-heavy shell effects | Latency prioritized over tear-free presentation |
| SDR Video Editing | Managed Rec.709 monitoring, commonly BT.1886/gamma 2.4 around 100 cd/m² in a dim controlled environment; delivery spec wins | SDR; fixed refresh; calibrated preview; no warmth or dynamic brightness | Editing and checking SDR video, subject to app/pipeline validation |
| HDR Preview | Genuine PQ/BT.2020-tagged source; measured/validated HDR presentation; no invented 1000-nit target | Acer only; verified 10-bit path; automatic return to SDR | Consumer HDR preview; not a qualified HDR mastering monitor |
| Battery | Accurate SDR baseline; lower backlight; laptop 60 Hz is an advertised alternative | Laptop 60 Hz when useful; don't force an available external monitor to a disruptive mode merely because AC disconnected | Power savings |

Fixed 120 Hz can represent 24, 30 and 60 fps at integer refresh multiples on the Acer. It does not fix dropped frames, decoding errors or 23.976/29.97/59.94 timing by itself. Player pacing must be verified. The laptop advertises only 60 and 165 Hz; neither is an integer multiple of 24. VRR minimums are above ordinary 24/30 fps film rates; do not assume VRR automatically solves film cadence. Interpolation is a preference, not recovered source detail.

The quoted sRGB standard has its own reference conditions; practical work brightness here is our recommendation, not a claim that 120 cd/m² is the sRGB standard. See the [ICC sRGB registry](https://registry.color.org/rgb-registry/srgb). SDR video delivery and monitoring need app-specific validation; forcing every desktop surface to gamma 2.4 is not a correct web workflow. Current Hyprland documentation says an applied ICC forces that output's `sdr_eotf` to sRGB, so a compositor gamma selector alone does not establish a Rec.709 reference-monitoring pipeline.

For print, use the actual printer/paper profile and a suitable soft-proof workflow. For P3 delivery, use a P3-aware app and verify the screen's measured coverage; advertising 90% P3 does not mean complete P3 coverage. Neither screen has been measured as a reference monitor.

## Use Hyprland's capabilities deliberately

- Keep color management enabled. Current live state already has it enabled, FP16 internal rendering on its automatic setting and ICC VCGT support enabled. These improve the available pipeline; they do not make an unmeasured display calibrated or turn an 8-bit output into 10-bit.
- Explicitly choose `render.non_shader_cm = 0` for the proposed accuracy baseline, with `render.direct_scanout = 0`, automatic HDR disabled and content-type signaling disabled while holding a known monitor preset. Live `non_shader_cm = 3` means `ignore` in the installed version, and can bypass color-management safeguards; it must not be treated as an accuracy feature. The defaults in the moving wiki differ from this version, so use the [v0.57.1 option definitions](https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/config/values/ConfigValues.cpp#L613) and [fullscreen/scanout implementation](https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/output/Monitor.cpp#L1823). This is a diagnostic/accuracy recommendation, not proof of the reported bug's cause. These render settings apply session-wide, while ICC and monitor settings can be per-output.
- Per-output monitor configuration can keep separate modes, scaling, color presets and ICC profiles for the Acer and laptop. Preserve their arrangement and workspace mapping when applying display changes.
- Use `misc.vrr = 3` or per-output equivalents for fullscreen video/game eligibility, with explicit per-window policy. Desktop/coding should have stable refresh; permit VRR for games, and test video separately for flicker and cadence. Current per-window rules already disable it generally and allow game/video content.
- `render.direct_scanout = 2` means automatic scanout for game content in the current docs, not all fullscreen video. Use it only when qualified; disable it while diagnosing fullscreen color or verifying a calibrated pipeline. Eligibility still depends on format, overlays and hardware support.
- `render.send_content_type` tells the display what kind of content is being shown. Hyprland explicitly warns it can trigger monitor profile changes and black screens. Because this user reports a black flash plus changed colors on fullscreen, comparing this option on/off is a targeted diagnostic, not a confirmed fix.
- `render.non_shader_cm_interop = 2`, currently active, bypasses external color transforms such as Hyprsunset for fullscreen photo/video/game. A Comfort preset should keep warmth behavior consistent in both modes; an Accurate preset should suspend warmth globally. The existing shell has one global Night Shift value, so independent per-screen warmth must not be promised.
- Reset Hyprsunset to identity and its brightness multiplier to 100% for accurate work. Its IPC command named `gamma` is a multiplier, not a way to set the monitor's sRGB/2.2/2.4 transfer curve; use hardware backlight for ordinary brightness. See [Hyprsunset's matrix implementation](https://github.com/hyprwm/hyprsunset/blob/main/src/Hyprsunset.cpp#L75).
- `render.cm_auto_hdr = 1`, currently active, can switch fullscreen HDR content to HDR. It is not a mechanism to improve SDR. Add automatic HDR only after a known SDR source stays SDR and a known HDR source enters/exits HDR correctly with Acer Auto enabled.
- The installed mpv binary reports v0.41.0. Hyprland's current [automatic-HDR note](https://wiki.hypr.land/configuring/core/config-options/) requires `target-colorspace-hint-mode=source` for mpv newer than v0.40.0. Add and verify this in a dedicated automatic-HDR playback profile; do not confuse it with the separate forced-SDR profile. The existing mpv config has `target-colorspace-hint=auto` but does not explicitly select source mode.
- Keep creative canvases opaque. The existing `focus` mode ensures opacity, but it does not disable night light, set a monitor profile, lock brightness or establish calibrated accuracy.
- Prefer specific runtime configuration changes and output state tracking for presets over reloading the entire desktop on each selection. The existing kuwai mode picker does reload; display presets should remain separate from focus/glass/gaming/battery appearance modes.

See [Hyprland rendering options](https://wiki.hypr.land/configuring/core/config-options/) and [monitor fields](https://wiki.hypr.land/configuring/core/monitors/). Installed-version source qualifications are recorded in the companion research note.

## Existing controls and proposed integration

Already present:

- Super+N → Controls: one brightness slider per output, global Night Shift and warmth.
- `~/Scripts/brightness.sh` routes per-output brightness through one controller. External Acer DDC uses a worker; the laptop uses backlight control. The service also owns idle dim/restore coordination.
- `kuwai mode --pick` and Super+Shift+/ choose appearance/performance modes; they are not display-calibration presets.

Proposed new Display controls, not implemented:

1. An output selector: Acer, Laptop, Both; show physical resolution, actual refresh, SDR/HDR state, output format and profile status.
2. Preset choices: Work, Accurate, Media, Gaming, Comfort, Battery; an Advanced section distinguishes Web Accurate, SDR Video and HDR Preview.
3. Separate Day/Evening/Night comfort schedules. Manual overrides win until explicitly resumed or their chosen expiry; an Accurate lock suspends warmth and brightness automation even across sunset, idle restoration and app focus changes.
4. HDR policy: Off / Automatic / HDR Preview. Explicitly mark laptop HDR unsupported. Unverified Acer 10-bit settings stay an optional test, with timed revert to the working mode if not confirmed.
5. Refresh policy: Desktop 200/165; Film 120 on Acer where suitable; Battery 60 on laptop. Warn when a selection will briefly blank the screen. Do not change refresh repeatedly as browser content changes.
6. A calibration section: selected profile, its associated OSD/white-point/brightness state, and whether measured. A preset name must not display “calibrated” merely because a file exists.
7. Restore previous / Resume schedule. On hotplug, identify by monitor description/EDID identity, rediscover connector and DDC bus, and reapply only compatible saved choices. Do not hard-code bus 15 or assume DP-3 survives a port change.

Reuse `shell/services/Display.qml` and the existing brightness controller. Extend its serialized ownership for additional verified DDC operations; don't add another writer for brightness or race it with dim/restore. Capabilities currently advertise white-point presets and RGB gains but not standard HDR, overdrive, gamma or named picture modes. Manufacturer-specific VCP values remain undocumented: leave those controls manual until mapped with readback and a reversible test.

Application automation should be opt-in and restore the preceding preset when the last relevant window exits. Color-accuracy lock has priority over schedule, night light, idle brightness changes, appearance modes and automatic media selection. A browser can host design tools, code and video simultaneously, so its executable name alone cannot choose the correct preset.

### Notch interaction walkthrough

The user's latest request is to talk through the operation and tests before activation. The following is proposed UI behavior, not existing controls.

1. Open the existing center through Super+N, or the notch hover row's bell; choose Controls. Add a Display card here, with a direct display shortcut in the notch hover row later. Avoid putting an always-visible row of presets on the resting notch.
2. Choose Acer, Laptop or Both. Show one concise state line per screen, for example `Acer · Work · SDR output · 1440p 200 Hz · 8-bit · sRGB baseline (unmeasured)`. Report pipeline state honestly; physical OSD HDR activation needs initial on-monitor verification.
3. Choose Work, Accurate, Media, Gaming or Battery. Comfort is a separate time/brightness/warmth policy rather than a competing color-calibration mode. Advanced Media options expose Film cadence and optional HDR Preview only after qualification.
4. Work defaults to neutral SDR. Accurate suspends warmth globally, holds the selected measured-profile/OSD state and brightness, and prevents scheduled overrides. Media preserves SDR color and offers an explicit 120 Hz Film cadence option on the Acer. Gaming permits tested VRR and its separately qualified performance path. Battery can select the laptop's advertised 60 Hz mode.
5. Change brightness independently for each screen. Schedule Day/Evening/Night brightness or optional comfort warmth only outside Accuracy lock. Manual changes persist until a clearly shown chosen expiry or Resume schedule; sunset is not permission to override accurate work.
6. Show Applying, Applied, Unsupported or Failed from actual readback. Display DDC failures rather than announcing success. Provide Restore previous and a temporary confirmation countdown for a risky new mode; lack of confirmation reverts it.
7. Briefly show the selected activity in the notch when it changes. A persistent small lock indicator is appropriate while accuracy is pinned. Explain `Night Shift paused on both screens` when either display requests accuracy, because present software warmth is global.

## Creator workflow assumptions

The user primarily delivers websites/mobile apps and occasional code-generated motion videos, wants fast edits of phone footage plus screen recordings, and watches anime/series. Start with web/sRGB and SDR Rec.709 delivery. Keep print/P3/HDR as explicit later workflows, not silent defaults.

For a low-cost first workflow, use Kdenlive for editing, OBS for intentional screen/camera capture, and the existing mpv for playback and export checks. See the companion research note for current primary-source support, Linux codec limitations of alternative editors and code-animation licensing.

A practical initial project is 1080p30 SDR for talking-head videos; use 60 fps when interaction/motion needs it and source footage supports it. Record legible screen content at native resolution and crop/scale deliberately. Prefer SDR phone recording initially; identify HDR phone material and tone-map it deliberately before treating it as SDR. Handle variable-frame-rate material with a supported transcode/proxy workflow when timing requires it. Preserve original sources. These are suggested defaults, not a requirement to discard higher-quality camera originals or a guarantee of every editor's color path.

## Qualification order

1. Save observed settings and user OSD choices. Use the same paused SDR frame for windowed/fullscreen comparisons; record Hyprland color mode and monitor information before/after.
2. With fixed SDR and neutral warmth in both states, compare content-type signaling, VRR and direct scanout one variable at a time. The original symptom must be judged on the physical monitor, not assumed fixed from a screenshot or successful IPC response.
3. Validate range with black/white clipping patterns. The observed movie's limited-range YUV source and full-range RGB output are normal, not evidence of a mismatch. Don't force input range to full just because the screen looks washed out.
4. Qualify Acer 10-bit separately using grayscale gradients, desktop text, fullscreen media, game entry/exit, screenshots/sharing and sleep/wake. If 200 Hz fails, compare advertised lower modes; revert to working 8-bit when needed.
5. Test known HDR content with monitor HDR Auto, verify real PQ/BT.2020 output and return to SDR. Ordinary SDR movie fullscreen must not spuriously trigger HDR or a vivid profile.
6. Measure/profile each screen at its chosen work state, then check the actual browser, design and editing applications. Check moving windows between screens, laptop-only operation, lid changes, reconnect, dim/restore and schedule overrides.

### What earns an Applied / Verified label

| Check | Observable acceptance |
| --- | --- |
| SDR fullscreen | The same paused image retains white point, black level and saturation; no unexpected HDR or monitor-preset change |
| Signal range | Black/white clipping patterns retain expected detail; source limited range is decoded once rather than forced to full |
| Text/chroma | Native-resolution text and colored fine lines stay clean; no hidden resolution reduction or chroma compromise |
| Film/anime | Player statistics do not show sustained dropped/repeated-frame problems; pans are assessed on the real monitor; optional interpolation is clearly a preference |
| Gaming VRR | Confirm variable refresh is active under a known game workload; inspect tearing, flicker and overdrive trails at varying frame rates |
| Accurate | Correct physical-screen profile and OSD state; neutral warmth; stable brightness; app/source tagging checked; measured only when measurements exist |
| HDR | Known HDR source, application tags, compositor output and monitor's own HDR indicator agree; exit restores SDR correctly |
| Schedule / overrides | A manual Accurate lock survives sunset/idle/app focus; Resume schedule restores the intended comfort policy rather than an old random value |
| Lifecycle | Disconnect/reconnect, suspend/resume, lid changes, shell restart and mode rollback restore compatible state without moving live windows |
| Capture / export | Screen sharing works; SDR exported files are checked in mpv and a browser; physical color is not inferred from screenshots alone |

Controller/preset-state transitions can be tested with fake monitor/DDC adapters before live use. Physical color, flicker, latency and monitor HDR switching still require real-screen checks. Never change the system clock to test schedules; use injectable times in isolated tests.

No physical calibration, HDR qualification, 10-bit A/B, latency measurement or successful fix of the reported fullscreen symptom was completed in this research. No desktop modes, monitor settings or services were changed.

## Subsequent live movie comparison

After the initial research, the user authorized controlled movie comparisons. These temporary runtime tests do not implement the proposed notch presets or modify persistent configuration.

- Baseline: mpv VIDEO content on the Acer; 2592×1080, 30 fps, 8-bit HEVC/NV12, SDR BT.709/BT.1886, limited-range source; renderer produces full-range RGB. Hardware decoding NVDEC, renderer gpu-next. The source being limited-range is normal.
- Test 1: change only `render.send_content_type` from true to false, with a three-minute automatic restore. User reports both the black flash and washed/different colors remain. User also reports the Acer named picture preset remains the same. The original true value was restored and read back successfully. This test does not support content-type signaling as a sufficient fix.
- Test 2: change only `render.non_shader_cm` from 3 to 0, with automatic restoration. User comparison pending at the time of this note.
- Temporary helper: `/tmp/rice-movie-diagnostic/compare.py`; validates setting readback and restores the original value, or preserves a newer differing value. It does not reload the desktop or change monitor modes. It is a diagnostic helper, not an installed preset controller.
- Test 2 (`non_shader_cm` 3 → 0) and Test 3 (movie-only VRR off): both symptoms remained; both restored.

## Cause found and fixed (2026-11-08)

mpv 0.41 with `target-colorspace-hint=auto` and the default `target-colorspace-hint-mode=target` tagged its Wayland surface with the *display's* capabilities read from Hyprland: the SDR BT.709 movie was rendered and tagged as **PQ / BT.2020, 455 nits** (`video-target-params`). Windowed, Hyprland converted it back to SDR. Fullscreen, `render.cm_auto_hdr = 1` saw an HDR surface and switched the Acer to HDR (the black flash, a modeset); with the Acer's HDR menu Off, the panel showed PQ-encoded values as SDR (the washed-out, low-contrast image; a screenshot regression against mpv's own frame gave slope ≈ 0.37, offset ≈ 0.23).

Fix: `target-colorspace-hint-mode=source` in `~/.config/mpv/mpv.conf` (Hyprland's wiki asks for exactly this for mpv > 0.40). Readback after: `bt.709 / bt.1886, 203 nits`; the user confirmed on the monitor: no flash, colours right. HDR files now tag PQ honestly and still switch the Acer to HDR in fullscreen; the Acer's HDR menu must be **Auto** for that. kunai (kitsunesnipe) was not the cause: it passes no colour options and keeps mpv.conf.

## Presets implemented

`hypr/kuwai/display.lua` (`kuwai display NAME`, the center's Controls → Display row, the notch's quick shelf: scroll to change, click for Controls): everyday, accurate, movie (external 120 Hz), gaming (the gaming look), battery (panel 60 Hz). Automatic on top of everyday (feature `auto_display`): an open colour app → accurate; unplugged → battery. Movie is never automatic: a rate change on fullscreen would blank the screen each time, and fullscreen video already gets VRR. Night Shift stays neutral in fullscreen video (user's choice; Hyprland's `non_shader_cm_interop = 2`).
