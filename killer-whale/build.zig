const std = @import("std");
const builtin = @import("builtin");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) !void {
    const test_step = b.step("test", "Run unit tests");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const app_name = b.option([]const u8, "app", "Application to build") orelse "binance";
    const output_name = b.option([]const u8, "output", "output file name");
    const verbose = b.option([]const u8, "verbose", "verbose mode") != null;
    const options = b.addOptions();
    options.addOption(bool, "verbose", verbose);

    const exe = b.addExecutable(.{
        .name = output_name orelse app_name,
        .root_source_file = b.path(try getMainFile(app_name)),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("config", options);
    exe.addIncludePath(b.path("."));

    const fastfilter_dep = b.dependency("fastfilter", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("fastfilter", fastfilter_dep.module("fastfilter"));

    const simdjzon_dep = b.dependency("simdjzon", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("simdjzon", simdjzon_dep.module("simdjzon"));

    const metrics_dep = b.dependency("metrics", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("metrics", metrics_dep.module("metrics"));

    const mqttz_dep = b.dependency("mqttz", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("mqttz", mqttz_dep.module("mqttz"));

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));

    const dep_curl = b.dependency("curl", .{ .target = target, .optimize = optimize, .link_vendor = false });
    dep_curl.builder.addSearchPrefix("/usr/include");

    dep_curl.module("curl").addIncludePath(.{ .cwd_relative = "/usr/include" });
    dep_curl.module("curl").addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/curl/include" });
    dep_curl.module("curl").addIncludePath(.{ .cwd_relative = "/usr/include/x86_64-linux-gnu" });

    exe.root_module.addImport("curl", dep_curl.module("curl"));

    exe.linkSystemLibrary("curl");
    //exe.linkLibC();

    //const dep_log = b.dependency("nexlog", .{ .target = target, .optimize = optimize });
    //exe.root_module.addImport("nexlog", dep_log.module("nexlog"));
    const dep_zeit = b.dependency("zeit", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zeit", dep_zeit.module("zeit"));

    // const ymlz = b.dependency("ymlz", .{});
    // exe.root_module.addImport("ymlz", ymlz.module("root"));

    exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
    switch (target.query.cpu_arch orelse .x86_64) {
        .x86_64 => if (dir_exists("/usr/lib/x86_64-linux-gnu")) {
            exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
        },
        .aarch64 => if (dir_exists("/usr/lib/aarch64-linux-gnu")) {
            exe.addLibraryPath(.{ .cwd_relative = "/usr/lib/aarch64-linux-gnu" });
        },
        else => {
            return error.Undef;
        },
    }

    exe.addIncludePath(.{ .cwd_relative = "/usr/include/" });

    const yazap = b.dependency("yazap", .{});
    exe.root_module.addImport("yazap", yazap.module("yazap"));

    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path(try getMainFile(app_name)),
        .target = target,
    });

    unit_tests.root_module.addOptions("config", options);

    unit_tests.root_module.addImport("yazap", yazap.module("yazap"));
    unit_tests.root_module.addImport("curl", dep_curl.module("curl"));
    unit_tests.root_module.addImport("zeit", dep_zeit.module("zeit"));
    unit_tests.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));
    unit_tests.root_module.addImport("mqttz", mqttz_dep.module("mqttz"));
    unit_tests.root_module.addImport("metrics", metrics_dep.module("metrics"));
    unit_tests.root_module.addImport("simdjzon", simdjzon_dep.module("simdjzon"));
    unit_tests.root_module.addImport("fastfilter", fastfilter_dep.module("fastfilter"));
    unit_tests.linkSystemLibrary("curl");

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_binary = b.addInstallArtifact(unit_tests, .{});
    test_step.dependOn(&test_binary.step);
    test_step.dependOn(&run_unit_tests.step);

    const gen_proto = b.step("gen-proto", "generates zig files from protocol buffer definitions");

    const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
        // out directory for the generated zig files
        .destination_directory = b.path("src/proto"),
        .source_files = &.{
            "protocol/all.proto",
        },
        .include_directories = &.{},
    });

    gen_proto.dependOn(&protoc_step.step);
}

fn getMainFile(app_name: []const u8) ![]const u8 {
    return switch (std.mem.eql(u8, app_name, "upbit")) {
        true => "src/upbit.zig",
        false => "src/main.zig",
    };
}

pub fn dir_exists(directory: []const u8) bool {
    if (std.fs.cwd().statFile(directory)) |_| {
        return true;
    } else |_| {
        return false;
    }
}
