const std = @import("std");
const os = std.os.linux;
const consts = @import("utils/consts.zig");
const ostree = @cImport({
    @cInclude("ostree-1/ostree.h");
});
const fcntl = @cImport({
    @cInclude("fcntl.h");
});
const mntent = @cImport({
    @cInclude("mntent.h");
});

extern threadlocal var errno: c_int;

pub const LibOstree = struct {
    version: *const [6:0]u8,
    deployment: ?*ostree.OstreeDeployment,
    sysroot: ?*ostree.OstreeSysroot,

    // factory
    pub fn init() LibOstree {
        // get the ostree deployment
        var _error: ?*ostree.GError = null;
        const _sysroot = ostree.ostree_sysroot_new(null);
        _ = ostree.ostree_sysroot_load(_sysroot, null, &_error);

        if (_error) | err | {
            std.log.err("{s}", .{ err.message });
            // handle error
            @panic("ostree_sysroot_load failed");
        }

        return LibOstree{
            .version = ostree.OSTREE_VERSION_S,
            .deployment = ostree.ostree_sysroot_get_booted_deployment(_sysroot),
            .sysroot = _sysroot,
        };
    }

    pub fn deployHead(self: *LibOstree) bool {
        // deploy the head of the default branch
        if (self.deployment) |deployment| {
            const _branch = ostree.ostree_deployment_get_origin(deployment);
            const _osName = ostree.ostree_deployment_get_osname(deployment);

            if (_branch) |branch| {
                const _origin = ostree.g_key_file_get_string(
                    branch,
                    "origin",
                    "refspec",
                    null
                );

                var _error: ?*ostree.GError = null;
                var _ret: ostree.gboolean = ostree.FALSE;
                const _repo = ostree.ostree_repo_new_default();
                _ret = ostree.ostree_repo_open(_repo, null, &_error);

                if (_error) | err | {
                    std.log.err("{s}", .{ err.message });
                    return false;
                }

                if (_repo) |repo| {
                    var _head: [*c]u8 = null;

                    _error = null;
                    _ret = ostree.ostree_repo_resolve_rev(
                        repo,
                        _origin,
                        ostree.FALSE,
                        &_head,
                        &_error
                    );

                    if (_error) | err | {
                        std.log.err("{s}", .{ err.message });
                        return false;
                    }

                    std.log.debug("{s}", .{ _head });
                    // cleanup possible leftovers
                    _error = null;
                    _ret = ostree.ostree_sysroot_prepare_cleanup(
                        self.sysroot,
                        null,
                        &_error
                    );

                    if (_error) | err | {
                        std.log.err("{s}", .{ err.message });
                        return false;
                    }

                    var _newDeployment: ?*ostree.OstreeDeployment = null;
                    _error = null;
                    _ret = ostree.ostree_sysroot_deploy_tree(
                        self.sysroot,
                        _osName,
                        _head,
                        branch,
                        null,
                        null,
                        &_newDeployment,
                        null, &_error
                    );

                    if (_error) | err | {
                        std.log.err("{s}", .{ err.message });
                        return false;
                    }

                    // write deployment
                    _error = null;
                    _ret = ostree.ostree_sysroot_simple_write_deployment(
                        self.sysroot,
                        _osName,
                        _newDeployment,
                        null,
                        ostree.OSTREE_SYSROOT_SIMPLE_WRITE_DEPLOYMENT_FLAGS_NO_CLEAN,
                        null,
                        &_error
                    );

                    if (_error) | err | {
                        std.log.err("{s}", .{ err.message });
                        return false;
                    }

                    // final cleanup
                    _error = null;
                    _ret = ostree.ostree_sysroot_cleanup(
                        self.sysroot,
                        null,
                        &_error
                    );

                    if (_error) | err | {
                        std.log.err("{s}", .{ err.message });
                        return false;
                    }

                    return true;
                }
            }
        }

        @panic("sysroot not found");
    }

    pub fn unlock(self: *LibOstree) bool {
        var _error: ?*ostree.GError = null;

        // unlock the ostree
        if (self.sysroot) |sysroot| {
            if (self.deployment) |deployment| {
                _ = ostree.ostree_sysroot_deployment_unlock(
                    sysroot,
                    deployment,
                    ostree.OSTREE_DEPLOYMENT_UNLOCKED_DEVELOPMENT,
                    null,
                    &_error
                );

                if (_error) | err | {
                    std.log.err("{s}", .{ err.message });
                    return false;
                } else {
                    return true;
                }
            }
        }

        @panic("sysroot/deployment not found");
    }

    pub fn getDeployHash(self: *LibOstree) ![*c]const u8 {
        // get the deployment hash
        if (self.deployment) |deployment| {
            return ostree.ostree_deployment_get_csum(deployment);
        }

        @panic("deployment not found");
    }

    pub fn isInDevMode(self: *LibOstree) bool {
        if (self.deployment) |deployment| {
            const _state = ostree.ostree_deployment_get_unlocked(deployment);

            if (_state == ostree.OSTREE_DEPLOYMENT_UNLOCKED_DEVELOPMENT) {
                return true;
            } else {
                return false;
            }
        }

        @panic("deployment not found");
    }

    pub fn getBranch(self: *LibOstree) ![*c]const u8 {
        if (self.deployment) |deployment| {
            return ostree.ostree_deployment_get_osname(deployment);
        }

        @panic("deployment not found");
    }

    fn _getMntOpt(opts: []const u8, key: []const u8) ?[]const u8 {
        var it = std.mem.tokenize(u8, opts, ",");
        while (it.next()) |entry| {
            if (
                std.mem.startsWith(u8, entry, key) and
                entry.len > key.len and entry[key.len] == '='
            ) {
                return entry[key.len + 1 ..];
            }
        }

        return null;
    }

    fn _prepareChangesPath() !void {
        const _file = mntent.setmntent("/proc/mounts", "r");
        if (_file) |file| {
            var _entry = mntent.getmntent(file);

            while (_entry) |entry| {
                const _typeS = consts.getStrinAsSlice(entry.*.mnt_type);

                if (std.mem.eql(u8, _typeS, "overlay")) {
                    const _optSlice = consts.getStrinAsSlice(entry.*.mnt_opts);
                    const _upperdir = _getMntOpt(_optSlice, "upperdir");

                    if (_upperdir) |upperdir| {
                        std.log.debug("upperdir: {s}", .{ upperdir });
                        const _upperdirSlash = try std.fmt.allocPrint(
                            std.heap.page_allocator,
                            "{s}/",
                            .{ upperdir }
                        );

                        try std.fs.makeDirAbsolute("/tmp/mars");
                        try std.fs.makeDirAbsolute("/tmp/mars/usr");

                        // do not try to reivent the wheel
                        // call rsync to copy all from upperdir to /tmp/mars/usr
                        const _args = [_][]const u8 {
                                    "rsync",
                                    "-a",
                                    _upperdirSlash,
                                    "/tmp/mars/usr"
                                };

                        _ = try std.process.Child.run(
                            .{
                                .allocator = std.heap.page_allocator,
                                .argv = &_args
                            }
                        );

                        return;
                    }

                    @panic("upperdir not found");
                }

                _entry = mntent.getmntent(file);
            }
        }

        @panic("failed to open /proc/mounts");
    }

    fn _changesPathCleanup() !void {
        const _args = [_][]const u8 {
            "rm",
            "-rf",
            "/tmp/mars"
        };

        _ = try std.process.Child.run(
            .{
                .allocator = std.heap.page_allocator,
                .argv = &_args
            }
        );
    }

    fn _abortTransaction(repo: *ostree.OstreeRepo, _err: ?*ostree.struct__GError) !void {
        if (_err) |err| {
            std.log.err("{s}", .{ err.message });
        }

        _ = ostree.ostree_repo_abort_transaction(repo, null, null);
        try _changesPathCleanup();
    }

    pub fn commit(self: *LibOstree) !bool {
        try _prepareChangesPath();

        // commit the dev diff
        if (self.deployment) |deployment| {
            var _error: ?*ostree.GError = null;
            var _ret: ostree.gboolean = ostree.FALSE;
            const _repo = ostree.ostree_repo_new_default();
            _ret = ostree.ostree_repo_open(_repo, null, &_error);

            if (_error) | err | {
                std.log.err("{s}", .{ err.message });
                return false;
            }

            if (_repo) |repo| {
                const _branch = ostree.ostree_deployment_get_origin(deployment);

                if (_branch) |branch| {
                    const _base = ostree.ostree_deployment_get_csum(deployment);
                    var _root: ?*ostree.OstreeRepoFile = null;
                    var _commitChecksum: [*c]const u8 = null;

                    const _origin = ostree.g_key_file_get_string(
                        branch,
                        "origin",
                        "refspec",
                        null
                    );


                    std.log.debug("branch: {s}", .{ _origin });
                    std.log.debug("base: {s}", .{ _base });

                    std.debug.print("preparing transaction...\n", .{});
                    _ret = ostree.ostree_repo_prepare_transaction(
                        repo,
                        null,
                        null,
                        &_error
                    );

                    if (_ret == ostree.FALSE) {
                        try _abortTransaction(repo, _error);
                        return false;
                    }

                    // create the commit
                    _error = null;
                    std.debug.print("creating commit...\n", .{});
                    const _mtree = ostree.ostree_mutable_tree_new_from_commit(
                        repo,
                        _base,
                        &_error
                    );

                    if (_error) | err | {
                        try _abortTransaction(repo, err);
                        return false;
                    }

                    _error = null;
                    std.debug.print("writing dir tree...\n", .{});
                    _ret = ostree.ostree_repo_write_dfd_to_mtree(
                        repo,
                        fcntl.AT_FDCWD,
                        "/tmp/mars",
                        _mtree,
                        null,
                        null,
                        &_error
                    );

                    if (_ret == ostree.FALSE) {
                        try _abortTransaction(repo, _error);
                        return false;
                    }

                    _error = null;
                    std.debug.print("writing mtree...\n", .{});
                    _ret = ostree.ostree_repo_write_mtree(
                        repo,
                        _mtree,
                        @ptrCast(&_root),
                        null,
                        &_error
                    );

                    if (_ret == ostree.FALSE) {
                        try _abortTransaction(repo, _error);
                        return false;
                    }

                    _error = null;
                    std.debug.print("writing commit...\n", .{});
                    _ret = ostree.ostree_repo_write_commit(
                        repo,
                        _base,
                        null,
                        null,
                        null,
                        _root,
                        @ptrCast(&_commitChecksum),
                        null,
                        &_error
                    );

                    if (_ret == ostree.FALSE) {
                        try _abortTransaction(repo, _error);
                        return false;
                    }

                    std.debug.print("setting branch...\n", .{});
                    ostree.ostree_repo_transaction_set_ref(
                        repo,
                        null,
                        _origin,
                        _commitChecksum
                    );

                    _error = null;
                    std.debug.print("end transaction... \n", .{});
                    _ret = ostree.ostree_repo_commit_transaction(
                        repo,
                        null,
                        null,
                        &_error
                    );

                    if (_ret == ostree.FALSE) {
                        try _abortTransaction(repo, _error);
                        return false;
                    }

                    try _changesPathCleanup();
                    return true;
                }
            }

            @panic("repo not found");
        }

        @panic("deployment not found");
    }
};
