const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const mysql = b.dependency("mysql_server", .{});
    const generated = b.addWriteFiles();

    // this or use cmake...I think this is simpler...
    _ = generated.add("mysql_version.h",
        \\#pragma once
        \\#define PROTOCOL_VERSION 10
        \\#define MYSQL_SERVER_VERSION "8.0.42"
        \\#define MYSQL_BASE_VERSION "8.0"
        \\#define MYSQL_VERSION_ID 80042
        \\#define MYSQL_VERSION_MATURITY "LTS"
        \\#define MYSQL_VERSION_MATURITY_IS_LTS 1
        \\#define MYSQL_PORT 3306
        \\#define MYSQL_ADMIN_PORT 33062
        \\#define MYSQL_PORT_DEFAULT 0
        \\#define MYSQL_UNIX_ADDR "/tmp/mysql.sock"
        \\#define MYSQL_CONFIG_NAME "my"
        \\#define MYSQL_PERSIST_CONFIG_NAME "mysqld-auto"
        \\#define MYSQL_COMPILATION_COMMENT "Source distribution"
        \\#define MYSQL_COMPILATION_COMMENT_SERVER "Source distribution"
        \\#define LIBMYSQL_VERSION "8.0.42"
        \\#define LIBMYSQL_VERSION_ID 80042
        \\#define LICENSE GPL
        \\
    );

    // build linux
    const linux_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .glibc_version = .{
            .major = 2,
            .minor = 17,
            .patch = 0,
        },
    });

    const linux_module = b.createModule(.{
        .root_source_file = b.path("src/sys_eval.zig"),
        .target = linux_target,
        .optimize = optimize,
        .link_libc = true,
    });
    linux_module.addIncludePath(generated.getDirectory());
    linux_module.addIncludePath(mysql.path("include"));

    const linux_library = b.addLibrary(.{
        .name = "sys_eval",
        .linkage = .dynamic,
        .root_module = linux_module,
    });
    b.installArtifact(linux_library);

    // windows shit...
    const windows_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    });
    const windows_module = b.createModule(.{
        .root_source_file = b.path("src/sys_eval.zig"),
        .target = windows_target,
        .optimize = optimize,
        .link_libc = true,
    });
    windows_module.addIncludePath(generated.getDirectory());
    windows_module.addIncludePath(mysql.path("include"));

    const windows_library = b.addLibrary(.{
        .name = "sys_eval",
        .linkage = .dynamic,
        .root_module = windows_module,
    });
    const windows_install = b.addInstallArtifact(windows_library, .{
        .dest_dir = .{ .override = .lib },
    });
    b.getInstallStep().dependOn(&windows_install.step);
}
