const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
const Typ = @import("types.zig").Typ;
const Siard = @This();

const APO = 39;

const NULL = "NULL";

const SiardError = error{
    UnexpectedElement,
    EmptyTable,
    BadIndex,
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

pub const metadataSchema =
    \\CREATE TABLE if not exists _metadata(dbname TEXT, dataOwner TEXT, dataOriginTimespan TEXT, lobFolder TEXT, producerApplication TEXT, archivalDate TEXT, messageDigest TEXT, clientMachine TEXT, databaseProduct TEXT, connection TEXT, databaseUser TEXT)
;

pub const tablesSchema =
    \\CREATE TABLE if not exists _tables(id INTEGER, name TEXT, description TEXT)
;

pub const columnsSchema =
    \\CREATE TABLE if not exists _columns(tableid INTEGER, name TEXT, originalType TEXT)
;

// generates a placeholder string like (?, ?, ?). Caller owns the memory.
fn placeholders(alloc: Allocator, count: u8) ![]const u8 {
    var list = std.ArrayList(u8).empty;
    try list.append(alloc, '(');
    var idx: u8 = 0;
    while (idx < count) {
        if (idx > 0) {
            try list.appendSlice(alloc, ", ");
        }
        try list.append(alloc, '?');
        idx += 1;
    }
    try list.append(alloc, ')');
    return list.toOwnedSlice(alloc);
}

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

    pub fn sqlInsert(self: *Metadata, alloc: Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "INSERT INTO _metadata VALUES ");
        const plc = try placeholders(alloc, @truncate(std.meta.fieldNames(@TypeOf(self.*)).len));
        defer alloc.free(plc);
        try list.appendSlice(alloc, plc);
        return list.toOwnedSlice(alloc);
    }

    pub fn sqlValues(self: *Metadata, alloc: Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).empty;
        inline for (comptime std.meta.fieldNames(@TypeOf(self.*))) |nm| {
            if (@field(self, nm)) |v| {
                const vals = try alloc.dupe(u8, v);
                try list.append(alloc, vals);
            } else {
                const n = try alloc.dupe(u8, NULL);
                try list.append(alloc, n);
            }
        }
        return list.toOwnedSlice(alloc);
    }
};

fn optional(el: xml.xmlNodePtr, opt: []const u8) xml.xmlNodePtr {
    var curr = el;
    while (curr != null and expect(curr, opt) == SiardError.UnexpectedElement) : (curr = xml.xmlNextElementSibling(curr)) {}
    return curr;
}

fn expect(el: xml.xmlNodePtr, exp: []const u8) !xml.xmlNodePtr {
    if (!std.mem.eql(u8, std.mem.span(el.*.name), exp)) return SiardError.UnexpectedElement;
    return el;
}

// fn getValue(
//     alloc: Allocator,
//     el: xml.xmlNodePtr,
// ) ![]const u8 {
//     return alloc.dupe(u8, std.mem.trim(u8, std.mem.span(xml.xmlNodeGetContent(el)), " \t\r\n"));
// }

fn getValue(
    alloc: Allocator,
    el: xml.xmlNodePtr,
) ![]const u8 {
    const value = std.mem.span(xml.xmlNodeGetContent(el));
    std.mem.replaceScalar(u8, value, ' ', '_');
    return alloc.dupe(u8, value);
}

const Schema = struct {
    name: []const u8,
    folder: []const u8,
    tables: ?[]Table,
    //views: []View, TODO
    //routines: []Routine, TODO

    fn init(self: *Schema, alloc: Allocator, schema: xml.xmlNodePtr) !void {
        var curr = try expect(xml.xmlFirstElementChild(schema), "name");
        self.name = try getValue(alloc, curr);
        curr = try expect(xml.xmlNextElementSibling(curr), "folder");
        self.folder = try getValue(alloc, curr);
        curr = optional(curr, "tables");
        if (curr == null) return;
        const table_count: usize = xml.xmlChildElementCount(curr);
        self.tables = try alloc.alloc(Table, table_count);
        var idx: usize = 0;
        var tbl = curr;
        while (idx < table_count) : (idx += 1) {
            tbl = if (idx == 0) try expect(xml.xmlFirstElementChild(tbl), "table") else try expect(xml.xmlNextElementSibling(tbl), "table");
            try self.tables.?[idx].init(alloc, tbl);
        }
    }

    fn deinit(self: *Schema, alloc: Allocator) void {
        alloc.free(self.name);
        alloc.free(self.folder);
        if (self.tables) |tables| {
            for (tables) |*tbl| {
                tbl.deinit(alloc);
            }
            alloc.free(tables);
        }
    }

    pub fn sqlInsertTbls(_: *Schema, alloc: Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "INSERT INTO _tables VALUES ");
        const plc = try placeholders(alloc, 3);
        defer alloc.free(plc);
        try list.appendSlice(alloc, plc);
        return list.toOwnedSlice(alloc);
    }

    pub fn sqlInsertTblVals(self: *Schema, alloc: Allocator, idx: usize) ![][]const u8 {
        const tables = self.tables orelse return SiardError.EmptyTable;
        const row = if (idx < tables.len) tables[idx] else return SiardError.BadIndex;
        var int_buf = [_]u8{0} ** 16;
        var list = std.ArrayList([]const u8).empty;
        const l = std.fmt.printInt(int_buf[0..], idx, 10, std.fmt.Case.lower, .{});
        const num = try alloc.dupe(u8, int_buf[0..l]);
        try list.append(alloc, num);
        const name = try alloc.dupe(u8, row.name);
        try list.append(alloc, name);
        const desc = blk: {
            if (row.description) |d| {
                break :blk if (d.len == 0) try alloc.dupe(u8, NULL) else try alloc.dupe(u8, d);
            } else break :blk try alloc.dupe(u8, NULL);
        };
        try list.append(alloc, desc);
        return list.toOwnedSlice(alloc);
    }

    pub fn sqlInsertCols(_: *Schema, alloc: Allocator) ![]const u8 {
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "INSERT INTO _columns VALUES ");
        const plc = try placeholders(alloc, 3);
        defer alloc.free(plc);
        try list.appendSlice(alloc, plc);
        return list.toOwnedSlice(alloc);
    }

    pub fn sqlInsertColsVals(self: *Schema, alloc: Allocator, tidx: usize, cidx: usize) ![][]const u8 {
        const tables = self.tables orelse return SiardError.EmptyTable;
        const tbl = if (tidx < tables.len) tables[tidx] else return SiardError.BadIndex;
        const col = if (cidx < tbl.columns.len) tbl.columns[cidx] else return SiardError.BadIndex;
        var int_buf = [_]u8{0} ** 16;
        var list = std.ArrayList([]const u8).empty;
        const l = std.fmt.printInt(int_buf[0..], tidx, 10, std.fmt.Case.lower, .{});
        const num = try alloc.dupe(u8, int_buf[0..l]);
        try list.append(alloc, num);
        const name = try alloc.dupe(u8, col.name);
        try list.append(alloc, name);
        const otype = blk: {
            if (col.typeOriginal) |ot| {
                break :blk if (ot.len == 0) try alloc.dupe(u8, NULL) else try alloc.dupe(u8, ot);
            } else break :blk try alloc.dupe(u8, NULL);
        };
        try list.append(alloc, otype);
        return list.toOwnedSlice(alloc);
    }
};

fn toIdx(name: []const u8) !usize {
    return try std.fmt.parseInt(u8, name[1..], 10);
}

const Table = struct {
    name: []const u8,
    folder: []const u8,
    description: ?[]const u8,
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
        const desc = expect(xml.xmlNextElementSibling(curr), "description") catch null;
        if (desc != null) {
            self.description = try getValue(alloc, desc);
            curr = desc;
        } else self.description = null;
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
    // generate SQL CREATE TABLE statement
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
    // generateSqlInsertStatement
    pub fn sqlInsert(self: *Table, alloc: Allocator, doc: [*c]xml.xmlDoc) ![]const u8 {
        if (self.rows == 0) {
            return SiardError.EmptyTable;
        }
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "INSERT INTO ");
        try list.appendSlice(alloc, self.name);
        try list.appendSlice(alloc, " VALUES ");

        const root = xml.xmlDocGetRootElement(doc);
        var row = xml.xmlFirstElementChild(root);
        var firstRow: bool = true;

        while (row != null) : (row = xml.xmlNextElementSibling(row)) {
            if (firstRow) {
                try list.append(alloc, '(');
                firstRow = false;
            } else {
                try list.appendSlice(alloc, ", (");
            }
            var col = xml.xmlFirstElementChild(row);
            var colIdx: usize = try toIdx(std.mem.span(col.*.name));
            for (self.columns, 0..) |column, cidx| {
                if (cidx > 0) {
                    try list.appendSlice(alloc, ", ");
                }
                if (col == null or colIdx > cidx + 1) {
                    try list.appendSlice(alloc, "NULL");
                    continue;
                }
                const val: []u8 = std.mem.span(xml.xmlNodeGetContent(col));
                std.mem.replaceScalar(u8, val, APO, '_');
                if (val.len == 0) {
                    try list.appendSlice(alloc, "NULL");
                } else {
                    if (column.typ.quote()) {
                        try list.append(alloc, APO);
                        try list.appendSlice(alloc, val);
                        try list.append(alloc, APO);
                    } else {
                        try list.appendSlice(alloc, val);
                    }
                }
                col = xml.xmlNextElementSibling(col);
                if (col != null) {
                    colIdx = try toIdx(std.mem.span(col.*.name));
                }
            }
            try list.append(alloc, ')');
        }
        return list.toOwnedSlice(alloc);
    }

    // generateSqlInsertStatement
    pub fn sqlStmt(self: *Table, alloc: Allocator) ![]const u8 {
        if (self.rows == 0) {
            return SiardError.EmptyTable;
        }
        var list = std.ArrayList(u8).empty;
        try list.appendSlice(alloc, "INSERT INTO ");
        try list.appendSlice(alloc, self.name);
        try list.appendSlice(alloc, " VALUES ");
        const plc = try placeholders(alloc, @truncate(self.columns.len));
        defer alloc.free(plc);
        try list.appendSlice(alloc, plc);
        return list.toOwnedSlice(alloc);
    }

    // return a table of values, caller owns the memory.
    pub fn sqlVals(self: *Table, alloc: Allocator, doc: [*c]xml.xmlDoc) ![][][]const u8 {
        if (self.rows == 0) {
            return SiardError.EmptyTable;
        }
        var table = std.ArrayList([][][]const u8).empty;

        const root = xml.xmlDocGetRootElement(doc);
        var row = xml.xmlFirstElementChild(root);

        while (row != null) : (row = xml.xmlNextElementSibling(row)) {
            var tableRow = std.ArrayList([][]const u8).empty;
            var col = xml.xmlFirstElementChild(row);
            var colIdx: usize = try toIdx(std.mem.span(col.*.name));
            for (self.columns, 0..) |_, cidx| {
                if (col == null or colIdx > cidx + 1) {
                    const n = try alloc.dupe(u8, NULL);
                    try tableRow.append(alloc, n);
                    continue;
                }
                const val: []u8 = std.mem.span(xml.xmlNodeGetContent(col));
                if (val.len == 0) {
                    const n = try alloc.dupe(u8, NULL);
                    try tableRow.append(alloc, n);
                } else {
                    const v = try alloc.dupe(u8, val);
                    try tableRow.append(alloc, v);
                }
                col = xml.xmlNextElementSibling(col);
                if (col != null) {
                    colIdx = try toIdx(std.mem.span(col.*.name));
                }
            }
            const slc = try tableRow.toOwnedSlice(alloc);
            try table.append(alloc, slc);
        }
        return table.toOwnedSlice(alloc);
    }

    fn deinit(self: *Table, alloc: Allocator) void {
        alloc.free(self.name);
        alloc.free(self.folder);
        if (self.description != null) alloc.free(self.description.?);
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
    typeOriginal: ?[]const u8,
    nullable: bool,

    fn init(self: *Column, alloc: Allocator, column: xml.xmlNodePtr) !void {
        const curr = try expect(xml.xmlFirstElementChild(column), "name");
        self.name = try getValue(alloc, curr);
        const typ = optional(xml.xmlNextElementSibling(curr), "type");
        self.typ = if (typ != null) Typ.fromStr(std.mem.span(xml.xmlNodeGetContent(typ))) else Typ.fromStr(@constCast("BLOB"));
        const typeOriginal = optional(curr, "typeOriginal");
        if (typeOriginal != null) self.typeOriginal = try getValue(alloc, curr) else self.typeOriginal = null;
        const nullable = optional(curr, "nullable");
        if (nullable == null) {
            self.nullable = false;
            return;
        }
        self.nullable = if (std.mem.eql(u8, std.mem.span(xml.xmlNodeGetContent(curr)), "true") or std.mem.eql(u8, std.mem.span(xml.xmlNodeGetContent(curr)), "TRUE")) true else false;
    }

    fn deinit(self: *Column, alloc: Allocator) void {
        alloc.free(self.name);
        if (self.typeOriginal != null) alloc.free(self.typeOriginal.?);
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
    const sql = try s.schemas[0].tables.?[0].sqlSchema(std.testing.allocator);
    defer std.testing.allocator.free(sql);
    const expect_sql =
        \\CREATE TABLE if not exists Orders(OrderID INTEGER, CustomerID TEXT, EmployeeID INTEGER, OrderDate TEXT, RequiredDate TEXT, ShippedDate TEXT, ShipVia INTEGER, Freight NUMERIC, ShipName TEXT, ShipAddress TEXT, ShipCity TEXT, ShipRegion TEXT, ShipPostalCode TEXT, ShipCountry TEXT, PRIMARY KEY(OrderID), FOREIGN KEY(CustomerID) REFERENCES Customers(CustomerID), FOREIGN KEY(EmployeeID) REFERENCES Employees(EmployeeID), FOREIGN KEY(ShipVia) REFERENCES Shippers(ShipperID))
    ;
    try std.testing.expectEqualStrings(expect_sql, sql);
    const metadataInsert = try s.metadata.sqlInsert(std.testing.allocator);
    const expect_metadataInsert =
        \\INSERT INTO _metadata VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ;
    try std.testing.expectEqualStrings(expect_metadataInsert, metadataInsert);
    std.testing.allocator.free(metadataInsert);
    const metadataVals = try s.metadata.sqlValues(std.testing.allocator);
    const exp: [11][]const u8 = .{ "testnt", "(...)", "2015", "file:///Northwind/", "SiardEdit 1.80 Swiss Federal Archives, Berne, Switzerland, 2007-2015", "2015-11-26", "MD53908342CA03FF371BDB9E92427930893", "10.50.32.247", "Microsoft SQL Server 12.00.2000", "jdbc:sqlserver://127.0.0.1:1433; authenticationScheme=nativeAuthentication; xopenStates=false; sendTimeAsDatetime=true; trustServerCertificate=false; sendStringParametersAsUnicode=true; selectMethod=cursor; responseBuffering=adaptive; packetSize=8000; multiSubnetFailover=false; loginTimeout=30; lockTimeout=-1; lastUpdateCount=true; encrypt=false; disableStatementPooling=true; databaseName=NORTHWND; applicationName=Microsoft JDBC Driver for SQL Server; applicationIntent=readwrite;\\u0020", "ptest2" };
    try std.testing.expectEqualDeep(exp[0..], metadataVals);
    for (metadataVals) |v| std.testing.allocator.free(v);
    std.testing.allocator.free(metadataVals);
}

test "placeholders" {
    const plc = try placeholders(std.testing.allocator, 5);
    defer std.testing.allocator.free(plc);
    try std.testing.expectEqualStrings("(?, ?, ?, ?, ?)", plc);
}
