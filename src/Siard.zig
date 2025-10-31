const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
const Typ = @import("types.zig").Typ;
const Siard = @This();

const SiardError = error{
    UnexpectedElement,
};

metadata: Metadata,
schemas: []Schema,
// users: ?[]User = null, //TODO
// roles: ?[]Role = null, //TODO

pub fn new(alloc: Allocator, doc: [*c]xml.xmlDoc) !*Siard {
    const ret = try alloc.create(Siard);
    const root = xml.xmlDocGetRootElement(doc);
    ret.metadata = Metadata{};
    const schemas = try ret.metadata.init(alloc, root);
    const schema_count: usize = xml.xmlChildElementCount(schemas);
    ret.schemas = try alloc.alloc(Schema, schema_count);
    var idx: usize = 0;
    var schema = schemas;
    while (idx < schema_count) : (idx += 1) {
        schema =
            if (idx == 0) try expect(xml.xmlFirstElementChild(schema), "schema") else try expect(xml.xmlNextElementSibling(schema), "schema");
        try ret.schemas[idx].init(alloc, schema);
    }
    return ret;
}

pub fn deinit(self: *Siard, alloc: Allocator) void {
    self.metadata.deinit(alloc);
    for (self.schemas) |*schema| {
        schema.deinit(alloc);
    }
    alloc.free(self.schemas);
    alloc.destroy(self);
}

const metadataSchema =
    \\CREATE TABLE if not exists _metadata(dbname TEXT, dataOwner TEXT, dataOriginTimespan TEXT, lobFolder TEXT, producerApplication TEXT, archivalDate TEXT, messageDigest TEXT, clientMachine TEXT, databaseProduct TEXT, connection TEXT, databaseUser TEXT)
;

const Metadata = struct {
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

    pub fn sqlSchema(self: *Metadata) []const u8 {
        _ = self;
        return metadataSchema;
    }

    pub fn sqlInsert(self: *Metadata, alloc: Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "INSERT INTO _metadata VALUES (");
        inline for (comptime std.meta.fieldNames(@TypeOf(self.*)), 0..) |nm, idx| {
            if (idx > 0) {
                try list.appendSlice(alloc, ", ");
            }
            if (@field(self, nm)) |v| {
                try list.append(alloc, 39);
                try list.appendSlice(alloc, v);
                try list.append(alloc, 39);
            } else {
                try list.appendSlice(alloc, "NULL");
            }
        }
        try list.append(alloc, ')');
        return list.toOwnedSlice(alloc);
    }
};

fn expect(el: xml.xmlNodePtr, exp: []const u8) !xml.xmlNodePtr {
    if (!std.mem.eql(u8, std.mem.span(el.*.name), exp)) return SiardError.UnexpectedElement;
    return el;
}

fn getValue(
    alloc: Allocator,
    el: xml.xmlNodePtr,
) ![]const u8 {
    return alloc.dupe(u8, std.mem.trim(u8, std.mem.span(xml.xmlNodeGetContent(el)), " \t\r\n"));
}

const Schema = struct {
    name: []const u8,
    folder: []const u8,
    tables: []Table,
    //views: []View, TODO
    //routines: []Routine, TODO

    fn init(self: *Schema, alloc: Allocator, schema: xml.xmlNodePtr) !void {
        var curr = try expect(xml.xmlFirstElementChild(schema), "name");
        self.name = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "folder");
        self.folder = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "tables");
        const table_count: usize = xml.xmlChildElementCount(curr);
        self.tables = try alloc.alloc(Table, table_count);
        var idx: usize = 0;
        var tbl = curr;
        while (idx < table_count) : (idx += 1) {
            tbl = if (idx == 0) try expect(xml.xmlFirstElementChild(tbl), "table") else try expect(xml.xmlNextElementSibling(tbl), "table");
            try self.tables[idx].init(alloc, tbl);
        }
    }

    fn deinit(self: *Schema, alloc: Allocator) void {
        alloc.free(self.name);
        alloc.free(self.folder);
        for (self.tables) |*tbl| {
            tbl.deinit(alloc);
        }
        alloc.free(self.tables);
    }
};

const Table = struct {
    name: []const u8,
    folder: []const u8,
    description: []const u8,
    columns: []Column,
    primaryKey: PrimaryKey,
    foreignKeys: ?[]ForeignKey,
    rows: u64,

    fn init(self: *Table, alloc: Allocator, table: xml.xmlNodePtr) !void {
        self.foreignKeys = null;
        var curr = try expect(xml.xmlFirstElementChild(table), "name");
        self.name = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "folder");
        self.folder = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "description");
        self.description = try getValue(alloc, curr);
        curr = try (expect(xml.xmlNextElementSibling(curr), "columns"));
        const col_count: usize = xml.xmlChildElementCount(curr);
        self.columns = try alloc.alloc(Column, col_count);
        var idx: usize = 0;
        var col = curr;
        while (idx < col_count) : (idx += 1) {
            col = if (idx == 0) try expect(xml.xmlFirstElementChild(col), "column") else try expect(xml.xmlNextElementSibling(col), "column");
            try self.columns[idx].init(alloc, col);
        }
        curr = xml.xmlNextElementSibling(curr);
        while (curr != null) : (curr = xml.xmlNextElementSibling(curr)) {
            if (std.mem.eql(u8, std.mem.span(curr.*.name), "primaryKey")) {
                try self.primaryKey.init(alloc, curr);
            } else if (std.mem.eql(u8, std.mem.span(curr.*.name), "foreignKeys")) {
                const fk_count: usize = xml.xmlChildElementCount(curr);
                self.foreignKeys = try alloc.alloc(ForeignKey, fk_count);
                idx = 0;
                var fk = curr;
                while (idx < fk_count) : (idx += 1) {
                    fk = if (idx == 0) try expect(xml.xmlFirstElementChild(fk), "foreignKey") else try expect(xml.xmlNextElementSibling(fk), "foreignKey");
                    try self.foreignKeys.?[idx].init(alloc, fk);
                }
            } else if (std.mem.eql(u8, std.mem.span(curr.*.name), "rows")) {
                self.rows = try std.fmt.parseInt(u64, std.mem.span(xml.xmlNodeGetContent(curr)), 10);
            }
        }
    }

    // \\ CREATE TABLE if not exists track(
    // \\   trackid     INTEGER,
    // \\   trackname   TEXT,
    // \\   trackartist INTEGER,
    // \\   FOREIGN KEY(trackartist) REFERENCES artist(artistid)
    // \\ )

    pub fn sqlSchema(self: *Table, alloc: Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "CREATE TABLE if not exists ");
        try list.appendSlice(alloc, self.name);
        try list.append(alloc, '(');
        var first: bool = true;
        for (self.columns) |col| {
            if (!first) {
                try list.appendSlice(alloc, ", ");
            } else {
                first = false;
            }
            try list.appendSlice(alloc, col.name);
            try list.append(alloc, ' ');
            try list.appendSlice(alloc, col.typ.asSqlite());
        }
        try list.appendSlice(alloc, ", PRIMARY KEY(");
        first = true;
        for (self.primaryKey.columns) |col| {
            if (!first) {
                try list.appendSlice(alloc, ", ");
            } else {
                first = false;
            }
            try list.appendSlice(alloc, col);
        }
        try list.append(alloc, ')');
        if (self.foreignKeys) |fks| {
            for (fks) |fk| {
                try list.appendSlice(alloc, ", FOREIGN KEY(");
                try list.appendSlice(alloc, fk.column);
                try list.appendSlice(alloc, ") REFERENCES ");
                try list.appendSlice(alloc, fk.reftable);
                try list.append(alloc, '(');
                try list.appendSlice(alloc, fk.referenced);
                try list.append(alloc, ')');
            }
        }
        try list.append(alloc, ')');
        return list.toOwnedSlice(alloc);
    }

    fn deinit(self: *Table, alloc: Allocator) void {
        alloc.free(self.name);
        alloc.free(self.folder);
        alloc.free(self.description);
        for (self.columns) |*col| {
            col.deinit(alloc);
        }
        alloc.free(self.columns);
        self.primaryKey.deinit(alloc);
        if (self.foreignKeys) |fks| {
            for (fks) |*fk| {
                fk.deinit(alloc);
            }
            alloc.free(fks);
        }
    }
};

const Column = struct {
    name: []const u8,
    typ: Typ,
    typeOriginal: []const u8,
    nullable: bool,

    fn init(self: *Column, alloc: Allocator, column: xml.xmlNodePtr) !void {
        var curr = try expect(xml.xmlFirstElementChild(column), "name");
        self.name = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "type");
        self.typ = Typ.fromStr(std.mem.span(xml.xmlNodeGetContent(curr)));
        curr = try expect(xml.xmlNextElementSibling(curr), "typeOriginal");
        self.typeOriginal = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "nullable");
        if (std.mem.eql(u8, std.mem.span(xml.xmlNodeGetContent(curr)), "true") or std.mem.eql(u8, std.mem.span(xml.xmlNodeGetContent(curr)), "TRUE")) {
            self.nullable = true;
        } else {
            self.nullable = false;
        }
    }

    fn deinit(self: *Column, alloc: Allocator) void {
        alloc.free(self.name);
        alloc.free(self.typeOriginal);
    }
};

const PrimaryKey = struct {
    name: []const u8,
    columns: [][]const u8,

    fn init(self: *PrimaryKey, alloc: Allocator, key: xml.xmlNodePtr) !void {
        var curr = try expect(xml.xmlFirstElementChild(key), "name");
        self.name = try getValue(alloc, curr);
        const col_count = xml.xmlChildElementCount(key) - 1;
        self.columns = try alloc.alloc([]const u8, col_count);
        var idx: usize = 0;
        while (idx < col_count) : (idx += 1) {
            curr = try expect(xml.xmlNextElementSibling(curr), "column");
            self.columns[idx] = try getValue(alloc, curr);
        }
    }

    fn deinit(self: *PrimaryKey, alloc: Allocator) void {
        alloc.free(self.name);
        for (self.columns) |col| {
            alloc.free(col);
        }
        alloc.free(self.columns);
    }
};

const ForeignKey = struct {
    name: []const u8,
    column: []const u8,
    refschema: []const u8,
    reftable: []const u8,
    referenced: []const u8,

    fn init(self: *ForeignKey, alloc: Allocator, key: xml.xmlNodePtr) !void {
        var curr = try expect(xml.xmlFirstElementChild(key), "name");
        self.name = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "referencedSchema");
        self.refschema = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "referencedTable");
        self.reftable = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "reference");
        curr = try expect(xml.xmlFirstElementChild(curr), "column");
        self.column = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "referenced");
        self.referenced = try getValue(alloc, curr);
    }

    fn deinit(self: *ForeignKey, alloc: Allocator) void {
        inline for (comptime std.meta.fieldNames(@TypeOf(self.*))) |nm| {
            alloc.free(@field(self, nm));
        }
    }
};

// TODO
const View = struct {};

// TODO
const Routine = struct {};

// TODO
const User = struct {};

// TODO
const Role = struct {};

test "siard" {
    const example = @import("test_example.zig").metadata;
    const d = xml.xmlReadMemory(example.ptr, @intCast(example.len), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    defer xml.xmlFreeDoc(d);
    const s = try new(std.testing.allocator, d);
    defer s.deinit(std.testing.allocator);
    try std.testing.expect(s.metadata.databaseProduct != null);
    try std.testing.expectEqualStrings(s.metadata.databaseProduct.?, "Microsoft SQL Server 12.00.2000");
    const sql = try s.schemas[0].tables[0].sqlSchema(std.testing.allocator);
    defer std.testing.allocator.free(sql);
    const expect_sql =
        \\CREATE TABLE if not exists Orders(OrderID INTEGER, CustomerID TEXT, EmployeeID INTEGER, OrderDate TEXT, RequiredDate TEXT, ShippedDate TEXT, ShipVia INTEGER, Freight NUMERIC, ShipName TEXT, ShipAddress TEXT, ShipCity TEXT, ShipRegion TEXT, ShipPostalCode TEXT, ShipCountry TEXT, PRIMARY KEY(OrderID), FOREIGN KEY(CustomerID) REFERENCES Customers(CustomerID), FOREIGN KEY(EmployeeID) REFERENCES Employees(EmployeeID), FOREIGN KEY(ShipVia) REFERENCES Shippers(ShipperID))
    ;
    try std.testing.expectEqualStrings(expect_sql, sql);
    const metadataInsert = try s.metadata.sqlInsert(std.testing.allocator);
    const expect_metadataInsert =
        \\INSERT INTO _metadata VALUES ('testnt', '(...)', '2015', 'file:///Northwind/', 'SiardEdit 1.80 Swiss Federal Archives, Berne, Switzerland, 2007-2015', '2015-11-26', 'MD53908342CA03FF371BDB9E92427930893', '10.50.32.247', 'Microsoft SQL Server 12.00.2000', 'jdbc:sqlserver://127.0.0.1:1433; authenticationScheme=nativeAuthentication; xopenStates=false; sendTimeAsDatetime=true; trustServerCertificate=false; sendStringParametersAsUnicode=true; selectMethod=cursor; responseBuffering=adaptive; packetSize=8000; multiSubnetFailover=false; loginTimeout=30; lockTimeout=-1; lastUpdateCount=true; encrypt=false; disableStatementPooling=true; databaseName=NORTHWND; applicationName=Microsoft JDBC Driver for SQL Server; applicationIntent=readwrite;\u0020', 'ptest2')
    ;
    defer std.testing.allocator.free(metadataInsert);
    try std.testing.expectEqualStrings(expect_metadataInsert, metadataInsert);
}
