# Audio: DACs, IEMs and EasyEffects

## How sound flows

```
apps ─▶ EasyEffects (the Cadenza EQ) ─▶ the default output (a real DAC) ─▶ IEMs
```

- **The default output is always a real device** (the FiiO JA11, the Audiocular D07, …).
  EasyEffects follows it. Don't make "Easy Effects Sink" the default: when it is the
  default, EasyEffects falls back to the last device it saved (that sent sound to the
  Audiocular while the Cadenza was in the FiiO). The Sound panel no longer lists it.
- **Switch DACs** in the island's Sound panel (or `wpctl set-default <id>`, ids from
  `wpctl status`). EasyEffects moves with it; the island names the IEMs behind the DAC.
- **Bit-perfect where possible**: PipeWire follows each stream's rate (44.1/48/88.2/96/
  176.4/192 kHz, `~/.config/pipewire/pipewire.conf.d/50-audio-quality.conf`), 32-bit to
  both DACs. When a stream must be resampled it uses quality 10
  (`…/client.conf.d` and `…/pipewire-pulse.conf.d/60-resample-quality.conf`, active
  after `systemctl --user restart pipewire pipewire-pulse wireplumber`).

## The EQ (save it once)

The Cadenza EQ you hear lives in EasyEffects' live state; the preset named `cadenza`
is empty. Save it so it can follow you to any DAC:

1. Open EasyEffects → **Presets** (top) → Output → `cadenza` → **Save** (overwrites it with
   the current EQ).
2. **Autoload**: in Presets → Autoload, add the FiiO JA11 (and keep the Audiocular) →
   preset `cadenza`. Now whichever DAC you plug the Cadenza into, the EQ loads.
3. Zen is on EasyEffects' blocklist (Settings → Output → Blocklist), so the browser
   skips the EQ. Remove it there if you want the EQ for YouTube/Spotify-in-Zen too.

Backups of every EasyEffects file: `~/.local/state/kuwai/easyeffects-backup-*`.

## New IEMs or a new DAC

The island shows what's behind a DAC from `~/.config/kuwai/devices.json`
(no restart needed):

```json
[
  {"match": "Audiocular D07", "label": "Kiwi Ears Cadenza", "via": "Audiocular D07", "image": "cadenza.png", "kind": "iem"},
  {"match": "JadeAudio JA11", "label": "Kiwi Ears Cadenza", "via": "FiiO JA11",     "image": "cadenza.png", "kind": "iem"}
]
```

- `match`: a piece of the device's name as PipeWire says it (`wpctl status` → Sinks).
- `label`: what you're listening on (the IEMs). `via`: the DAC. `kind`: `iem`,
  `headphones`, `earbuds`, `speaker`.
- `image`: a picture in `~/.config/kuwai/devices/` (square PNG, transparent).
- New IEMs on the same DAC: change `label` and `image` on that DAC's line.
- New IEMs, new sound: in EasyEffects make a preset for them (e.g. AutoEQ's parametric
  EQ for the model → Equalizer → Import), then point that DAC's Autoload at it.

## Device cards

A card shows when a device actually comes or goes, once. Nothing shows while the
screen is locked or off, or in the 8 s after you come back. What was told lives in
`$XDG_RUNTIME_DIR/kuwai/devices-told.json` (a new login starts fresh, and greets you with
what's connected).
