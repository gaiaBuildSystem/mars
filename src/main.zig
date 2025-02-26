const std = @import("std");
const clap = @import("clap");
const consts = @import("utils/consts.zig");
const libOstree = @import("libostree.zig");

fn _checkIfWeAreRoot() bool {
    // check if we are root
    const _uid = std.os.linux.getuid();
    if (_uid != 0) {
        std.log.err("Need super 🐮 powers to enable dev mode", .{});
        return false;
    }

    return true;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var ostree = libOstree.LibOstree.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = std.os.argv[1..std.os.argv.len];
    defer _ = gpa.deinit();

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
        }
    }
}
