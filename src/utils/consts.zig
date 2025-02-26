const std = @import("std");

pub const MARS_VERSION_S = "0.0.0";

pub const MARS_HELP_S =
\\
\\ mars [subcommand] [args]
\\
\\ Subcommands:
\\      commit           - Commit the dev diff
\\      dev              - Set the device to develop mode
\\      deploy-hash      - Get the booted deployment hash
\\      help             - Print this help message
\\
\\
;

pub const MarsCommands = enum {
    CMD_COMMIT,
    CMD_DEV,
    CMD_DEPLOY_HASH,
    CMD_HELP,
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

    if (std.mem.eql(u8, _slice, "deploy-hash")) {
        return MarsCommands.CMD_DEPLOY_HASH;
    }

    if (std.mem.eql(u8, _slice, "help")) {
        return MarsCommands.CMD_HELP;
    }

    std.log.err("command [{s}] not found", .{ _slice });
    return MarsCommands.CMD_HELP;
}
