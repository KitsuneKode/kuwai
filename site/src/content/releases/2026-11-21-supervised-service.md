---
title: "Supervised desktop service and zero orphaned processes"
summary: "Moved the desktop shell into a dedicated systemd user unit with automatic fallback, cgroup teardown, and 1.1-second recovery."
date: 2026-11-21T11:00:00Z
category: "Resilience"
slugId: "supervised-service"
---

The desktop shell now runs under a dedicated user service with strict child-process lifecycle control. Streaming helpers terminate cleanly with the shell, eliminating over a hundred orphaned background processes and recovering automatically in 1.1 seconds if anything crashes.
