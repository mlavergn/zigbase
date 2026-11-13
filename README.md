# Zig Base Template

A starting point for a Zig module — **not a project in its own right.** Clone it,
rename it, replace the placeholder code.

You get a library plus three ways to exercise it, so a fresh clone builds, tests,
runs, and serves before you have written anything. The placeholder feature is a
greeting.

## Layout

```
src/   the library     base.zig    the placeholder feature
cli/   a command       client.zig  what the command does
web/   a web console   server.zig  HTTP loop, listen port, browser launch
app/   a native app    window.zig  the window's view tree (ziggui)
```

Every directory has a `module.zig` barrel — import through it, never a sibling
file. `cli/`, `web/` and `app/` each have a `main.zig` entry point; `src/root.zig`
exists only so `zig build docs` has an autodoc root.

## Use it

```sh
make              # build, format, test
make validate     # the pre-commit gate: clean, format, lint, build, test
make run          # the CLI (zbase); `make run ARGS="Zig"` to greet something else
make demo         # the web console on a random port, opens a browser
make install      # the release CLI into ~/.local/bin/zbase
make app          # the native app (ZigBase.app on macOS), built and opened
make install-app  # the app into ~/Applications (Linux: ~/.local/bin + desktop entry)
```

`make help` lists the build steps; the Makefile has the rest.

## Making it yours

1. Set `.name`, `.description`, and `.version` in `build.zig.zon`.
2. Give it a fresh `.fingerprint` — it is derived from the package name, so a
   clone that keeps the old one will not build. Delete the line and let
   `zig build` tell you the value to use.
3. Replace `src/base.zig` with the real feature, and point `cli/client.zig`,
   `web/server.zig` and `app/window.zig` at it. Update the `module.zig` barrels as
   you go.
4. Rename the `.<project>_<module>` log scopes.
5. Rename the executables: `cli_name`, `app_name` and `app_identifier` in
   `build.zig`. The CLI and app names must differ by
   more than case. No GUI? Delete `app/`, the `-Dapp` block in `build.zig`, the
   `ziggui` dependency, and the `app` Makefile targets.

## Conventions

Requires Zig 0.17.1 and, on macOS, 26.0 or later. No third-party dependencies;
first-party ones (zigbuildx, and ziggui for `app/`) are fine. SDL3 arrives through
ziggui, and only for `-Dapp` builds.
