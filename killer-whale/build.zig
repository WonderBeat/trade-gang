const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const test_step = b.step("test", "Run unit tests");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const target_str = switch (target.query.cpu_arch.?) {
    //     .arm, .armeb => "arm",
    //     .x86 => "x86",
    //     else => "",
    // };

    //const name = try std.fmt.allocPrint(b.allocator, "app-{s}", .{target_str});
    const exe = b.addExecutable(.{
        .name = "app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(b.path("."));

    const dep_curl = b.dependency("curl", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("curl", dep_curl.module("curl"));
    exe.linkLibC();

    const dep_log = b.dependency("nexlog", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("nexlog", dep_log.module("nexlog"));
    // const ymlz = b.dependency("ymlz", .{});
    // exe.root_module.addImport("ymlz", ymlz.module("root"));
    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
    });
    unit_tests.root_module.addImport("curl", dep_curl.module("curl"));
    unit_tests.root_module.addImport("zlog", dep_log.module("nexlog"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
