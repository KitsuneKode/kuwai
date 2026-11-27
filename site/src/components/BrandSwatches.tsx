import { useState } from "react";

const SWATCHES: [string, string][] = [
  ["Desktop ground", "#0b0b0f"],
  ["Glass tint base", "#111114"],
  ["Solid surface", "#1c1c1f"],
  ["Accent (selection)", "#0a84ff"],
  ["Attention / warning", "#ff9f0a"],
  ["Positive / charging", "#30d158"],
  ["Critical / error", "#ff453a"],
  ["Search / Caffeine", "#ffd60a"],
  ["Focus / screen share", "#bf5af2"]
];

export default function BrandSwatches() {
  const [copiedHex, setCopiedHex] = useState<string | null>(null);

  const copy = async (hex: string) => {
    try {
      await navigator.clipboard.writeText(hex);
    } catch {}
    setCopiedHex(hex);
    window.setTimeout(() => setCopiedHex(null), 1200);
  };

  return (
    <div className="swatch-grid">
      {SWATCHES.map(([name, hex]) => (
        <button key={hex} type="button" className="swatch-btn" onClick={() => copy(hex)}>
          <span className="swatch-color" style={{ background: hex }} />
          <span className="swatch-name">{name}</span>
          <span className="swatch-hex tabular">{copiedHex === hex ? "Copied" : hex}</span>
        </button>
      ))}
    </div>
  );
}
