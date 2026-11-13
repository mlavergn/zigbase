# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zigbase` is the template other Zig projects are cloned from: a library module, a
CLI that exercises it, a one-page web console, and a native app (`app/`, ziggui). It
is not a product — nothing here should grow a feature that a clone would have to
delete. Every body is a placeholder around "Hello World"; a clone replaces them and
keeps the shape.

A clone with no GUI deletes `app/`, the `-Dapp` block and its helpers in `build.zig`
(`Config.addApp`, the GUI test module), the `ziggui` dependency, and the `app`
Makefile targets.

`app/` stays as minimal as `cli/` and `web/`: one window, no icon (`AppBundle`'s
`.icns`/`.png` are null; a clone adds its own), and no menus, settings,
single-instance lock, `--screenshot`, theming or design tokens. `../zigmcp`'s
`app/` is the reference for all of those, and `../styleguide/GUIDESIGN.md` governs
a clone that grows them.

`src/root.zig` exists solely so `zig build docs` has an autodoc root (autodoc will
not root at `module.zig`) — keep it in step with the barrel.

## Hard constraints

- **Zig 0.17.1** (`.minimum_zig_version` in `build.zig.zon`; ziggui and zigbuildx
  require it).
- **Never add a third-party dependency.** Local (first-party) dependencies are fine. `.dependencies` holds:
  - `zigbuildx` (`Deps`, `Xcode`, `App`, `Docs`): build-only, imported by `build.zig` and never by the module, pinned by `.url` + `.hash`, never `.path`.
  - `ziggui`: a sibling `.path` (`../ziggui`) with `.clone`, which `Deps.cloneMissing` clones when missing. Only `app/` imports it.
  - SDL3 is ziggui's own third-party dependency, the one exception. It is lazy and fetched only through `linkApp`, under `-Dapp`, so a plain `zig build` or `test` never fetches it.
- **macOS 26.0 is the floor** (`macos_min` in `build.zig`, a full semver: `26.0.0`). `zigbuildx.Xcode.standardTargetOptions`
  stamps it on every artifact; `-Dmacos-min` may raise it, and `Config.checkMacosFloor` fails
  configure for any macOS target below it, including a versioned `-Dtarget`.
- `build.zig.zon` is the source of truth for name and version; `build.zig` derives
  both from it. `.fingerprint` is derived from the name, so a clone needs a new one
  or the package will not build.
- `.paths = .{ "src" }` — only `src/` ships to consumers. Nothing in `cli/`,
  `web/` or `app/` may be part of the library's public surface.
- Building on macOS resolves the Xcode SDK and hardcodes `.cpu_arch = .aarch64`;
  it fails with `error.FailedToResolveSDK` without an SDK. Apple Silicon only.

## Commands

`make validate` (`clean format lint build test`) is the pre-commit gate — run it
before declaring work done. `make format`, `make lint`, and `make validate` come
from `../styleguide/Makefile.in`. `make help` and the Makefile cover the rest.

- `zig build test -Dtest-filter=<text>` runs only the tests whose names contain
  `<text>`, in each binary.
- `make test` runs four separate test binaries (`src/`, `cli/`, `web/`, and `app/`
  on ziggui's core barrel, with no SDL).
- `make app` builds the native app (`zig build app -Dapp --release=fast`) and opens
  `zig-out/ZigBase.app`; on Linux it runs `zig-out/bin/ZigBase`. `make install-app`
  installs it: the bundle to `APP_DIR` (`~/Applications`) on macOS; on Linux
  `~/.local/bin/ZigBase` plus its desktop entry. `make install` stays CLI-only
  (`~/.local/bin/zbase`). The first `-Dapp` build fetches and compiles SDL3.
- **Never call `codesign` (or other Xcode command-line tools) from the Makefile** —
  they are not guaranteed to be installed. Zig's linker ad-hoc signs the arm64
  executable, which is enough for the bundle to run locally.
- `make demo` binds a random user-range port and opens a browser. `make docs`
  writes `zig-out/docs`, then serves it (`zig build docs-serve`, zigbuildx's
  `Docs.addServe`) on a free loopback port, opens a browser, and blocks until
  interrupted. No `python3`.

Gotchas:

- `app/main.zig` is compiled only by `-Dapp`, which `make validate` does not run;
  after touching it, run `zig build -Dapp`. The tests run `app/module.zig` as its
  own module over ziggui's core barrel (`Config.addTestModule`, `Config.addTestRun`); the executable's root
  `app/main.zig` imports the barrel directly, over `linkApp`'s app barrel. Every
  module shares one `config` module (`options.createModule()`), since a file may
  belong to only one module.
- `build.zig` keeps behavior on `Config` (C.1.a): the free `build` function
  Zig requires calls `Config` methods (`checkMacosFloor`, `addTestModule`,
  `addTestRun`, `addApp`). New build helpers go there too.
- `zigbuildx.App.addInstall` writes the bundle's `Info.plist` and the Linux desktop
  entry; don't hand-write either. `cli_name`, `app_name` and `app_identifier` in
  `build.zig` (`zbase`, `ZigBase`, `com.example.zigbase`) are placeholders a clone
  renames; the Makefile reads `APP_NAME` from `app_name`. The package, module and library
  stay `zigbase`; only the CLI executable is `zbase`.
- **`cli_name` and `app_name` must differ by more than case.** Both install to
  `bin/` (Linux and Windows layouts), and on a case-insensitive filesystem
  `zigbase` and `ZigBase` are one file that each build overwrites.
- `make lint` fails on any finding: zlintpre's summary is checked, and zlint runs
  with `-c ../styleguide --deny-warnings`, so warnings are errors. New source roots
  go in `ZIG_DIRS` in the Makefile.
- **For stdout/stderr use `std.Io.File.stdout().writerStreaming(io, &buf)`, not
  `.writer(...)`.** `writer()` defaults to *positional* writes, which interleave
  destructively with the streaming writes `std.log` makes to the same terminal.

## Style

`../styleguide/ZIGSTYLE.md` is authoritative and imported below — conform code to it,
not the reverse. The rule most often broken by habit: **enum variants are
camelCase** (`.startOfBlock`), unlike Zig std.

**Before using any `std` API, check `../styleguide/ZIGMIGRATE.md`.** Zig 0.16 removed
or reshaped a lot (`std.net`, `std.fs.File`, `std.crypto.random`,
`GeneralPurposeAllocator`, managed `std.ArrayList`). Never use a deprecated API,
and clear any deprecation warning in the same change that produced it.

`../styleguide` is the shared sibling checkout (its own repo) — never edit it from
this repo; flag upstream if a rule is wrong.

@../styleguide/ZIGSTYLE.md
