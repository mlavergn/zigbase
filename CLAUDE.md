# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zigbase` is the template other Zig projects are cloned from: a library
module, a CLI that exercises it, and a one-page web console. It is not a product —
nothing here should grow a feature that a clone would have to delete. Every body is
a placeholder around "Hello World"; a clone replaces them and keeps the shape.

`src/root.zig` exists solely so `zig build docs` has an autodoc root (autodoc will
not root at `module.zig`) — keep it in step with the barrel.

## Hard constraints

- **Zig 0.17.0** (`.minimum_zig_version` in `build.zig.zon`).
- **Never add an external dependency.** The module is std only. `.dependencies` holds only `zigbuildx` (`Deps`, `Xcode`), build-only, imported by `build.zig` and never by the module, pinned by `.url` + `.hash`, never `.path`.
- `build.zig.zon` is the source of truth for name and version; `build.zig` derives
  both from it. `.fingerprint` is derived from the name, so a clone needs a new one
  or the package will not build.
- `.paths = .{ "src" }` — only `src/` ships to consumers. Nothing in `cli/` or
  `web/` may be part of the library's public surface.
- Building on macOS resolves the Xcode SDK and hardcodes `.cpu_arch = .aarch64`;
  it fails with `error.FailedToResolveSDK` without an SDK. Apple Silicon only.

## Commands

`make validate` (`clean format lint build test`) is the pre-commit gate — run it
before declaring work done. `make help` and the Makefile cover the rest.

- `make test` runs three separate test binaries (`src/`, `cli/`, `web/` modules).
- `make demo` binds a random user-range port and opens a browser. `make docs`
  blocks, serving on `:8080` until interrupted.

Gotchas:

- `make format` runs under `/bin/sh`, which does not expand `**` recursively — it
  only reaches one directory deep. **`build.zig` at the root is never formatted by
  it**; run `zig fmt build.zig` explicitly.
- `-Dtest-filter=<str>` is declared but only feeds the `config` options module; it
  does not actually filter tests.
- `make lint` cannot fail on findings: every rule in `styleguide/zlint.json` is
  `warn` and `--deny-warnings` is not passed. Read the output, not the exit code.
- **For stdout/stderr use `std.Io.File.stdout().writerStreaming(io, &buf)`, not
  `.writer(...)`.** `writer()` defaults to *positional* writes, which interleave
  destructively with the streaming writes `std.log` makes to the same terminal.

## Style

`styleguide/ZIGSTYLE.md` is authoritative and imported below — conform code to it,
not the reverse. The rule most often broken by habit: **enum variants are
camelCase** (`.startOfBlock`), unlike Zig std.

**Before using any `std` API, check `styleguide/ZIGMIGRATE.md`.** Zig 0.16 removed
or reshaped a lot (`std.net`, `std.fs.File`, `std.crypto.random`,
`GeneralPurposeAllocator`, managed `std.ArrayList`). Never use a deprecated API,
and clear any deprecation warning in the same change that produced it.

`styleguide/` is vendored — do not edit it here; flag upstream if a rule is wrong.

@styleguide/ZIGSTYLE.md
