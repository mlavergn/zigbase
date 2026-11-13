const std = @import("std");
const log = std.log.scoped(.zigbase_build);
const builtin = @import("builtin");

const zon = @import("build.zig.zon");
const zigbuildx = @import("zigbuildx");

/// The CLI executable's name; a clone renames it. It must differ from
/// `app_name` by more than case, or the two overwrite each other in `bin/` on
/// a case-insensitive filesystem (macOS, Windows).
const cli_name = "zbase";
/// The native app's name, and its macOS bundle's; a clone renames it.
const app_name = "ZigBase";
/// The app's bundle identifier; a clone renames it.
const app_identifier = "com.example.zigbase";
/// The oldest macOS the builds run on, and the lowest `-Dmacos-min` accepts;
/// a full semantic version, so `std.SemanticVersion.parse` reads it.
const macos_min = "26.0.0";

/// The names, paths and options every part of the build graph shares, and
/// the helpers that declare its pieces from them.
const Config = struct {
    const Self = @This();

    /// The package name, from `build.zig.zon`.
    name: []const u8,
    /// The library module's import name.
    mod_name: []const u8,
    /// The CLI executable's name.
    cli_name: []const u8,
    /// The web console executable's name.
    web_name: []const u8,
    /// The resolved target, with the macOS floor applied.
    target: std.Build.ResolvedTarget,
    /// The optimize mode.
    optimize: std.lang.Optimize,
    /// The library's root source file.
    module_source_file: std.Build.LazyPath,
    /// The CLI's root source file.
    cli_source_file: std.Build.LazyPath,
    /// The package version, from `build.zig.zon`.
    version: std.SemanticVersion,

    /// Fails the build when the target is macOS with a floor below `macos_min`,
    /// whether `-Dmacos-min` or `-Dtarget`'s own version set it.
    ///
    /// - `self`: the build's configuration.
    /// - Returns: nothing when the floor holds; `error.MacosMinTooLow` otherwise.
    fn checkMacosFloor(self: *const Self) !void {
        if (self.target.result.os.tag != .macos) return;
        const floor = try std.SemanticVersion.parse(macos_min);
        const min = self.target.result.os.version_range.semver.min;
        if (min.order(floor) == .lt) {
            log.err("macOS {f} is below the {s} floor; raise -Dmacos-min, or give -Dtarget a version (aarch64-macos.{s})", .{ min, macos_min, macos_min });
            return error.MacosMinTooLow;
        }
    }

    /// Declares a test module over `root`: one executable's barrel, importing the
    /// library and `config` as that executable does.
    ///
    /// - `self`: the build's configuration.
    /// - `b`: the build graph.
    /// - `config_module`: the `config` options module.
    /// - `module`: the zigbase library module.
    /// - `root`: the barrel, relative to the build root.
    /// - Returns: the module.
    fn addTestModule(
        self: *const Self,
        b: *std.Build,
        config_module: *std.Build.Module,
        module: *std.Build.Module,
        root: []const u8,
    ) *std.Build.Module {
        const test_module = b.createModule(.{
            .root_source_file = b.path(root),
            .target = self.target,
            .optimize = self.optimize,
        });
        test_module.addImport("config", config_module);
        test_module.addImport(self.mod_name, module);
        return test_module;
    }

    /// Declares a test binary over `root_module` and runs it, every time, as part
    /// of `tests_step`.
    ///
    /// - `b`: the build graph.
    /// - `tests_step`: the `test` step.
    /// - `filters`: `-Dtest-filter`, or empty to run every test.
    /// - `root_module`: the module whose tests to run.
    fn addTestRun(b: *std.Build, tests_step: *std.Build.Step, filters: []const []const u8, root_module: *std.Build.Module) void {
        const tests = b.addTest(.{ .root_module = root_module, .filters = filters });
        const tests_run = b.addRunArtifact(tests);
        // force tests to run on every test run
        tests_run.has_side_effects = true;
        tests_step.dependOn(&tests_run.step);
    }

    /// Declares the native app and its `app` step: the executable, over ziggui's
    /// app barrel (`linkApp`, which links SDL3), installed by the default install
    /// step. On macOS it is a `ZigBase.app` bundle at the top of the prefix
    /// (`Info.plist` from build.zig.zon) whose executable carries the linker's
    /// ad-hoc signature; on Linux `bin/ZigBase` with a desktop entry under `share/`.
    ///
    /// - `self`: the build's configuration.
    /// - `b`: the build graph.
    /// - `config_module`: the `config` options module.
    /// - `module`: the zigbase library module.
    /// - `lib`: the library, which carries the macOS frameworks.
    /// - `ziggui_dep`: the ziggui dependency.
    /// - Returns: nothing; propagates macOS SDK resolution failure.
    fn addApp(
        self: *const Self,
        b: *std.Build,
        config_module: *std.Build.Module,
        module: *std.Build.Module,
        lib: *std.Build.Step.Compile,
        ziggui_dep: *std.Build.Dependency,
    ) !void {
        const ziggui_build = @import("ziggui");
        // An explicit macOS target needs the SDK spelled out.
        const xcode = try zigbuildx.Xcode.initFor(b, self.target);
        const ziggui_app_module = ziggui_build.linkApp(ziggui_dep, .{
            .target = self.target,
            .optimize = self.optimize,
            .macos_sdk = if (xcode.loaded) xcode.sdk else null,
        });

        const exe = b.addExecutable(.{
            .name = app_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("app/main.zig"),
                .target = self.target,
                .optimize = self.optimize,
                .link_libc = true,
            }),
        });
        exe.root_module.addImport("config", config_module);
        exe.root_module.addImport(self.mod_name, module);
        exe.root_module.addImport("ziggui", ziggui_app_module);
        exe.root_module.linkLibrary(lib);

        // A macOS `.app`, or on Linux `bin/ZigBase` with its desktop entry.
        const bundle: zigbuildx.AppBundle = .{
            .name = app_name,
            .identifier = app_identifier,
            .version = zon.version,
            .exe = exe,
            .comment = zon.description,
        };
        const install = zigbuildx.App.addInstall(b, bundle, null);
        b.step("app", "Build the native app (with -Dapp)").dependOn(install);
        b.getInstallStep().dependOn(install);
    }
};

/// Declares the build graph for the zigbase library, CLI, web console, native
/// app, tests, and docs.
///
/// Serves as the entry point the Zig build runner invokes to wire up every
/// build step consumers rely on — `lib`, `cli`, `run`, `web`, `serve`, `test`,
/// `docs`, `docs-serve`, and with `-Dapp` `app` — plus the standard target, optimize, and
/// test-filter options, and `-Dmacos-min`. On macOS it adds the resolved SDK
/// framework path so linking succeeds. Called once per build invocation.
///
/// - `b`: the build graph the steps and options are registered on.
/// - Returns: nothing on success; propagates errors from option parsing,
///   version parsing, the macOS floor check, and macOS SDK resolution.
pub fn build(b: *std.Build) !void {
    // Pre-flight: ensure any local dependencies are cloned
    zigbuildx.Deps.cloneMissing(b, zon);

    // Build config
    const cfg = Config{
        .name = @tagName(zon.name),
        .mod_name = @tagName(zon.name),
        .cli_name = cli_name,
        .web_name = @tagName(zon.name) ++ "-web",
        // `-Dtarget`, plus `-Dmacos-min`: the floor the binaries and the app's Info.plist state.
        .target = try zigbuildx.Xcode.standardTargetOptions(b, macos_min),
        .optimize = b.standardOptimizeOption(.{}),
        .module_source_file = b.path("src/module.zig"),
        .cli_source_file = b.path("cli/main.zig"),
        .version = try std.SemanticVersion.parse(zon.version),
    };

    try cfg.checkMacosFloor();

    // Build options
    const options = b.addOptions();
    // The GUI's name: the bundle, the window title and the desktop entry read it.
    options.addOption([:0]const u8, "app_name", app_name);

    // const app_bundle_id = b.option([]const u8, "appBundleId", "Set the appBundleId to use for sandbox contexts") orelse "com.example";
    // options.addOption([]const u8, "appBundleId", app_bundle_id);
    // cfg.app_bundle_id = app_bundle_id;

    // Each test binary runs only the tests whose names contain this text.
    const test_filter = b.option([]const u8, "test-filter", "Run unit tests that match filter");
    const test_filters: []const []const u8 = if (test_filter) |filter| b.dupeStrings(&.{filter}) else &.{};

    // One module over the options, so every module that imports `config` shares it.
    const config_module = options.createModule();

    // -------------------------------------------------------------------------
    // Module

    const module = b.addModule(cfg.name, .{
        .root_source_file = cfg.module_source_file,
        .target = cfg.target,
        .optimize = cfg.optimize,
    });
    module.addImport("config", config_module);
    module.addIncludePath(b.path("src"));

    // -------------------------------------------------------------------------
    // Lib

    const lib = b.addLibrary(.{ .name = cfg.name, .root_module = module, .linkage = .static });
    lib.root_module.addImport("config", config_module);
    lib.root_module.addIncludePath(b.path("src"));

    if (builtin.os.tag == .macos) {
        var xcode = try zigbuildx.Xcode.init(b);
        try xcode.resolve();
        xcode.addFrameworkPath(lib.root_module);
    }

    const lib_install = b.addInstallArtifact(lib, .{});
    const lib_step = b.step("lib", "Build static library");
    lib_step.dependOn(&lib_install.step);

    // -------------------------------------------------------------------------
    // CLI

    const cli_module = b.createModule(.{
        .root_source_file = cfg.cli_source_file,
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    const cli = b.addExecutable(.{
        .name = cfg.cli_name,
        .root_module = cli_module,
    });
    cli.root_module.addImport("config", config_module);
    cli.root_module.addImport(cfg.mod_name, module);

    cli.root_module.addIncludePath(b.path("src"));
    cli.root_module.linkLibrary(lib);

    // depend on lib being built
    cli.step.dependOn(&lib.step);
    b.installArtifact(cli);

    const cli_install = b.addInstallArtifact(cli, .{});
    const cli_step = b.step("cli", "Build the CLI app");
    cli_step.dependOn(&cli_install.step);

    // -------------------------------------------------------------------------
    // Web console

    const web_module = b.createModule(.{
        .root_source_file = b.path("web/main.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    const web = b.addExecutable(.{
        .name = cfg.web_name,
        .root_module = web_module,
    });
    web.root_module.addImport("config", config_module);
    web.root_module.addImport(cfg.mod_name, module);
    web.root_module.addIncludePath(b.path("src"));
    web.root_module.linkLibrary(lib);

    web.step.dependOn(&lib.step);
    b.installArtifact(web);

    const web_install = b.addInstallArtifact(web, .{});
    const web_step = b.step("web", "Build the web console");
    web_step.dependOn(&web_install.step);

    const web_run = b.addRunArtifact(web);
    web_run.step.dependOn(b.getInstallStep());
    web_run.addPassthruArgs();

    const web_run_step = b.step("serve", "Run the web console");
    web_run_step.dependOn(&web_run.step);

    // -------------------------------------------------------------------------
    // GUI

    // The native app (`app/`), drawn by ziggui. Its modules build and test
    // headless on ziggui's core barrel; the executable, which links SDL3
    // through ziggui's `linkApp`, is configured only with `-Dapp`, so a plain
    // `zig build` never fetches SDL.
    const ziggui_dep = b.dependency("ziggui", .{
        .target = cfg.target,
        .optimize = cfg.optimize,
    });

    if (b.option(bool, "app", "Build the native app (fetches and builds SDL3)") orelse false) {
        try cfg.addApp(b, config_module, module, lib, ziggui_dep);
    }

    // -------------------------------------------------------------------------
    // Run

    const cli_run = b.addRunArtifact(cli);

    // Run step depends on the install step to run from the installation directory
    cli_run.step.dependOn(b.getInstallStep());

    // Support arguments like: `zig build run -- argA argB`
    cli_run.addPassthruArgs();

    const run_step = b.step("run", "Run the CLI app");
    run_step.dependOn(&cli_run.step);

    // -------------------------------------------------------------------------
    // Tests

    const tests_step = b.step("test", "Run unit tests");

    // The library, then each executable's barrel as its own module, so each
    // gets its own compile step. The GUI's is over ziggui's core barrel: no SDL.
    Config.addTestRun(b, tests_step, test_filters, module);
    Config.addTestRun(b, tests_step, test_filters, cfg.addTestModule(b, config_module, module, "cli/module.zig"));
    Config.addTestRun(b, tests_step, test_filters, cfg.addTestModule(b, config_module, module, "web/module.zig"));
    const gui_tests_module = cfg.addTestModule(b, config_module, module, "app/module.zig");
    gui_tests_module.addImport("ziggui", ziggui_dep.module("ziggui"));
    Config.addTestRun(b, tests_step, test_filters, gui_tests_module);

    // -------------------------------------------------------------------------
    // Docs

    // Autodoc roots a module at `root.zig`, or failing that at the file whose
    // basename matches the artifact name; with `src/module.zig` it can do
    // neither, and the site roots itself at an arbitrary import instead.
    // ZIGSTYLE requires the barrel to be `module.zig`, so docs build from a
    // sibling `root.zig`. It is the same module — the other sources come along.
    const docs_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = cfg.target,
        .optimize = cfg.optimize,
    });
    docs_mod.addImport("config", config_module);
    docs_mod.addIncludePath(b.path("src"));

    const docs_lib = b.addLibrary(.{
        .name = cfg.name,
        .root_module = docs_mod,
        .linkage = .static,
    });

    if (builtin.os.tag == .macos) {
        var docs_xcode = try zigbuildx.Xcode.init(b);
        try docs_xcode.resolve();
        docs_xcode.addFrameworkPath(docs_lib.root_module);
    }

    const docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    // Serves the site on a free loopback port and opens the browser; no python3.
    const docs_serve_step = b.step("docs-serve", "Serve the documentation until interrupted");
    docs_serve_step.dependOn(zigbuildx.Docs.addServe(b, docs_lib.getEmittedDocs(), 0));
}
