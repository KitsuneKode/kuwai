import { useState } from "react";

const VERIFY = `git clone https://github.com/KitsuneKode/kuwai.git ~/Projects/kuwai
~/Projects/kuwai/bin/kuwai-setup --verify-only`;

const INSTALL = `~/Projects/kuwai/bin/kuwai-setup --deps
kuwai doctor`;

type CopyState = "idle" | "copied" | "failed";

export default function InstallBlock() {
  const [verifyState, setVerifyState] = useState<CopyState>("idle");
  const [installState, setInstallState] = useState<CopyState>("idle");

  const copy = async (text: string, set: (s: CopyState) => void) => {
    try {
      if (!navigator.clipboard?.writeText) {
        set("failed");
        return;
      }
      await navigator.clipboard.writeText(text);
      set("copied");
    } catch {
      set("failed");
    }
    window.setTimeout(() => set("idle"), 2200);
  };

  const label = (state: CopyState) =>
    state === "copied" ? "Copied" : state === "failed" ? "Copy failed" : "Copy";

  return (
    <div className="install-steps">
      <div className="terminal-box">
        <div className="terminal-bar">
          <span className="terminal-label">Step 1 · Verify the release</span>
          <button
            type="button"
            className="btn-quiet btn-compact"
            onClick={() => copy(VERIFY, setVerifyState)}
          >
            {label(verifyState)}
          </button>
        </div>
        <pre className="terminal-code">
          <code>{VERIFY}</code>
        </pre>
        <p className="terminal-foot">
          Confirms the signature and file tree before anything is installed.
        </p>
      </div>

      <div className="terminal-box">
        <div className="terminal-bar">
          <span className="terminal-label">Step 2 · Install and check</span>
          <button
            type="button"
            className="btn-quiet btn-compact"
            onClick={() => copy(INSTALL, setInstallState)}
          >
            {label(installState)}
          </button>
        </div>
        <pre className="terminal-code">
          <code>{INSTALL}</code>
        </pre>
        <p className="terminal-foot">
          After install, choose <strong>kuwai</strong> at login. Run{" "}
          <a href="https://github.com/KitsuneKode/kuwai/blob/main/docs/manual/install.md" className="inline-link">
            kuwai doctor
          </a>{" "}
          if something looks wrong, or{" "}
          <a href="https://github.com/KitsuneKode/kuwai/blob/main/docs/manual/install.md#uninstall" className="inline-link">
            install.sh --uninstall
          </a>{" "}
          to put your old files back.
        </p>
      </div>
    </div>
  );
}