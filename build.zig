const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const xml = b.addModule("xml", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/xml.zig"),
    });
    const test_exe = b.addTest(.{ .root_module = xml });
    const run_test_exe = b.addRunArtifact(test_exe);
    const run_test_step = b.step("test", "Run tests.");
    run_test_step.dependOn(&run_test_exe.step);
    addExample(b, xml, target, optimize, "simple");
}

fn addExample(
    b: *std.Build,
    xml: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
) void {
    const exe = b.addExecutable(.{ .name = name, .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("examples/" ++ name ++ ".zig"),
    }) });
    exe.root_module.addImport("xml", xml);
    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step(name, "Run \"" ++ name ++ "\" example");
    run_step.dependOn(&run_exe.step);
}
