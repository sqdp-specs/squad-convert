const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;

pub const Metadata = struct {
    dbname: ?[:0]const u8 = null,
    dataOwner: ?[:0]const u8 = null,
    dataOriginTimespan: ?[:0]const u8 = null,
    lobFolder: ?[:0]const u8 = null,
    producerApplication: ?[:0]const u8 = null,
    archivalData: ?[:0]const u8 = null,
    messageDigest: ?[:0]const u8 = null,
    clientMachine: ?[:0]const u8 = null,
    databaseProduct: ?[:0]const u8 = null,
    connection: ?[:0]const u8 = null,
    databaseUser: ?[:0]const u8 = null,

    fn update(self: *Metadata, name: []const u8, value: [:0]const u8) bool {
        inline for (comptime std.meta.fieldNames(@TypeOf(self.*))) |nm| {
            if (std.mem.eql(u8, nm, name)) {
                @field(self, nm) = value;
                return true;
            }
        }
        return false;
    }

    fn free(self: *Metadata, alloc: Allocator) void {
        inline for (comptime std.meta.fieldNames(@TypeOf(self.*))) |nm| {
            if (@field(self, nm)) |v| alloc.free(v);
        }
    }
};

const Schema = struct {
    name: []const u8,
    folder: []const u8,
};

const Table = struct {};

pub fn equals(a: [*]const xml.xmlChar, b: []const u8) bool {
    for (b, 0..) |char, idx| if (a[idx] != char) return false;
    return a[b.len] == 0;
}

// length includes the sentinel
fn xmlStrLen(a: [*]const xml.xmlChar) usize {
    var idx: usize = 0;
    while (true) : (idx += 1) if (a[idx] == 0) return idx + 1;
}

pub fn xmlStrDup(ally: Allocator, a: [*]const xml.xmlChar) ![:0]const u8 {
    const len = xmlStrLen(a);
    const arr = try ally.alloc(u8, len);
    var idx: usize = 0;
    while (idx < len) : (idx += 1) {
        arr[idx] = a[idx];
    }
    return arr[0 .. len - 1 :0];
}

test "dbname" {
    var m = Metadata{};
    _ = m.update("dbname", "test");
    try std.testing.expect(m.dbname != null);
    if (m.dbname) |v| {
        try std.testing.expectEqualStrings(v, "test");
    }
}

test "metadata" {
    const example =
        \\ <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\ <?xml-stylesheet type="text/xsl" href="metadata.xsl"?><siardArchive xmlns="http://www.bar.admin.ch/xmlns/siard/1.0/metadata.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" xsi:schemaLocation="http://www.bar.admin.ch/xmlns/siard/1.0/metadata.xsd metadata.xsd">
        \\   <dbname>testnt</dbname>
        \\   <dataOwner>(...)</dataOwner>
        \\   <dataOriginTimespan>2015</dataOriginTimespan>
        \\   <lobFolder>file:///Northwind/</lobFolder>
        \\   <producerApplication>SiardEdit 1.80 Swiss Federal Archives, Berne, Switzerland, 2007-2015</producerApplication> <!-- Modified by Phillip Tømmerholt, Danish National Archives -->
        \\   <archivalDate>2015-11-26</archivalDate>
        \\   <messageDigest>MD53908342CA03FF371BDB9E92427930893</messageDigest>
        \\   <clientMachine>10.50.32.247</clientMachine>
        \\   <databaseProduct>
        \\     Microsoft SQL Server 12.00.2000
        \\   </databaseProduct>
        \\   <connection>jdbc:sqlserver://127.0.0.1:1433; authenticationScheme=nativeAuthentication; xopenStates=false; sendTimeAsDatetime=true; trustServerCertificate=false; sendStringParametersAsUnicode=true; selectMethod=cursor; responseBuffering=adaptive; packetSize=8000; multiSubnetFailover=false; loginTimeout=30; lockTimeout=-1; lastUpdateCount=true; encrypt=false; disableStatementPooling=true; databaseName=NORTHWND; applicationName=Microsoft JDBC Driver for SQL Server; applicationIntent=readwrite;\u0020</connection>
        \\   <databaseUser>ptest2</databaseUser>
        \\   <schemas/>
        \\   </siardArchive>
    ;
    const d = xml.xmlReadMemory(example.ptr, @intCast(example.len), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    var m = Metadata{};
    const root = xml.xmlDocGetRootElement(d);
    var curr = xml.xmlFirstElementChild(root);
    while (curr != null) : (curr = xml.xmlNextElementSibling(curr)) {
        const nm = try xmlStrDup(std.testing.allocator, curr.*.name);
        const content = try xmlStrDup(std.testing.allocator, xml.xmlNodeGetContent(curr));

        if (!m.update(nm, content)) {
            std.testing.allocator.free(content);
        }
        std.testing.allocator.free(nm);
    }
    if (m.archivalData) |v| {
        try std.testing.expectEqualStrings(v, "2015-11-26");
    }
    m.free(std.testing.allocator);
}
