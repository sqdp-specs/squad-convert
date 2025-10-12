//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zqlite = @import("zqlite");
const miniz = @import("miniz");

pub fn convert() !void {}

test {
    std.testing.refAllDecls(@This());
}

const example = "test/northwind.siard";

test "unzip" {
    var s: miniz.mz_zip_archive = std.mem.zeroes(miniz.mz_zip_archive);
    var fs: miniz.mz_zip_archive_file_stat = std.mem.zeroes(miniz.mz_zip_archive_file_stat);
    const res = miniz.mz_zip_reader_init_file(&s, example, 0);
    try std.testing.expectEqual(res, 1);
    for (0..miniz.mz_zip_reader_get_num_files(&s)) |idx| {
        fs = std.mem.zeroes(miniz.mz_zip_archive_file_stat);
        _ = miniz.mz_zip_reader_file_stat(&s, @intCast(idx), &fs);
        std.debug.print("{s}\n", .{fs.m_filename});
    }
    try std.testing.expectEqual(miniz.mz_zip_reader_get_num_files(&s), 48);
}

test "sqlite" {
    const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
    var conn = try zqlite.open("test.sqlite", flags);
    try conn.exec("create table if not exists test (name text)", .{});
    try conn.exec("insert into test (name) values (?1), (?2)", .{ "Leto", "Ghanima" });
    if (try conn.row("select * from test order by name limit 1", .{})) |row| {
        defer row.deinit();
        try std.testing.expectEqualStrings("Ghanima", row.text(0));
    }
    conn.close();
    try std.fs.cwd().deleteFile("test.sqlite");
}
