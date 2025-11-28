const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run unit tests");
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const output_name = b.option([]const u8, "output", "output file name") orelse "app";
    const verbose = b.option([]const u8, "verbose", "verbose mode") != null;
    const only_binary = b.option(bool, "only-binary", "generate binary with tests") == true;
    const test_options = b.addOptions();
    test_options.addOption(bool, "only-binary", only_binary);
    const options = b.addOptions();
    options.addOption(bool, "verbose", verbose);

    const backend = b.option(
        []const u8,
        "backend",
        "Override the default aio backend (io_uring, epoll, kqueue, iocp, wasi_poll)",
    );

    const root_module = b.addModule("root", .{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
        .strip = optimize != .Debug,
    });

    const exe = b.addExecutable(.{
        .name = output_name,
        .root_module = root_module,
    });
    exe.root_module.addOptions("config", options);
    exe.addIncludePath(b.path("."));

    const zio = b.dependency("zio", .{ .target = target, .optimize = optimize, .backend = backend });
    const simdjzon = b.dependency("simdjzon", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zio", zio.module("zio"));
    exe.root_module.addImport("simdjzon", simdjzon.module("simdjzon"));
    // const tardy = b.dependency("tardy", .{ .target = target, .optimize = optimize }).module("tardy");
    // exe.root_module.addImport("tardy", tardy);

    const websocket = b.dependency("websocket", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("websocket", websocket.module("websocket"));

    const metrics_dep = b.dependency("metrics", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("metrics", metrics_dep.module("metrics"));

    //exe.linkLibC();

    //const dep_log = b.dependency("nexlog", .{ .optimize = optimize });
    //exe.root_module.addImport("nexlog", dep_log.module("nexlog"));
    const dep_zeit = b.dependency("zeit", .{ .optimize = optimize });
    exe.root_module.addImport("zeit", dep_zeit.module("zeit"));

    // const ymlz = b.dependency("ymlz", .{});
    // exe.root_module.addImport("ymlz", ymlz.module("root"));

    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_module = b.addModule("test", .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
        }),
    });

    unit_tests.root_module.addOptions("only-binary", test_options);
    unit_tests.root_module.addImport("zeit", dep_zeit.module("zeit"));
    unit_tests.root_module.addImport("metrics", metrics_dep.module("metrics"));
    unit_tests.root_module.addImport("zio", zio.module("zio"));
    unit_tests.root_module.addImport("websocket", websocket.module("websocket"));
    unit_tests.root_module.addImport("simdjzon", simdjzon.module("simdjzon"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_binary = b.addInstallArtifact(unit_tests, .{});
    if (only_binary) {
        test_step.dependOn(&test_binary.step);
    } else {
        test_step.dependOn(&run_unit_tests.step);
    }

    const exe_check = b.addExecutable(.{
        .name = "binance_trade_cache_check",
        .root_module = root_module,
    });

    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);
}
