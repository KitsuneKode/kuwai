import { useState } from "react";

const SWATCHES: [string, string][] = [
  ["Desktop ground", "#0b0b0f"],
  ["Liquid glass tint", "#111114"],
  ["Elevated solid", "#1c1c1f"],
  ["Selection accent", "#0a84ff"],
  ["Attention and ask", "#ff9f0a"],
  ["Healthy and ready", "#30d158"],
  ["Critical and error", "#ff453a"],
  ["Focus and share", "#bf5af2"]
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
