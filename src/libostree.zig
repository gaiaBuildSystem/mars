const std = @import("std");
const os = std.os.linux;
const consts = @import("utils/consts.zig");
const format = @import("utils/ansi_term/src/format.zig");
const term = @import("utils/ansi_term/src/terminal.zig");
const style = @import("utils/ansi_term/src/style.zig");
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
    allocator: std.mem.Allocator,

    // factory
    pub fn init(gpa: std.mem.Allocator) LibOstree {
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
            .allocator = gpa,
        };
    }

    pub fn deployHead(self: *LibOstree) !bool {
        // for environment variable handle
        var _envMap = try std.process.getEnvMap(self.allocator);
        defer _envMap.deinit();

        // check the machine arch
        var uts: os.utsname = undefined;
        const __ret = os.uname(&uts);
        if (__ret != 0) {
            std.log.err("error trying to get machine arch", .{});
            return false;
        }

        // deploy the head of the default branch
        if (self.deployment) |deployment| {
            var _error: ?*ostree.GError = null;
            var _ret: ostree.gboolean = ostree.FALSE;
            const _repo = ostree.ostree_repo_new_default();
            const _deploymentGKeyFile = ostree.ostree_deployment_get_origin(deployment);
            _ret = ostree.ostree_repo_open(_repo, null, &_error);

            if (_error) | err | {
                std.log.err("{s}", .{ err.message });
                return false;
            }

            if (_repo) |repo| {
                const _osName = ostree.ostree_deployment_get_osname(deployment);
                const _branch = _envMap.get("MARS_OSTREE_REPO_BRANCH");

                if (_branch) |branch| {
                    // the []const u8 is not null terminated
                    // so we need to make it null terminated
                    const _originBuffer = try self.allocator.alloc(u8, branch.len + 1);
                    defer self.allocator.free(_originBuffer);
                    std.mem.copyBackwards(u8, _originBuffer, branch);
                    _originBuffer[branch.len] = 0;
                    var _head: [*c]u8 = null;

                    // now we can use it as a null terminated string C pointer
                    const _origin: [*c]const u8 = @ptrCast(_originBuffer);

                    std.log.debug("osname: {s}", .{ std.mem.span(_osName) });
                    std.log.debug("branch: {s}", .{ std.mem.span(_origin) });

                    // get the GKeyFile
                    // 1. resolve commit from branch
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

                    std.log.debug("head: {s}", .{ _head });

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
                        _deploymentGKeyFile,
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

                    // also set the upgrade_available flag
                    const _args = [_][]const u8 {
                        "fw_setenv",
                        "upgrade_available",
                        "1"
                    };
                    _ = try std.process.Child.run(
                        .{
                            .allocator = std.heap.page_allocator,
                            .argv = &_args
                        }
                    );

                    return true;
                }

                std.log.err("branch not found", .{});
                return false;
            }

            std.log.err("repo not found", .{});
            return false;
        }

        std.log.err("deployment not found", .{});
        return false;
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

        std.log.err("sysroot/deployment not found", .{});
        return false;
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

        std.log.err("deployment not found", .{});
        return false;
    }

    pub fn getBranch(self: *LibOstree) ![]u8 {
        const _branch = try std.process.getEnvVarOwned(
            self.allocator, "MARS_OSTREE_REPO_BRANCH"
        );

        return _branch;
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


    fn _pathExists(path: []const u8) !bool {
        const fs = std.fs;
        const cwd = fs.cwd();

        cwd.access(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };

        return true;
    }

    fn _getUpperdir() ![]const u8 {
        const _file = mntent.setmntent("/proc/mounts", "r");

        if (_file) |file| {
            var _entry = mntent.getmntent(file);

            while (_entry) |entry| {
                const _typeS = consts.getStrinAsSlice(entry.*.mnt_type);

                if (std.mem.eql(u8, _typeS, "overlay")) {
                    const _optSlice = consts.getStrinAsSlice(entry.*.mnt_opts);
                    const _upperdir = _getMntOpt(_optSlice, "upperdir");

                    if (_upperdir) |upperdir| {
                        const _upperdirSlash = try std.fmt.allocPrint(
                            std.heap.page_allocator,
                            "{s}/",
                            .{ upperdir }
                        );

                        return _upperdirSlash;
                    }
                }

                _entry = mntent.getmntent(file);
            }

            @panic("Failed to get dev folder, are we in dev mode?");
        }

        @panic("Failed to open /proc/mounts, are we in dev mode?");
    }

    fn _prepareChangesPath() !std.ArrayList([]u8) {
        const _upperdirSlash = try _getUpperdir();

        // if the /tmp/mars already exists simple remove it
        if (try _pathExists("/tmp/mars")) {
            try std.fs.cwd().deleteTree("/tmp/mars");
        }

        try std.fs.makeDirAbsolute("/tmp/mars");
        try std.fs.makeDirAbsolute("/tmp/mars/usr");

        // Copy files from upperdir, but collect whiteout files to handle deletions
        var deletions = std.ArrayList([]u8).init(std.heap.page_allocator);
        try _copyWithWhiteoutProcessing(_upperdirSlash, "/tmp/mars/usr", &deletions, _upperdirSlash);

        // Also copy /etc/ as before
        const _argsEtc = [_][]const u8 {
                    "rsync",
                    "-a",
                    "--delete",
                    "/etc/",
                    "/tmp/mars/usr/etc"
                };

        _ = try std.process.Child.run(
            .{
                .allocator = std.heap.page_allocator,
                .argv = &_argsEtc
            }
        );

        return deletions;
    }

    fn _copyWithWhiteoutProcessing(src_path: []const u8, dest_path: []const u8, deletions: *std.ArrayList([]u8), upperdir_root: []const u8) !void {
        const allocator = std.heap.page_allocator;

        // First ensure destination directory exists
        std.fs.makeDirAbsolute(dest_path) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Open source directory
        var src_dir = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer src_dir.close();

        var iterator = src_dir.iterate();

        while (try iterator.next()) |entry| {
            const src_item = try std.fs.path.join(allocator, &[_][]const u8{ src_path, entry.name });
            const dest_item = try std.fs.path.join(allocator, &[_][]const u8{ dest_path, entry.name });

            // Free immediately after use instead of defer
            defer {
                allocator.free(src_item);
                allocator.free(dest_item);
            }

            if (entry.kind == .directory) {
                // Recursively copy subdirectories
                try _copyWithWhiteoutProcessing(src_item, dest_item, deletions, upperdir_root);
            } else {
                // Check if it's a whiteout file (char device with 0 size)
                const file_stat = std.fs.cwd().statFile(src_item) catch continue;

                if (file_stat.kind == .character_device and file_stat.size == 0) {
                    // This is a whiteout file - record the deletion path
                    std.log.debug("Found whiteout file for deletion: {s}", .{entry.name});

                    // Calculate the relative path from upperdir root to this whiteout file
                    // src_item is the full path to the whiteout file
                    // upperdir_root is the upperdir root path
                    // We need to get the relative path and then prepend "/usr"

                    // Remove trailing slash from upperdir_root for comparison
                    const upperdir_clean = if (std.mem.endsWith(u8, upperdir_root, "/"))
                        upperdir_root[0..upperdir_root.len-1]
                    else
                        upperdir_root;

                    if (std.mem.startsWith(u8, src_item, upperdir_clean)) {
                        // Get the relative path from upperdir root
                        const relative_from_upperdir = src_item[upperdir_clean.len..];
                        // Remove leading slash if present
                        const clean_relative = if (std.mem.startsWith(u8, relative_from_upperdir, "/"))
                            relative_from_upperdir[1..]
                        else
                            relative_from_upperdir;

                        // Build the ostree deletion path: /usr + relative path
                        const deletion_path = try std.fmt.allocPrint(allocator, "/usr/{s}", .{clean_relative});

                        std.log.debug("Adding to deletions array: '{s}' (ptr: {*}, len: {})", .{ deletion_path, deletion_path.ptr, deletion_path.len });
                        try deletions.append(deletion_path);
                        std.log.debug("Deletions array now has {} items", .{deletions.items.len});
                    } else {
                        std.log.warn("Whiteout file {s} not under upperdir {s}", .{src_item, upperdir_clean});
                    }
                    continue;
                }

                // Copy regular files
                std.fs.cwd().copyFile(src_item, std.fs.cwd(), dest_item, .{}) catch |err| {
                    std.log.warn("Failed to copy {s}: {}", .{ src_item, err });
                };
            }
        }
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

    fn _applyDeletions(mtree: *ostree.OstreeMutableTree, deletions: *std.ArrayList([]u8)) !void {
        for (deletions.items) |path| {
            std.log.debug("Applying deletion: {s}", .{path});

            // Split the path into components (skip leading slash)
            const path_without_leading_slash = if (std.mem.startsWith(u8, path, "/")) path[1..] else path;

            var path_components = std.ArrayList([]const u8).init(std.heap.page_allocator);
            defer path_components.deinit();

            var iter = std.mem.split(u8, path_without_leading_slash, "/");
            while (iter.next()) |component| {
                try path_components.append(component);
            }

            if (path_components.items.len == 0) {
                std.log.debug("Empty path, skipping: {s}", .{path});
                continue;
            }

            // Navigate through all directories except the last component (which is the file/dir to remove)
            var current_tree = mtree;
            var _error: ?*ostree.GError = null;

            // Navigate through all parent directories
            for (path_components.items[0..path_components.items.len-1]) |dir_name| {
                std.log.debug("Navigating to directory: {s}", .{dir_name});

                var next_tree: ?*ostree.OstreeMutableTree = null;
                const dir_name_z = try std.heap.page_allocator.dupeZ(u8, dir_name);
                defer std.heap.page_allocator.free(dir_name_z);

                _error = null;
                _ = ostree.ostree_mutable_tree_ensure_dir(current_tree, dir_name_z.ptr, &next_tree, &_error);

                if (_error) |err| {
                    std.log.debug("Failed to access directory {s}: {s}", .{ dir_name, err.message });
                    break;
                }

                if (next_tree) |nt| {
                    current_tree = nt;
                } else {
                    std.log.debug("Directory {s} not found", .{dir_name});
                    break;
                }
            }

            // If we successfully navigated to the parent directory, remove the file/directory
            if (_error == null) {
                const target_name = path_components.items[path_components.items.len - 1];
                std.log.debug("Removing '{s}' from current directory", .{target_name});

                const target_name_z = try std.heap.page_allocator.dupeZ(u8, target_name);
                defer std.heap.page_allocator.free(target_name_z);

                _error = null;
                const remove_result = ostree.ostree_mutable_tree_remove(current_tree, target_name_z.ptr, 1, &_error);

                if (_error) |err| {
                    std.log.debug("Failed to remove {s}: {s}", .{ target_name, err.message });
                } else if (remove_result != ostree.FALSE) {
                    std.log.debug("Successfully removed {s}", .{target_name});
                } else {
                    std.log.debug("ostree_mutable_tree_remove returned FALSE for {s}", .{target_name});
                }
            }
        }
    }

    fn _abortTransaction(repo: *ostree.OstreeRepo, _err: ?*ostree.struct__GError) !void {
        if (_err) |err| {
            std.log.err("{s}", .{ err.message });
        }

        _ = ostree.ostree_repo_abort_transaction(repo, null, null);
        try _changesPathCleanup();
    }

    pub fn commit(self: *LibOstree) !bool {
        var deletions = try _prepareChangesPath();
        defer {
            for (deletions.items) |path| {
                std.heap.page_allocator.free(path);
            }
            deletions.deinit();
        }

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
                const _branch = try std.process.getEnvVarOwned(
                    self.allocator, "MARS_OSTREE_REPO_BRANCH"
                );
                defer self.allocator.free(_branch);
                std.log.debug("repo branch: {s}", .{ _branch });

                const _base = ostree.ostree_deployment_get_csum(deployment);
                var _root: ?*ostree.OstreeRepoFile = null;
                var _commitChecksum: [*c]const u8 = null;
                // the []const u8 is not null terminated
                // so we need to make it null terminated
                const _originBuffer = try self.allocator.alloc(u8, _branch.len + 1);
                defer self.allocator.free(_originBuffer);
                std.mem.copyBackwards(u8, _originBuffer, _branch);
                _originBuffer[_branch.len] = 0;

                // now we can use it as a null terminated string C pointer
                const _origin: [*c]const u8 = @ptrCast(_originBuffer);

                // this is a sanity check
                std.log.debug("branch: {s}", .{ std.mem.span(_origin) });
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

                // Apply deletions from whiteout files AFTER writing the directory tree
                if (_mtree) |mtree| {
                    std.debug.print("applying deletions...\n", .{});
                    try _applyDeletions(mtree, &deletions);
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

            std.log.err("repo not found", .{});
            return false;
        }

        std.log.err("deployment not found", .{});
        return false;
    }

    fn _collectWhiteoutFiles(src_path: []const u8, deletions: *std.ArrayList([]u8), upperdir_root: []const u8) !void {
        const allocator = std.heap.page_allocator;

        // Open source directory
        var src_dir = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer src_dir.close();

        var iterator = src_dir.iterate();

        while (try iterator.next()) |entry| {
            const src_item = try std.fs.path.join(allocator, &[_][]const u8{ src_path, entry.name });
            defer allocator.free(src_item);

            if (entry.kind == .directory) {
                // Recursively search subdirectories
                try _collectWhiteoutFiles(src_item, deletions, upperdir_root);
            } else {
                // Check if it's a whiteout file (char device with 0 size)
                const file_stat = std.fs.cwd().statFile(src_item) catch continue;

                if (file_stat.kind == .character_device and file_stat.size == 0) {
                    // This is a whiteout file - record the deletion path
                    std.log.debug("Found whiteout file for deletion: {s}", .{entry.name});

                    // Calculate the relative path from upperdir root to this whiteout file
                    const upperdir_clean = if (std.mem.endsWith(u8, upperdir_root, "/"))
                        upperdir_root[0..upperdir_root.len-1]
                    else
                        upperdir_root;

                    if (std.mem.startsWith(u8, src_item, upperdir_clean)) {
                        // Get the relative path from upperdir root
                        const relative_from_upperdir = src_item[upperdir_clean.len..];
                        // Remove leading slash if present
                        const clean_relative = if (std.mem.startsWith(u8, relative_from_upperdir, "/"))
                            relative_from_upperdir[1..]
                        else
                            relative_from_upperdir;

                        // For display purposes, we want to show the path as it would appear in the filesystem
                        const deletion_path = try allocator.dupe(u8, clean_relative);
                        try deletions.append(deletion_path);
                    }
                }
            }
        }
    }

    pub fn _getDiffers(
        self: *LibOstree,
        repo: *ostree.OstreeRepo,
        ref: ?[*c]const u8,
        dev: bool
    ) !void {
        const stdout = std.io.getStdOut().writer();
        var _error: ?*ostree.GError = null;
        var _ret: ostree.gboolean = ostree.FALSE;
        var _ref: [*c]const u8 = null;
        var _dpref: []const u8 = "";

        const _AddedStyle = style.Style {
            .foreground = .Green,
        };

        const _RemovedStyle = style.Style {
            .foreground = .Red,
        };

        const _ModifiedStyle = style.Style {
            .foreground = .Yellow,
        };

        if (ref) |r| {
            _ref = r;
        } else {
            _ref = try self.getDeployHash();
        }

        // resolve the _ref
        var _head: [*c]u8 = null;
        _ret = ostree.ostree_repo_resolve_rev(
            repo,
            _ref,
            ostree.FALSE,
            &_head,
            &_error
        );
        if (_ret == ostree.FALSE) {
            if (_error) |err| {
                std.log.err("{s}", .{ err.message });
            }
            return;
        }

        // load the commit
        var _commit: ?*ostree.GVariant = null;
        _ret = ostree.ostree_repo_load_variant(
            repo,
            ostree.OSTREE_OBJECT_TYPE_COMMIT,
            _head,
            &_commit,
            &_error
        );
        if (_ret == ostree.FALSE) {
            if (_error) |err| {
                std.log.err("{s}", .{ err.message });
            }
            return;
        }

        const _parent = ostree.ostree_commit_get_parent(_commit);
        if (_parent == null and !dev) {
            try stdout.print("Parent: \tInitial Commit\n", .{});
            return;
        } else if (!dev) {
            try stdout.print("Parent: \t{s}\n", .{ _parent });
        } else {
            try stdout.print("Parent: \tDevelopment Mode\n", .{});
        }

        try stdout.print("\nGetting diff please wait ...\n", .{});

        // get differs
        var src_file: ?*ostree.GFile = null;
        var target_file: ?*ostree.GFile = null;

        // if in dev mode get the system changes
        if (dev) {
            _dpref = "/usr/";
            // for dev changes instead of a commit we have the deployment folder
            _ret = ostree.ostree_repo_read_commit(repo, _head, &src_file, null, null, &_error);
            if (_ret == ostree.FALSE) {
                if (_error) |err| {
                    std.log.err("Failed to read parent commit: {s}", .{err.message});
                }
                return;
            }

            // for dev we need to check only /usr
            src_file = ostree.g_file_get_child(src_file, "usr");

            // in the dev mode we get from the deployment folder
            // there was mounted the overlayfs
            // const _deployHash = try self.getDeployHash();
            const _deployedPath = try std.fmt.allocPrint(
                std.heap.page_allocator,
                "/usr",
                .{  }
            );
            target_file = ostree.g_file_new_for_path(_deployedPath.ptr);
        } else {
            // get the parent diff
            if (_parent != null) {
                _ret = ostree.ostree_repo_read_commit(repo, _parent, &src_file, null, null, &_error);
                if (_ret == ostree.FALSE) {
                    if (_error) |err| {
                        std.log.err("Failed to read parent commit: {s}", .{err.message});
                    }
                    return;
                }

                _ret = ostree.ostree_repo_read_commit(repo, _head, &target_file, null, null, &_error);
                if (_ret == ostree.FALSE) {
                    if (_error) |err| {
                        std.log.err("Failed to read current commit: {s}", .{err.message});
                    }
                    return;
                }
            }
        }

        const modified: ?*ostree.GPtrArray = ostree.g_ptr_array_new_with_free_func(@ptrCast(@constCast(&ostree.ostree_diff_item_unref)));
        const removed: ?*ostree.GPtrArray = ostree.g_ptr_array_new_with_free_func(@ptrCast(@constCast(&ostree.g_object_unref)));
        const added: ?*ostree.GPtrArray = ostree.g_ptr_array_new_with_free_func(@ptrCast(@constCast(&ostree.g_object_unref)));

        var diff_opts = ostree.OstreeDiffDirsOptions{
            .owner_uid = -1,
            .owner_gid = -1,
        };

        _ret = ostree.ostree_diff_dirs_with_options(ostree.OSTREE_DIFF_FLAGS_NONE, src_file, target_file, modified, removed, added, &diff_opts, null, &_error);
        if (_ret == ostree.FALSE) {
            if (_error) |err| {
                std.log.err("Failed to diff commits: {s}", .{err.message});
            }
            return;
        }

        var whiteout_deletions = std.ArrayList([]u8).init(self.allocator);
        defer {
            for (whiteout_deletions.items) |path| {
                self.allocator.free(path);
            }
            whiteout_deletions.deinit();
        }

        // Custom printing so we can apply styles and custom prefixes
        // Print modified as "!= path", removed as "- path", added as "+ path"
        if (added) |a| {
            var i: usize = 0;

            try stdout.print("\nAdded:\n\n", .{});

            while (i < a.len) : (i += 1) {
                const raw = ostree.g_ptr_array_index(a, i);
                if (raw == null) continue;
                const added_file: *ostree.GFile = @alignCast(@ptrCast(raw));
                var path: []const u8 = "(unknown)";
                const p = ostree.g_file_get_relative_path(target_file, added_file);
                if (p) |pp| {
                    path = std.mem.span(pp);
                } else {
                    const p2 = ostree.g_file_get_relative_path(src_file, added_file);
                    if (p2) |pp2| path = std.mem.span(pp2);
                }

                // In dev mode, skip whiteout files from the added list (they'll be shown as removed)
                if (dev) {
                    // Check if this is a whiteout file by examining the actual file
                    const added_file_path = ostree.g_file_get_path(added_file);
                    if (added_file_path) |file_path| {
                        const file_path_str = std.mem.span(file_path);
                        const file_stat = std.fs.cwd().statFile(file_path_str) catch null;
                        if (file_stat) |stat| {
                            if (stat.kind == .character_device and stat.size == 0) {
                                // This is a whiteout file, skip it
                                continue;
                            }
                        }
                    }
                }

                try format.updateStyle(stdout, _AddedStyle, null);
                try stdout.print("\t+     ", .{});
                try stdout.print("{s}{s}\n", .{ _dpref, path });
                try format.resetStyle(stdout);
            }
        }

        if (removed) |r| {
            var i: usize = 0;

            try stdout.print("\nRemoved:\n\n", .{});

            while (i < r.len) : (i += 1) {
                const raw = ostree.g_ptr_array_index(r, i);
                if (raw == null) continue;
                const removed_file: *ostree.GFile = @alignCast(@ptrCast(raw));
                var path: []const u8 = "(unknown)";
                const p = ostree.g_file_get_relative_path(target_file, removed_file);
                if (p) |pp| {
                    path = std.mem.span(pp);
                } else {
                    const p2 = ostree.g_file_get_relative_path(src_file, removed_file);
                    if (p2) |pp2| path = std.mem.span(pp2);
                }

                try format.updateStyle(stdout, _RemovedStyle, null);
                try stdout.print("\t-     ", .{});
                try stdout.print("{s}{s}\n", .{ _dpref, path });
                try format.resetStyle(stdout);
            }

            // In dev mode, also show whiteout files as removed
            if (dev) {
                for (whiteout_deletions.items) |whiteout_path| {
                    try format.updateStyle(stdout, _RemovedStyle, null);
                    try stdout.print("\t-     ", .{});
                    try stdout.print("{s}{s}\n", .{ _dpref, whiteout_path });
                    try format.resetStyle(stdout);
                }
            }
        }

        if (modified) |m| {
            var i: usize = 0;

            try stdout.print("\nModified:\n\n", .{});

            while (i < m.len) : (i += 1) {
                const raw = ostree.g_ptr_array_index(m, i);
                if (raw == null) continue;
                const diff_item: *ostree.OstreeDiffItem = @alignCast(@ptrCast(raw));
                // diff_item->src may be a GFile pointer
                const src_file_ptr = diff_item.*.src;
                var path: []const u8 = "(unknown)";
                if (src_file_ptr) |sf| {
                    const p = ostree.g_file_get_relative_path(target_file, sf);
                    if (p) |pp| {
                        path = std.mem.span(pp);
                    } else {
                        const p2 = ostree.g_file_get_relative_path(src_file, sf);
                        if (p2) |pp2| path = std.mem.span(pp2);
                    }
                }

                try format.updateStyle(stdout, _ModifiedStyle, null);
                try stdout.print("\t!=    ", .{});
                try stdout.print("{s}{s}\n", .{ _dpref, path });
                try format.resetStyle(stdout);
            }
        }
    }

    pub fn getStatus(self: *LibOstree) !void {
        const stdout = std.io.getStdOut().writer();

        // get the deployment hash
        if (self.deployment) |deployment| {
            var _error: ?*ostree.GError = null;
            var _ret: ostree.gboolean = ostree.FALSE;
            var _devMode: bool = false;
            const _repo = ostree.ostree_repo_new_default();
            _ret = ostree.ostree_repo_open(_repo, null, &_error);

            const _hash = ostree.ostree_deployment_get_csum(deployment);
            const _os = ostree.ostree_deployment_get_osname(deployment);
            const _branch = try self.getBranch();
            const _unlocked = ostree.ostree_deployment_get_unlocked(deployment);

            try stdout.print("\nDev:    \t", .{});

            if (_unlocked == ostree.OSTREE_DEPLOYMENT_UNLOCKED_DEVELOPMENT) {
                try stdout.print("true\n", .{});
                _devMode = true;
            } else {
                try stdout.print("false\n", .{});
            }

            try stdout.print("Commit: \t{s}\n", .{ std.mem.span(_hash) });
            try stdout.print("OS:     \t{s}\n", .{ std.mem.span(_os) });
            try stdout.print("Branch: \t{s}\n", .{ _branch });
            defer self.allocator.free(_branch);
            try stdout.print("Ostree: \t{s}\n", .{ self.version });
            try stdout.print("Mars:   \t{s}\n", .{ consts.MARS_VERSION_S });

            if (_repo) |repo| {
                try self._getDiffers(repo, null, _devMode);
            }
        } else {
            std.log.err("deployment not found", .{});
        }
    }
};
