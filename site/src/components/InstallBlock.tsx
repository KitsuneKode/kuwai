import { useState } from "react";

const COMMANDS = `git clone https://github.com/KitsuneKode/kuwai.git ~/Projects/kuwai
cd ~/Projects/kuwai && ./install.sh --dry-run
./install.sh --deps
bin/kuwai doctor`;

export default function InstallBlock() {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(COMMANDS);
    } catch {}
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  };

  return (
    <div className="terminal-box">
      <div className="terminal-bar">
        <span className="terminal-label">Arch Linux with Hyprland 0.57</span>
        <button type="button" className="btn-quiet btn-compact" onClick={handleCopy}>
          {copied ? "Copied" : "Copy commands"}
        </button>
      </div>
      <pre className="terminal-code"><code>{COMMANDS}</code></pre>
    </div>
  );
}
