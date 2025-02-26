const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const exe_native = b.addExecutable(.{
        .name = "mars",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
        .link_libc = true,
        .linkage = .dynamic
    });

    exe_native.linkSystemLibrary("glib-2.0");
    exe_native.linkSystemLibrary("ostree-1");

    b.installArtifact(exe_native);

    const run_cmd = b.addRunArtifact(exe_native);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
