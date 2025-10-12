const std = @import("std");

const LIBXML2_VERSION = "2.13.5";
const LIBXML2_VERSION_NUMBER = 21305;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libxml2_dep = b.dependency("libxml2", .{});
    const miniz_dep = b.dependency("miniz", .{});

    const xmlversion_h = b.addConfigHeader(.{
        .style = .{ .cmake = libxml2_dep.path("include/libxml/xmlversion.h.in") },
        .include_path = "libxml/xmlversion.h",
    }, .{
        .VERSION = LIBXML2_VERSION,
        .LIBXML_VERSION_NUMBER = LIBXML2_VERSION_NUMBER,
        .LIBXML_VERSION_EXTRA = "",
        .WITH_THREADS = false,
        .WITH_THREAD_ALLOC = false,
        .WITH_TREE = true,
        .WITH_OUTPUT = true,
        .WITH_PUSH = false,
        .WITH_READER = false,
        .WITH_PATTERN = true,
        .WITH_WRITER = false,
        .WITH_SAX1 = false,
        .WITH_FTP = false,
        .WITH_HTTP = false,
        .WITH_VALID = false,
        .WITH_HTML = true,
        .WITH_LEGACY = false,
        .WITH_C14N = false,
        .WITH_CATALOG = false,
        .WITH_XPATH = true,
        .WITH_XPTR = false,
        .WITH_XPTR_LOCS = false,
        .WITH_XINCLUDE = false,
        .WITH_ICONV = false,
        .WITH_ICU = false,
        .WITH_ISO8859X = false,
        .WITH_DEBUG = false,
        .WITH_REGEXPS = true,
        .WITH_SCHEMAS = true,
        .WITH_SCHEMATRON = false,
        .WITH_MODULES = false,
        .MODULE_EXTENSION = target.result.dynamicLibSuffix(),
        .WITH_ZLIB = false,
        .WITH_LZMA = false,
    });

    const libxml2_config_h = b.addConfigHeader(.{
        .style = .{ .cmake = libxml2_dep.path("config.h.cmake.in") },
    }, .{
        .ATTRIBUTE_DESTRUCTOR = "__attribute__((destructor))",
        .HAVE_ARPA_INET_H = true,
        .HAVE_ATTRIBUTE_DESTRUCTOR = true,
        .HAVE_DLFCN_H = true,
        .HAVE_DLOPEN = true,
        .HAVE_DL_H = false,
        .HAVE_FCNTL_H = true,
        .HAVE_FTIME = true,
        .HAVE_GETENTROPY = false,
        .HAVE_GETTIMEOFDAY = true,
        .HAVE_LIBHISTORY = false,
        .HAVE_LIBREADLINE = false,
        .HAVE_MMAP = true,
        .HAVE_MUNMAP = true,
        .HAVE_NETDB_H = true,
        .HAVE_NETINET_IN_H = true,
        .HAVE_POLL_H = true,
        .HAVE_PTHREAD_H = true,
        .HAVE_SHLLOAD = false,
        .HAVE_STAT = true,
        .HAVE_STDINT_H = true,
        .HAVE_SYS_MMAN_H = true,
        .HAVE_SYS_RANDOM_H = true,
        .HAVE_SYS_SELECT_H = true,
        .HAVE_SYS_SOCKET_H = true,
        .HAVE_SYS_STAT_H = true,
        .HAVE_SYS_TIMEB_H = true,
        .HAVE_SYS_TIME_H = true,
        .HAVE_UNISTD_H = true,
        .HAVE_VA_COPY = true,
        .HAVE_ZLIB_H = false,
        .HAVE___VA_COPY = true,
        .SUPPORT_IP6 = false,
        .VERSION = LIBXML2_VERSION,
        .XML_SOCKLEN_T = "socklen_t",
        .XML_THREAD_LOCAL = null,
    });

    var libxml2_sources: std.ArrayList([]const u8) = .empty;
    libxml2_sources.appendSlice(b.allocator, &.{
        "buf.c",
        "chvalid.c",
        "dict.c",
        "entities.c",
        "encoding.c",
        "error.c",
        "globals.c",
        "hash.c",
        "list.c",
        "parser.c",
        "parserInternals.c",
        "SAX2.c",
        "threads.c",
        "tree.c",
        "uri.c",
        "valid.c",
        "xmlIO.c",
        "xmlmemory.c",
        "xmlstring.c",
        "pattern.c",
        "xmlregexp.c",
        "xmlunicode.c",
        "relaxng.c",
        "xmlschemas.c",
        "xmlschemastypes.c",
        "xpath.c",
        "HTMLparser.c",
        "HTMLtree.c",
        "xmlsave.c",
    }) catch @panic("OOM");
    const libxml2_cflags: []const []const u8 = &.{
        "-DLIBXML_STATIC",
        "-pedantic",
        "-Wall",
        "-Wextra",
        "-Wshadow",
        "-Wpointer-arith",
        "-Wcast-align",
        "-Wwrite-strings",
        "-Wstrict-prototypes",
        "-Wmissing-prototypes",
        "-Wno-long-long",
        "-Wno-format-extra-args",
    };
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("xml.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(libxml2_dep.path("include"));
    translate_c.addConfigHeader(xmlversion_h);

    const xml_mod = translate_c.createModule();
    xml_mod.addIncludePath(libxml2_dep.path("include"));
    xml_mod.addConfigHeader(xmlversion_h);
    xml_mod.addConfigHeader(libxml2_config_h);
    xml_mod.addCSourceFiles(.{
        .root = libxml2_dep.path("."),
        .files = libxml2_sources.items,
        .flags = libxml2_cflags,
    });

    if (target.result.os.tag == .windows) {
        xml_mod.linkSystemLibrary("bcrypt", .{});
    }

    const miniz_translate_c = b.addTranslateC(.{
        .root_source_file = miniz_dep.path("miniz.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const miniz_mod = miniz_translate_c.createModule();
    miniz_mod.addCSourceFile(.{
        .file = miniz_dep.path("miniz.c"),
    });

    const zqlite_dep = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const zqlite = zqlite_dep.module("zqlite");

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/squadc.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("xml", xml_mod);
    lib_mod.addImport("miniz", miniz_mod);
    lib_mod.addImport("zqlite", zqlite);

    const exe = b.addExecutable(.{
        .name = "squadc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "squadc", .module = lib_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
