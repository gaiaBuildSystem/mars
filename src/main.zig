const std = @import("std");
const clap = @import("clap");
const consts = @import("utils/consts.zig");
const libOstree = @import("libostree.zig");

fn _checkIfWeAreRoot() bool {
    // check if we are root
    const _uid = std.os.linux.getuid();
    if (_uid != 0) {
        std.log.err("Need super 🐮 powers", .{});
        return false;
    }

    return true;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const gpa = std.heap.page_allocator;
    var ostree = libOstree.LibOstree.init(gpa);
    const args = std.os.argv[1..std.os.argv.len];

    if (args.len == 0) {
        try stdout.print(consts.MARS_HELP_S, .{});
        return;
    }

    // check the arguments
    const _subcmd = consts.getMarsCommandHash(args[0]);

    switch (_subcmd) {
        .CMD_HELP => {
            try stdout.print(consts.MARS_HELP_S, .{});
        },
        .CMD_DEV => {
            if(_checkIfWeAreRoot()) {
                if (ostree.isInDevMode()) {
                    std.log.err("Already in dev mode", .{});
                    return;
                }

                const _ret = ostree.unlock();
                if (_ret)
                    try stdout.print("dev mode enabled\n", .{});
            }
        },
        .CMD_DEPLOY => {
            if (ostree.isInDevMode() and _checkIfWeAreRoot()) {
                const _ret = try ostree.deployHead();

                if (_ret) {
                    try stdout.print("deploy successful\n", .{});
                } else {
                    std.log.err("deploy failed", .{});
                }
            } else {
                std.log.err("Need to be in dev mode to deploy", .{});
            }
        },
        .CMD_DEPLOY_HASH => {
            const hash = try ostree.getDeployHash();
            try stdout.print("{s}\n", .{hash});
        },
        .CMD_COMMIT => {
            if (ostree.isInDevMode()) {
                const _ret = try ostree.commit();
                if (_ret) {
                    try stdout.print("commit successful\n", .{});
                } else {
                    std.log.err("commit failed", .{});
                }
            } else {
                std.log.err("Need to be in dev mode to commit", .{});
            }
        },
        .CMD_ROLLBACK => {
            std.log.err("NOT IMPLEMENTED", .{});
        },
        .CMD_VERSION => {
            try stdout.print("{s}\n", .{consts.MARS_VERSION_S});
        },
    }
}
