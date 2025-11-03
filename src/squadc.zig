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

fn appendExt(alloc: Allocator, base: []const u8, ext: []const u8) ![:0]const u8 {
    var list = std.ArrayList(u8).empty;
    try list.appendSlice(alloc, base);
    try list.appendSlice(alloc, ext);
    return list.toOwnedSliceSentinel(alloc, 0);
}

pub fn convert(alloc: Allocator, path: []const u8) !void {
    // make squad file name by trimming ext from path
    const squadFile = try appendExt(alloc, std.fs.path.stem(path), ".squad");
    // open sqlite connection
    var conn = try zqlite.open(squadFile, zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode);
    alloc.free(squadFile);
    defer conn.close();
    // read the archive
    var archive: miniz.mz_zip_archive = std.mem.zeroes(miniz.mz_zip_archive);
    const res = miniz.mz_zip_reader_init_file(&archive, @ptrCast(path), 0);
    if (res != 1) {
        return SquadError.BadZip;
    }
    defer _ = miniz.mz_zip_reader_end(&archive); // free resources
    // find and read metadata.xml
    const midx = try zipIndex(&archive, "metadata.xml");
    var uncomp_size: usize = 0;
    const p = miniz.mz_zip_reader_extract_to_heap(&archive, @intCast(midx), @ptrCast(&uncomp_size), 0) orelse return SquadError.BadZip;
    defer miniz.mz_free(p);
    const doc = xml.xmlReadMemory(@ptrCast(p), @intCast(uncomp_size), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    defer xml.xmlFreeDoc(doc);
    const s = try Siard.new(alloc, doc);
    defer s.deinit(alloc);
    // execute metadata schema statements
    try conn.exec(Siard.metadataSchema, .{});
    try conn.exec(Siard.tablesSchema, .{});
    try conn.exec(Siard.columnsSchema, .{});
    // // execute metadata insert statements
    const metadataInsert = try s.metadata.sqlInsert(alloc);
    try conn.exec(metadataInsert, .{});
    alloc.free(metadataInsert);
    const tableInsert = try s.schemas[0].sqlInsertTbls(alloc);
    try conn.exec(tableInsert, .{});
    alloc.free(tableInsert);
    const columnsInsert = try s.schemas[0].sqlInsertCols(alloc);
    try conn.exec(columnsInsert, .{});
    alloc.free(columnsInsert);
    // execute table schema statements
    for (s.schemas[0].tables) |*tbl| {
        if (tbl.rows == 0) continue;
        const tableSchema = try tbl.sqlSchema(alloc);
        try conn.exec(tableSchema, .{});
        alloc.free(tableSchema);
        // table insert
        uncomp_size = 0;
        const tpath = try appendExt(alloc, tbl.folder, ".xml");
        const tidx = try zipIndex(&archive, tpath);
        alloc.free(tpath);
        const t = miniz.mz_zip_reader_extract_to_heap(&archive, @intCast(tidx), @ptrCast(&uncomp_size), 0) orelse return SquadError.BadZip;
        const tdoc = xml.xmlReadMemory(@ptrCast(t), @intCast(uncomp_size), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
        const ins = try tbl.sqlInsert(alloc, tdoc);
        conn.exec(ins, .{}) catch std.debug.print("{s}\n", .{conn.lastError()});
        xml.xmlFreeDoc(tdoc);
        miniz.mz_free(t);
        alloc.free(ins);
    }
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
    var conn = try zqlite.open("test.squad", zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode);
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
    try std.fs.cwd().deleteFile("northwind.squad");
}
