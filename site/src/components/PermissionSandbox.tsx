import { useState } from "react";

export default function PermissionSandbox() {
  const [status, setStatus] = useState<"pending" | "allowed" | "denied">("pending");

  return (
    <div className={`hook-sandbox${status === "allowed" ? " is-allowed" : status === "denied" ? " is-denied" : ""}`}>
      <div className="hook-header">
        <span className="hook-title">Native permission hook</span>
        <span className={`hook-meta tabular${status !== "pending" ? " is-done" : ""}`}>
          {status === "pending" ? "Fallback to terminal in 45s" : "Answered directly"}
        </span>
      </div>
      <div className="hook-body">
        <p className="hook-prompt">Claude Code in pane 2 asks to run:</p>
        <pre className="code-line"><code>git rebase --onto main feature/island-polish~2</code></pre>
        <div className="hook-actions">
          {status === "pending" ? (
            <>
              <button type="button" className="btn-primary btn-compact" onClick={() => setStatus("allowed")}>
                Allow
              </button>
              <button type="button" className="btn-secondary btn-compact" onClick={() => setStatus("denied")}>
                Deny
              </button>
            </>
          ) : (
            <button type="button" className="btn-quiet btn-compact" onClick={() => setStatus("pending")}>
              Replay prompt
            </button>
          )}
        </div>
        {status !== "pending" && (
          <p className="hook-result" aria-live="polite">
            {status === "allowed"
              ? "Approved through the native hook. Pane 2 resumes without pulling focus from your editor."
              : "Blocked before execution. Your active window stays untouched."}
          </p>
        )}
      </div>
    </div>
  );
}
