# Architecture Decision Records

Decisions that shape kuwai's privilege boundaries, compositor behaviour, update
and migration safety, local AI sandbox, and helper architecture. Extracted from
non-obvious decision-record code comments so rationale lives in one durable
place instead of drifting inside source files.

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-privilege-and-process-boundaries.md) | Separate Privilege and Process Boundaries for Greeter, Polkit Auth, RTC Wake, and Screensaver Film | Accepted |
| [ADR-002](ADR-002-gpu-renderer-and-frame-scheduling.md) | Hybrid GPU Renderer Selection, Explicit Sync, and Frame Scheduling on Hyprland 0.57 | Accepted |
| [ADR-003](ADR-003-display-presets-and-hdr-detection.md) | Display Presets, Automatic Colour/HDR Management, and Wire-Level HDR Detection | Accepted |
| [ADR-004](ADR-004-workspaces-layer-namespaces-and-window-rules.md) | Per-Monitor Workspace Blocks, Layer Namespace Conventions, and Window Rules | Accepted |
| [ADR-005](ADR-005-channels-promotion-gates-and-landlock-migrations.md) | Stable/Dev Channels, Promotion Safety Gates, Backups, and Landlock-Fenced Migrations | Accepted |
| [ADR-006](ADR-006-local-assistant-sandbox-and-prompting.md) | Local AI Assistant Security Architecture, Per-Chat Container Jail, and Small-Model Prompting | Accepted |
| [ADR-007](ADR-007-system-update-and-pacnew-pipeline.md) | Single-Password System Update Pipeline and Three-Way `.pacnew` Classification | Accepted |
| [ADR-008](ADR-008-desktop-helpers-and-media-architecture.md) | Desktop Helpers Architecture (Brightness, Clipboard, Feeds, Media, and Usage/Spend) | Accepted |
| [ADR-009](ADR-009-typography-rendering-and-hyde-interop.md) | Typography, FreeType Rendering, and HyDE Interoperability | Accepted |
| [ADR-010](ADR-010-comment-ban-and-ratchet.md) | Code Comment Policy and Per-File Ratchet Enforcement | Accepted |
