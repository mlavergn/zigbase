# Zig Base Template

A starting point for a Zig module — **not a project in its own right.** Clone it,
rename it, replace the placeholder code.

You get a library plus two ways to exercise it, so a fresh clone builds, tests,
runs, and serves before you have written anything. The placeholder feature is a
greeting.

## Layout

```
src/   the library     base.zig    the placeholder feature
cli/   a command       client.zig  what the command does
web/   a web console   server.zig  HTTP loop, listen port, browser launch
```

Every directory has a `module.zig` barrel — import through it, never a sibling
file. `cli/` and `web/` each have a `main.zig` entry point; `src/root.zig` exists
only so `zig build docs` has an autodoc root.

## Use it

```sh
make            # build, format, test
make validate   # the pre-commit gate: clean, format, lint, build, test
make run        # the CLI; `make run ARGS="Zig"` to greet something else
make demo       # the web console on a random port, opens a browser
```

`make help` lists the build steps; the Makefile has the rest.

## Making it yours

1. Set `.name`, `.description`, and `.version` in `build.zig.zon`.
2. Give it a fresh `.fingerprint` — it is derived from the package name, so a
   clone that keeps the old one will not build. Delete the line and let
   `zig build` tell you the value to use.
3. Replace `src/base.zig` with the real feature, and point `cli/client.zig` and
   `web/server.zig` at it. Update the `module.zig` barrels as you go.
4. Rename the `.<project>_<module>` log scopes.

## Conventions

`styleguide/ZIGSTYLE.md` is authoritative for style and layout;
`styleguide/ZIGMIGRATE.md` covers the Zig 0.17 API changes. Both are vendored
from a shared standard — follow them, don't edit them here.

Requires Zig 0.17.0. The module has no external dependencies and must keep it
that way.
