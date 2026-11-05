# kitty-sidebar: compositor decoration research spike

Status: **build verified on Hyprland 0.57.1; never loaded; rendering and input unverified**.

Read [RESEARCH.md](RESEARCH.md) for the verdict, pinned source references, comparison,
and limits. Nothing here is installed or connected to the running shell.

## Build and pure feed checks

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

Output: `build/libkitty-sidebar.so`. Dependencies: installed Hyprland development
headers plus pkg-config modules in CMakeLists.txt; nlohmann/json.hpp.
The shared library intentionally has compositor symbols resolved by its host.
Do not load it in the desktop session. It is an unqualified research artifact.

## Safe baseline probe

```sh
python3 isolated-probe.py
```

Requires bubblewrap. This starts **only a new baseline compositor**, with its own
config, home, state and runtime beneath `.runs/`. It hides the host's DRM devices,
TTYs, `/run`, `/sys`, and session buses. It inherits no display address. It never
loads the plugin, starts kitty/Quickshell, or sends compositor IPC. It stops its own
process group after 20 seconds if necessary. There is no fallback to a live display.
`/mnt` inside the namespace maps to the private run directory, keeping Unix socket
paths short. All persistent artifacts stay inside this directory.

On this machine the probe exits 134: Aquamarine cannot obtain an allocator without
a DRM or nested Wayland backend. That is an environment/backend limitation before
plugin loading, **not a plugin crash**. See `evidence/headless-result.json` and the
ignored raw log `evidence/headless.log`.

## Source snapshots

Downloaded, ignored source trees in `vendor/`:

- `Hyprland`: tag v0.57.1, `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9`.
- `hyprland-plugins`: tag v0.57.0, `d2427d4d15b36df40468f5a58bbd67cdba19835d`.
- `aquamarine`: tag v0.16.0, `b77d67648336223a6c8fb88844ae316e7b72b574`.

They are reference material, not build dependencies or submodules. Pinned upstream
links in RESEARCH.md remain usable without these local checkouts.
