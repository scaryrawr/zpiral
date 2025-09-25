const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const touch_mod = b.createModule(.{
        .root_source_file = b.path("src/multitouch/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/zpiral/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const toml_mod = b.dependency("toml", .{
        .optimize = optimize,
        .target = target,
    }).module("toml");

    exe_mod.addImport("multitouch", touch_mod);
    exe_mod.addImport("toml", toml_mod);

    const sdk = std.zig.system.darwin.getSdk(b.allocator, &(target.result)) orelse
        @panic("no macOS SDK found");
    b.sysroot = sdk;

    linkFrameworks(b, sdk, touch_mod);
    linkFrameworks(b, sdk, exe_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zpiral",
        .root_module = touch_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zpiral",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = touch_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn linkFrameworks(b: *std.Build, sdk: []const u8, step: *std.Build.Module) void {
    step.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/usr/include" }) });
    step.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/Frameworks" }) });
    step.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/System/Library/PrivateFrameworks" }) });
    step.linkFramework("CoreFoundation", .{});
    step.linkFramework("MultitouchSupport", .{});
}
