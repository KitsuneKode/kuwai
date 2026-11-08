# Display quality: primary-source findings

Research date: 2026-11-08. Advice and proposed controls only; no monitor, session, application, or source-product settings were changed. Hyprland target: 0.57.1. Current wiki pages track latest Git, so pinned source and observed settings take precedence over wiki defaults.

## Hardware evidence and its limits

The [Acer India listing for UM.HX2SI.101](https://store.acer.com/en-in/acer-nitro-xv272u-x1-27-inch-wqhd-2560-1440-ips-gaming-monitor-200hz-refresh-rate-0-5ms-gtg-amd-freesync-premium-hdr400-2-hdmi-dp-ergostand-2w-2-stereo-speakers-dci-p3-90-black) identifies XV272U X1 as 27-inch IPS, 2560×1440, 200 Hz, 90% DCI-P3, HDR400, FreeSync Premium, HDMI 2.0 and DisplayPort 1.4. Its “Color Supported: Black” field is cabinet color, not evidence of bit depth. No native panel-bit-depth or unit calibration evidence appears there.

The official [Czech EU SKU UM.HX2EE.111 page](https://www.acer.com/cz-cs/monitors/gaming/nitro-xv2/pdp/UM.HX2EE.111) specifies 200 Hz through DP, 144 Hz through HDMI, 350-nit SDR/400-nit HDR peak, and VESA DisplayHDR400. The [Polish EU SKU page](https://www.acer.com/pl-pl/monitors/gaming/nitro-xv2/pdp/UM.HX2EE.111) lists native contrast 1000:1. Treat these as regional corroboration, not proof every Indian unit has identical electronics, firmware or panel. An exact X1 manual was not located; do not borrow an XV272U P/KV/X manual's OSD behavior.

The investigation supplied these live read-only observations: Acer DP-3 operates at 1440p200, XRGB8888, `cm=srgb`; EDID advertises a 10-bit input, PQ HDR, approximately 455.5-nit desired peak, and VRR 48–200. Laptop CSOT MNF601CA1-3 operates at 1440p165, scale 4/3, XRGB8888; EDID advertises 8-bit, no HDR, VRR 60–165. These are session/EDID facts reported by the parent investigation, not independent laboratory measurements. EDID luminance is metadata, not a measured peak.

Keep four claims separate: source precision → application swapchain precision → compositor scanout format → physical panel drive. `rgb10a2` in mpv proves its buffer precision; it does not establish 10-bit scanout. XRGB2101010 would establish a compositor output-buffer format, not native 10-bit LCD pixels or actual wire encoding. EDID accepting 10-bit does not distinguish native 10-bit from 8-bit+FRC. [Hyprland's bit-depth documentation](https://wiki.hypr.land/configuring/core/monitors/colors/) explicitly distinguishes 10-bit support from FRC implementations. Neither Acer primary listing resolves this unit's physical panel depth. Keep the laptop at 8-bit/no HDR; qualify Acer 10-bit separately at its intended resolution/refresh, checking actual format, stability, capture, and gradients.

## Hyprland capabilities and version-specific cautions

[Hyprland 0.57.1 ConfigValues.cpp](https://raw.githubusercontent.com/hyprwm/Hyprland/v0.57.1/src/config/values/ConfigValues.cpp) pins these defaults: `cm_enabled=true` (restart needed for a full change), `direct_scanout=0`, `send_content_type=true`, `cm_auto_hdr=1`, `non_shader_cm=3`, `non_shader_cm_interop=2`, `cm_sdr_eotf="default"`, `use_fp16=2`, `icc_vcgt_enabled=true`, `misc:vrr=0`. The observed machine overrides several. In particular, latest wiki's `non_shader_cm=2` default is not the 0.57.1 source default.

The [current monitor color documentation](https://wiki.hypr.land/configuring/core/monitors/colors/) defines `srgb` as sRGB output primaries, `auto` as sRGB at 8bpc/wide at 10bpc when supported, and `wide` as BT.2020 output primaries. `edid` primaries can be inaccurate. An absolute-path `icc` overrides the CM preset and forces sRGB EOTF. HDR presets remain experimental and ICC/HDR gaming combinations are cautioned against. These controls describe the output; selecting `wide` cannot make a 90% P3 panel reproduce BT.2020. Recommendation: SDR starts with `srgb`, or a measured ICC for that unit/OSD state, not a manual `wide` switch justified only by the marketing gamut.

The [current option documentation](https://wiki.hypr.land/configuring/core/config-options/) describes:

| Control | Relevant behavior |
| --- | --- |
| `render.cm_sdr_eotf` | `default` currently sRGB; `gamma22` changes unspecified sources; `gamma22force` also reinterprets tagged sRGB; `srgb` explicitly treats unspecified sources as sRGB. |
| Monitor `sdr_eotf` | Output assumption, separately configurable; do not equate source reinterpretation with measured OSD gamma. |
| `cm_auto_hdr` | 0 disabled;1 HDR;2 HDR with EDID primaries; switches for fullscreen HDR content. |
| `send_content_type` | Can trigger monitor profile autoswitch and a black screen during switching. |
| `non_shader_cm_interop` | 0 disables external CTM fullscreen;1 retains it;2 disables it for fullscreen photo/video/game. |
| `direct_scanout` | 0 disabled;1 enabled;2 automatic for games. |

The [pinned 0.57.1 Monitor.cpp](https://raw.githubusercontent.com/hyprwm/Hyprland/v0.57.1/src/output/Monitor.cpp#L1746) confirms mode 2 direct scanout rejects fullscreen content other than GAME. A normally classified mpv VIDEO surface therefore should not acquire direct scanout merely by becoming fullscreen. The same source skips certain color-management blockers under `non_shader_cm=3`/IGNORE. `canNoShaderCM()` rejects ICC-bearing output descriptions. Do not advertise3 as an accuracy optimization. For an accuracy/diagnostic baseline, propose `non_shader_cm=0`, direct scanout 0. For gaming, test2 plus direct scanout 2 after validating colors. Direct scanout eligibility and correct CM are different gates.

Per-output fields include `cm`, `icc`, `bitdepth`, `sdr_eotf`, luminance metadata and VRR; global render options remain session-wide. [Monitor field reference](https://wiki.hypr.land/configuring/core/monitors/). [VRR mode reference](https://wiki.hypr.land/configuring/core/monitors/modes/) defines 0 off, 1 always, 2 fullscreen, 3 fullscreen video/game; use numeric3 when matching both types. Mode availability comes from the output's advertised modes, not an arbitrary refresh number.

## Color targets and brightness

[W3C's sRGB specification](https://www.w3.org/Graphics/Color/srgb.pdf) defines D65, an approximately 2.2 response with a precise piecewise function, and 80 cd/m² reference white. [CSS Color4](https://www.w3.org/TR/2026/CRD-css-color-4-20261103/) uses sRGB/D65 as the legacy CSS default. Therefore web/UI work should preserve sRGB semantics and neutral white, rather than globally forcing gamma 2.2 on tagged sRGB or adding warmth. The reference 80 nits is a defined viewing condition, not a universal office comfort prescription.

[EIZO's monitor-adjustment guidance](https://www.eizo.eu/colour-management-and-calibration/colour-management-the-complete-workflow/monitor-adjustment) recommends 120–140 cd/m² at an average daylight workstation and gives 90 cd/m² under artificial lighting; it explicitly calls its examples rough references dependent on workplace conditions. It also recommends gamma 2.2 for that photographic workflow. Its 6000 K starting-point discussion concerns ambient/print matching, not a replacement for sRGB's D65 target.

Suggested starting targets below are our practical choices, not Acer calibration values or universal standards. Measure with a colorimeter to turn them into actual luminance; neither Acer 40% nor laptop 43% can be converted into nits without measurements.

| Use/ambient | Starting white luminance | White/response |
| --- | --- | --- |
| Web/UI/design, controlled normal room |100–120 cd/m² |D65; sRGB pipeline; gamma 2.2 OSD only as nearest available coarse setting. |
| Daylit workstation |120–140 cd/m² |Same neutral target; reduce reflections first. |
| Dim-room work/comfort |80–100 cd/m² |Neutral for color work; optional warmth for noncritical reading. |
| SDR films, controlled dim surround |Around100cd/m² |D65, Rec.709/BT.1886 interpretation; see below. |
| SDR gaming |100–140 cd/m² initially |Tune to room; preserve source gamma, neutral colors, and shadow detail. |

For reference SDR video evaluation, [ITU-R BT.2035](https://www.itu.int/rec/R-REC-BT.2035/en) specifies 100 cd/m² white, D65 and BT.1886 response. [BT.1886](https://www.itu.int/rec/r-rec-bt.1886/en) is the television display EOTF; ideal-black gamma is 2.4, with black-level compensation in the actual formulation. This does not mean forcing the entire desktop to gamma 2.4. A color-managed player should convert source video to the display's characterized output response. Acer 1000:1 consumer IPS is not a reference grading monitor.

## Calibration, OSD and range

[ICC's display-calibration guidance](https://www.color.org/displaycalibration/) distinguishes setting targets, measuring displayed patches, applying correction transforms/LUTs and generating a display profile. A downloaded profile from another unit is not a measurement of this one. Calibration cannot create missing gamut or remove panel nonuniformity.

Recommended procedure: establish a repeatable OSD state (SDR, chosen gamut mode, neutral temperature, normal contrast, disabled dynamic contrast/black boost/extra saturation), set hardware brightness, then measure/profile that exact state. This sequence is a workflow recommendation, not a confirmed X1 menu recipe. Changing OSD gamut, RGB gains or contrast later invalidates assumptions of that profile; maintain separate profiles for separately measured states. Do not invent exact RGB-gain values without a meter.

Use one coordinated display-characterization path. Applications must accurately tag their output for the compositor. Applying an application ICC transform into device values and subsequently treating those values as ordinary sRGB for another device transform can double-correct. Applying the same VCGT calibration ramps twice is also wrong. App+compositor CM can coexist when output tagging and ownership are correct; two CM components are not inherently an error. Verify with controlled patches, not by the existence of profile files alone.

PC output and monitor input should agree on RGB full range. A limited-range YCbCr source does not require limited-range desktop output: decode/convert it once into the expected RGB range. The [mpv manual](https://mpv.io/manual/master/#options-video-output-levels) describes full→limited mismatch as crushed endpoints and limited→full mismatch as gray blacks/dim whites. Retain automatic source range unless the file is demonstrably mistagged; use black/white clipping patterns to verify output agreement.

## Media cadence and HDR

At fixed refresh, arithmetic matters:200/30=6⅔ and165/30=5½ cause unequal repeats.120 Hz gives exact multiples for 24/30/60 fps,144 Hz for 24 fps;180 Hz for30/60 fps only if actually advertised.23.976 fps ideally uses119.88/143.856, not rounded exact 120/144; otherwise small clock correction or occasional repeats remain. These are calculations, not claims that every mode exists.

At the reported Acer VRR 48–200 range, 24/30 fps are below the minimum. Repeated presentation at 48/60 Hz can fit, but compositor/player/driver must actually provide that cadence; FreeSync marketing alone does not prove smooth movie playback. Laptop's reported60–165 differs. For repeatable media baseline, use an available120Hz mode and inspect player timing; test VRR separately. VRR is not frame interpolation.

The [mpv manual](https://mpv.io/manual/master/) supports `video-sync=display-resample` for display timing with small audio resampling. Its `gpu-next` colorspace hint reports output metadata; stats verify input/output descriptions, not the final monitor result. Hyprland's [auto-HDR documentation](https://wiki.hypr.land/configuring/core/config-options/) specifically requires `--target-colorspace-hint-mode=source` for mpv newer than 0.40.0 when using compositor automatic HDR. Keep this distinct from a forced-SDR media profile.

HDR400 is an entry tier, not proof of effective local dimming or reference HDR. [VESA CTS1.1](https://displayhdr.org/performance-criteria-cts1-1/) allowed400-tier8-bit driver depth while accepting10-bit signals; [CTS1.2](https://displayhdr.org/performance-criteria/) tightened contrast and precision requirements. Certification revision for this exact unit was not verified. Do not infer native 10-bit, dimming-zone count or measured peak from the logo. Recommendation: keep HDR optional for real HDR media/games, with correct application metadata and OSD mode; compare against competent HDR→SDR tone mapping. Keep SDR desktop and accuracy presets SDR. `sdrbrightness` is SDR-in-HDR mapping, not physical backlight brightness.

## Proposed preset/toggle design

These are design recommendations, not implemented behavior:

- **Accurate SDR:** per-output native resolution; Acer 200/laptop 165 Hz initially; sRGB output with a matching verified OSD state, or that output's measured ICC; no night tint; hardware brightness at the room target. Session accuracy priority disables content-type monitor autoswitch and automatic HDR. Use shader CM and disable direct scanout while validating.
- **Comfort:** same geometries and SDR interpretation; lower per-output hardware brightness first; optional global warmer tint. Clearly show that warmth alters colors. Avoid presenting software dimming as calibrated brightness.
- **SDR media:** neutral output, automatic source decoding, HDR off, no surprise OSD profile changes, optional advertised120Hz cadence mode; validate fullscreen matches windowed. Do not blindly apply “cinema” saturation or a desktop-wide2.4 exponent.
- **Gaming:** native resolution/high refresh, per-output VRR 3 or 2 as qualified, direct scanout 2 only after color/path testing. Prefer non-shader mode 2 over IGNORE 3 when enabling this path. OSD overdrive must be visually qualified across the VRR range; no exact X1 best overdrive setting was established.
- **HDR media/game, optional:** Acer only; separate profile from ICC-accurate SDR; confirmed10-bit output where supported; deliberate HDR/OSD coordination; measured or honestly advertised luminance inputs. No HDR on the laptop based on current evidence.

Brightness and color mode can be per output, but [hyprsunset's documented IPC](https://wiki.hypr.land/hypr-ecosystem/user/hyprsunset/) exposes global temperature/gamma. Upstream [PR87](https://github.com/hyprwm/hyprsunset/pull/87) and [PR88](https://github.com/hyprwm/hyprsunset/pull/88) for per-output behavior were still open when checked. Therefore an accuracy request on either screen should suspend global warmth and explain why; “Acer accurate/laptop warm” is not a verified stock capability.

[hyprsunset source](https://raw.githubusercontent.com/hyprwm/hyprsunset/main/src/Hyprsunset.cpp#L75) implements its “gamma” as a diagonal CTM multiplier, not the monitor's gamma exponent. Identity temperature plus gamma 100% is the neutral software baseline. Its scheduled profiles may override temporary IPC changes later, so accuracy mode must coordinate with the existing Night Shift owner/schedule, save intent, and restore it deliberately.

Reuse the existing brightness owner and its connector mapping; introduce no second DDC writer. Keep preset request, applied readback, unsupported control and failure distinct. DDC brightness/temperature capabilities do not establish a supported command for OSD gamma or game presets. Current investigation found unsupported standard gamma/preset VCPs and undocumented manufacturer codes, so those should remain manual OSD instructions until documented.

## Fullscreen color-change investigation

The supplied symptom is windowed colors acceptable → fullscreen black flash → washed/different color, with Acer HDR OFF. Several relevant transitions exist: monitor content-type autoswitch; external warmth suppressed by interop2; fullscreen output metadata/transfer changes; VRR; HDR signaling; scanout eligibility. The documentation establishes plausible mechanisms, not the cause on this machine.

Most direct first hypothesis is content-type monitor autoswitch because documentation explicitly warns about black-screen transitions. Warmth removal can explain a white-point difference but cannot by itself establish crushed/raised black levels. Investigate one reversible setting at a time, comparing the same paused frame and output readback. Direct scanout 2 is game-only, so do not claim ordinary mpv video is bypassing the compositor without observing its classification/active path. An 8-bit limited SDR source converted into a 10-bit full-range application buffer is normal and is not evidence of HDR or a range bug.

## Creator software: small, practical Linux stack

Additional scope clarified on 2026-11-08: quick edits of phone-camera footage and screen recordings, occasional code/Claude-assisted motion videos, primarily website/mobile-app client work, plus accurate anime/series playback. Recommendation: **use the installed Kdenlive for editing and mpv for playback; add OBS when a reusable recording workflow is needed, and local Remotion only when a video needs programmatic animation.** The parent investigation found Kdenlive/mpv/FFmpeg installed and OBS/Resolve absent from PATH; absence from PATH is not a full package inventory. This is a fit/value judgement, not a benchmark. No software was installed or settings changed during this research.

| Tool | Why it fits this work | Cost/qualification |
| --- | --- | --- |
| [Kdenlive](https://kdenlive.org/) | Cutting phone footage, screen recordings, titles/subtitles, keyframes, voice/music mix, basic correction and scopes in one Linux editor. | Free/open source; [project licensing](https://kdenlive.org/cs/about/) states no subscription, license fee or paid feature unlocks. Best starting editor for this scope. |
| [OBS Studio](https://obsproject.com/), optional addition | Record the actual website/app/terminal and narration; build reusable recording scenes. | Free/open source. Use the Wayland PipeWire source and verify a short actual recording when installed. |
| mpv | Keep the existing player for anime/series and checking finished exports against the neutral display preset. | Existing workflow; editor preview and final-file playback should both be checked. |
| [Remotion](https://www.remotion.dev/docs/license/pricing), optional | React/code-driven titles, cursor demonstrations and repeatable product animations when ordinary editor keyframes are insufficient. | Local rendering does not require a hosted subscription for eligible Free License users; licensing conditions below matter for client code handoff. |

### Recommended ingest/edit/export routine

1. Keep camera originals. For new quick-turn SDR projects, record SDR deliberately rather than treating the Acer's HDR toggle as an editing conversion. On supported iPhones, [Apple documents Camera → Record Video → HDR Video off](https://support.apple.com/guide/iphone/adjust-hdr-camera-settings-iph2cafe2ebc/ios). This setting is model-dependent; do not assume the user's phone supports Dolby Vision recording.
2. Inspect actual source metadata. If existing footage is PQ/HLG/Dolby Vision, make a properly tone-mapped/gamut-converted SDR working copy before an SDR edit. Changing its label to Rec.709 or lowering bit depth is insufficient. [FFmpeg's filter documentation](https://ffmpeg.org/ffmpeg-filters.html#tonemap) separates tone mapping/color conversion from encoding. A convenient iPhone option for existing HDR footage is [iMovie export with HDR disabled](https://support.apple.com/en-au/102241), as Apple documents. Do not claim desktop HDR grading has been qualified here.
3. Choose the project's delivery size, frame rate and SDR color space before cutting. The [Kdenlive project-profile reference](https://docs.kdenlive.org/en/project_and_asset_management/project_settings/general_settings.html) says profiles define dimensions, frame rate and color space. A useful default is Rec.709 SDR at the intended delivery fps; use 30 fps for ordinary talking-head edits and 60 fps when smooth UI motion is part of the deliverable. These fps choices are recommendations, not display calibration requirements.
4. Transcode variable-frame-rate phone/screen footage to a constant-rate editing master if Kdenlive requests it or timing/seek/audio-sync problems appear. [Kdenlive explicitly provides VFR transcoding profiles](https://docs.kdenlive.org/en/getting_started/configuration.html). Then enable [proxy clips](https://docs.kdenlive.org/en/project_and_asset_management/project_settings/proxy_settings.html) if high-resolution HEVC is slow: proxies lighten editing, while rendering returns to originals. Consequently, a good-looking proxy does not establish correct final HDR conversion, timing or color metadata. Kdenlive also documents [transcoding color-tag pitfalls](https://docs.kdenlive.org/en/tips_and_tricks/useful_info/color_hell.html).
5. Edit on the neutral SDR display preset; correct exposure/white balance using scopes rather than extra display saturation. Render a short representative SDR MP4 test with a compatible H.264/AAC preset, then check motion, text, audio sync, skin tones and black/white clipping in mpv and the intended browser/phone. Retain a high-quality master separately when useful. Actual encoder availability/performance depends on the installed build and GPU; no preset was benchmarked on this host.

Kdenlive is recommended for this SDR workflow, not as a proven HDR finishing system. Its [25.12 release notes](https://kdenlive.org/news/releases/25.12.0/) explicitly mention filtering out effects/transitions incompatible with 10-bit depth; selecting a 10-bit export alone therefore does not establish an entirely 10-bit processing path.

### Recording on Hyprland

[OBS documents Screen Capture (PipeWire)](https://obsproject.com/kb/display-capture-sources) for Wayland. [Hyprland's portal documentation](https://wiki.hypr.land/hypr-ecosystem/user/xdg-desktop-portal-hyprland/) says selecting the OBS PipeWire source should show its share picker and supports Hyprland-specific window sharing. Use this path rather than expecting X11/XSHM capture to cover native Wayland windows. Portal availability, chosen output/window, cursor visibility, recording frame rate and microphone/system audio require a short end-to-end check; compositor refresh does not imply the recording has the same fps.

Start with SDR recording, a deliberate 30/60 fps output and an encoder the existing GPU supports. The [OBS recording guide](https://obsproject.com/kb/standard-recording-output-guide) recommends MKV against interrupted-recording corruption and documents remuxing to MP4 when needed. Remuxing changes the container, not HDR to SDR or a codec's editability. A camera-phone recording is an imported media file; using the phone as a live OBS camera would require a separate connection/workflow not established here.

### Why Resolve is a later option

Resolve becomes attractive if advanced grading, tracking/noise reduction or a deeper Fusion workflow becomes a regular requirement. It is not the lowest-friction default for this phone/screen-editing workload on Linux.

The current [official Resolve 21.1 codec PDF, September 2026](https://documents.blackmagicdesign.com/SupportNotes/DaVinci_Resolve_21_Supported_Codec_List.pdf) lists, in its Rocky Linux 8.6/CUDA tables (printed pp.13–14,17): H.264/H.265 decoding is Studio-only; encoding requires Studio and Nvidia graphics; AAC decoding/encoding is unsupported. This affects ordinary 8-bit files too, not merely 10-bit phone HEVC. The tables do not guarantee every HEVC 10-bit profile/chroma format on every GPU; hardware support remains an explicit qualification. A free Resolve workflow may require a supported intermediate such as DNxHR plus PCM audio, with additional storage/time. Studio still does not remove the listed Linux AAC limitation. Those published platform tables also do not qualify Resolve on this host's Arch/Hyprland configuration.

[Blackmagic's India product page](https://www.blackmagicdesign.com/in/products/davinciresolve) currently lists Resolve free and Studio 21 at **₹25,980**, promoted from ₹31,980, as checked 2026-11-08. This is the displayed regional price, not a confirmed checkout/tax quote. No purchase is needed for the recommended Kdenlive workflow.

### Remotion commercial boundary

The current [Remotion FAQ](https://www.remotion.dev/docs/license/faq) and [terms](https://www.remotion.dev/docs/terms) allow individuals and teams/organizations up to three people to use the Free License commercially. A small studio delivering only a finished MP4 to a larger client does not aggregate that client's headcount. If the client owns/operates the Remotion codebase, or parties collaborate on that project, involved-party headcounts aggregate toward the four-person Company License threshold. The company total matters, not just the number editing code. Source availability does not mean OSI open source.

For Company License users, [current pricing](https://www.remotion.dev/docs/license/pricing) distinguishes Creators at $25/user/month for low-volume manual creation and Automators at $0.01/render with a $100/month minimum for automated video products/pipelines. These requirements do not apply merely because an eligible Free License user renders locally with Claude/Codex assistance. Recommendation: reuse the user's existing motion-video path first; consider Remotion only if code-driven repeatability saves time, and revisit licensing when handing off project code.
