//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const zqlite = @import("zqlite");
const miniz = @import("miniz");
const xml = @import("xml");
const Siard = @import("Siard.zig");
const Allocator = std.mem.Allocator;

const SquadError = error{
    BadZip,
    NotFound,
};

fn zipIndex(archive: *miniz.mz_zip_archive, fname: []const u8) !usize {
    var fs: miniz.mz_zip_archive_file_stat = std.mem.zeroes(miniz.mz_zip_archive_file_stat);
    for (0..miniz.mz_zip_reader_get_num_files(archive)) |idx| {
        fs = std.mem.zeroes(miniz.mz_zip_archive_file_stat);
        _ = miniz.mz_zip_reader_file_stat(archive, @intCast(idx), &fs);
        const a: [*:0]const u8 = @ptrCast(&fs.m_filename);
        if (std.mem.endsWith(u8, std.mem.span(a), fname)) {
            return idx;
        }
    }
    return SquadError.NotFound;
}

pub fn convert(alloc: Allocator, path: []const u8) !void {
    var archive: miniz.mz_zip_archive = std.mem.zeroes(miniz.mz_zip_archive);
    const res = miniz.mz_zip_reader_init_file(&archive, @ptrCast(path), 0);
    if (res != 1) {
        return SquadError.BadZip;
    }
    defer _ = miniz.mz_zip_reader_end(&archive); // free resources
    const midx = try zipIndex(&archive, "metadata.xml");
    var uncomp_size: usize = 0;
    const p = miniz.mz_zip_reader_extract_to_heap(&archive, @intCast(midx), @ptrCast(&uncomp_size), 0) orelse return SquadError.BadZip;
    defer miniz.mz_free(p);
    const doc = xml.xmlReadMemory(@ptrCast(p), @intCast(uncomp_size), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    defer xml.xmlFreeDoc(doc);
    const s = try Siard.new(alloc, doc);
    defer s.deinit(alloc);
    const str = try s.metadata.sqlInsert(alloc);
    defer alloc.free(str);
    std.debug.print("{s}", .{str});
    return;
}

const example = "test/northwind.siard";

test "tests" {
    _ = @import("Siard.zig");
    _ = @import("types.zig");
}

test "unzip" {
    var archive: miniz.mz_zip_archive = std.mem.zeroes(miniz.mz_zip_archive);
    const res = miniz.mz_zip_reader_init_file(&archive, example, 0);
    try std.testing.expectEqual(res, 1);
    defer _ = miniz.mz_zip_reader_end(&archive);
    const idx = try zipIndex(&archive, "metadata.xml");
    try std.testing.expectEqual(idx, 1);
}

test "sqlite" {
    const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
    var conn = try zqlite.open("test.squad", flags);
    try conn.exec(
        \\ CREATE TABLE if not exists artist(
        \\   artistid INTEGER,
        \\   artistname TEXT
        \\ )
    , .{});
    try conn.exec(
        \\ CREATE TABLE if not exists track(
        \\   trackid     INTEGER,
        \\   trackname   TEXT,
        \\   trackartist INTEGER,
        \\   FOREIGN KEY(trackartist) REFERENCES artist(artistid)
        \\ )
    , .{});
    try conn.exec("create table if not exists test (name text)", .{});
    try conn.exec("insert into test (name) values (?1), (?2)", .{ "Leto", "Ghanima" });
    if (try conn.row("select * from test order by name limit 1", .{})) |row| {
        defer row.deinit();
        try std.testing.expectEqualStrings("Ghanima", row.text(0));
    }
    conn.close();
    try std.fs.cwd().deleteFile("test.squad");
}

test "convert" {
    try convert(std.testing.allocator, example);
}
