const std = @import("std");

pub const MARS_VERSION_S = "0.0.2";

pub const MARS_HELP_S =
\\
\\ mars [subcommand]
\\
\\ Subcommands:
\\      commit           - Commit the dev diff
\\      dev              - Set the device to develop mode
\\      deploy           - Deploy the head of the default branch
\\      deploy-hash      - Get the booted deployment hash
\\      help             - Print this help message
\\      info             - Show information about the current state of deployment
\\      rollback         - Rollback the deployment to the previous commit
\\
\\
;

pub const MarsCommands = enum {
    CMD_COMMIT,
    CMD_DEV,
    CMD_DEPLOY,
    CMD_DEPLOY_HASH,
    CMD_ROLLBACK,
    CMD_HELP,
    CMD_INFO,
    CMD_VERSION
};

pub fn getStrinAsSlice(str: [*:0]u8) []u8 {
    return str[0..std.mem.len(str)];
}

pub fn getMarsCommandHash(command: [*:0]u8) MarsCommands {
    const _slice = getStrinAsSlice(command);

    if (std.mem.eql(u8, _slice, "commit")) {
        return MarsCommands.CMD_COMMIT;
    }

    if (std.mem.eql(u8, _slice, "dev")) {
        return MarsCommands.CMD_DEV;
    }

    if (std.mem.eql(u8, _slice, "deploy")) {
        return MarsCommands.CMD_DEPLOY;
    }

    if (std.mem.eql(u8, _slice, "deploy-hash")) {
        return MarsCommands.CMD_DEPLOY_HASH;
    }

    if (std.mem.eql(u8, _slice, "help")) {
        return MarsCommands.CMD_HELP;
    }

    if (std.mem.eql(u8, _slice, "info")) {
        return MarsCommands.CMD_INFO;
    }

    if (std.mem.eql(u8, _slice, "rollback")) {
        return MarsCommands.CMD_ROLLBACK;
    }

    if (std.mem.eql(u8, _slice, "version")) {
        return MarsCommands.CMD_VERSION;
    }

    std.log.err("command [{s}] not found", .{ _slice });

    // return a default value
    return MarsCommands.CMD_HELP;
}
