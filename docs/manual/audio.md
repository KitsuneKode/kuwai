# Audio: Sound panel, DACs, and device cards

Open the Sound view inside Controls (**`Super+Ctrl+Space` → Sound**) or right-click the media card in the island. It lists per-app PipeWire streams, output devices, input devices, and live microphone levels.

## Switching outputs and EasyEffects

- Select a real hardware device (internal speakers, USB DAC, Bluetooth headphones) as the default PipeWire output in the Sound panel or with `wpctl set-default <id>`.
- If you use **EasyEffects** for parametric EQ, leave your hardware device as the default sink rather than setting the virtual "Easy Effects Sink" as default; EasyEffects follows the active hardware output automatically. Configure per-device autoload presets in EasyEffects under **Presets → Autoload**.

## Custom device names and art (`devices.json`)

When an audio device connects or disconnects, kuwai shows a device card out of the notch with its name, status, and battery level (when reported). To map a USB DAC or headphones to a friendly name, icon kind, and image, create `~/.config/kuwai/devices.json` (read live, no restart required):

```json
[
  {
    "match": "USB Audio DAC",
    "label": "Studio Headphones",
    "via": "USB DAC",
    "image": "headphones.png",
    "kind": "headphones"
  }
]
```

- `match`: substring matching the PipeWire node name shown by `wpctl status`.
- `label`: display name shown on the card.
- `via`: optional DAC or adapter name.
- `kind`: `iem`, `headphones`, `earbuds`, or `speaker`.
- `image`: optional square transparent PNG in `~/.config/kuwai/devices/`.

Device cards stay quiet while the screen is locked or off and for 8 seconds after waking.
