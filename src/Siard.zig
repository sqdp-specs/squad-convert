const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;

pub const Metadata = struct {
    dbname: ?[]const u8 = null,
    dataOwner: ?[]const u8 = null,
    dataOriginTimespan: ?[]const u8 = null,
    lobFolder: ?[]const u8 = null,
    producerApplication: ?[]const u8 = null,
    archivalDate: ?[]const u8 = null,
    messageDigest: ?[]const u8 = null,
    clientMachine: ?[]const u8 = null,
    databaseProduct: ?[]const u8 = null,
    connection: ?[]const u8 = null,
    databaseUser: ?[]const u8 = null,

    fn init(self: *Metadata, alloc: Allocator, root: xml.xmlNodePtr) !xml.xmlNodePtr {
        var curr = xml.xmlFirstElementChild(root);
        while (curr != null and !std.mem.eql(u8, std.mem.span(curr.*.name), "schemas")) : (curr = xml.xmlNextElementSibling(curr)) {
            const value = try alloc.dupe(u8, std.mem.trim(u8, std.mem.span(xml.xmlNodeGetContent(curr)), " \t\r\n"));
            inline for (comptime std.meta.fieldNames(@TypeOf(self.*))) |nm| {
                if (std.mem.eql(u8, nm, std.mem.span(curr.*.name))) {
                    @field(self, nm) = value;
                    break;
                }
            } else alloc.free(value);
        }
        return curr;
    }

    fn deinit(self: *Metadata, alloc: Allocator) void {
        inline for (comptime std.meta.fieldNames(@TypeOf(self.*))) |nm| {
            if (@field(self, nm)) |v| alloc.free(v);
        }
    }
};

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
    const root = xml.xmlDocGetRootElement(d);
    var m = Metadata{};
    const schema_ptr = try m.init(std.testing.allocator, root);
    try std.testing.expect(schema_ptr != null);
    try std.testing.expect(m.databaseProduct != null);
    try std.testing.expectEqualStrings(m.databaseProduct.?, "Microsoft SQL Server 12.00.2000");
    m.deinit(std.testing.allocator);
}

const Schema = struct {
    name: []const u8,
    folder: []const u8,
};

const Table = struct {};
