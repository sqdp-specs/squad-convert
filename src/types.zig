const std = @import("std");
const xml = @import("xml");

pub const Typ = union(enum) {
    unqualified: Unqualified,
    qualified: Qualified,
    // interval: Interval, TODO

    pub fn fromStr(str: []u8) Typ {
        const u = Unqualified.fromStr(str);
        if (u != .none) {
            return Typ{ .unqualified = u };
        }
        return Typ{ .qualified = Qualified.fromStr(str) };
    }

    // should this type be enclosed in quotes in insert syntax
    pub fn quote(self: Typ) bool {
        switch (self) {
            .unqualified => |u| return u.quote(),
            .qualified => |q| return q.quote(),
        }
    }

    pub fn asSqlite(self: Typ) []const u8 {
        switch (self) {
            .unqualified => |u| return u.asSqlite(),
            .qualified => |q| return q.asSqlite(),
        }
    }
};

const Unqualified = enum {
    bigInt, // BIGINT xs:integer
    boolean, // BOOLEAN xs:boolean
    date, // DATE dateType
    dataLink, // DATALINK blobType / clobType13
    double, // DOUBLE PRECISION xs:double
    integer, // INTEGER, INT xs:integer
    real, // REAL xs:float
    smallInt, // SMALLINT xs:integer
    xml, // XML clobType11
    none,

    fn fromStr(str: []u8) Unqualified {
        if (std.mem.eql(u8, str, "BIGINT")) return .bigInt;
        if (std.mem.eql(u8, str, "BOOLEAN")) return .boolean;
        if (std.mem.eql(u8, str, "DATE")) return .date;
        if (std.mem.eql(u8, str, "DATALINK")) return .dataLink;
        if (std.mem.eql(u8, str, "DOUBLE PRECISION")) return .double;
        if (std.mem.eql(u8, str, "INTEGER") or std.mem.eql(u8, str, "INT")) return .integer;
        if (std.mem.eql(u8, str, "REAL")) return .real;
        if (std.mem.eql(u8, str, "SMALLINT")) return .smallInt;
        if (std.mem.eql(u8, str, "XML")) return .xml;
        return .none;
    }

    fn asSqlite(self: Unqualified) []const u8 {
        switch (self) {
            .bigInt, .integer, .smallInt => return "INTEGER",
            .boolean, .date => return "NUMERIC",
            .real, .double => return "REAL",
            .xml => return "TEXT",
            .dataLink => return "BLOB",
            .none => return "",
        }
    }

    fn quote(self: Unqualified) bool {
        switch (self) {
            .xml, .dataLink => return true,
            _ => return false,
        }
    }
};

const QualType = enum {
    blob, // BINARY LARGE OBJECT(...), BLOB(...) blobType12
    varbinary, // BINARY VARYING(...), VARBINARY(...) xs:hexBinary / clobType13
    binary, // BINARY(…) xs:hexBinary / blobType13
    clob, // CHARACTER LARGE OBJECT(...), CLOB(...) clobType13
    varchar, // CHARACTER VARYING(...), CHAR VARYING(...), VARCHAR(...) xs:string / clobType13
    char, // CHARACTER(...), CHAR(...) xs:string / clobType13
    decimal, // DECIMAL(...), DEC(...) xs:decimal
    float, // FLOAT(p) xs:double
    nclob, // NATIONAL CHARACTER LARGE OBJECT(...), NCHAR LARGE OBJECT(...), NCLOB(...) clobType13
    nvarchar, // NATIONAL CHARACTER VARYING(...), NATIONAL CHAR VARYING(...), NCHAR VARYING(...) xs:string / clobType13
    nchar, // NATIONAL CHARACTER(...), NCHAR(...), NATIONAL CHAR(...), xs:string / clobType13
    numeric, // NUMERIC(...) xs:decimal
    time, // TIME(...) timeType
    timez, // TIME WITH TIME ZONE(...) timeType
    timestamp, // TIMESTAMP(...) dateTimeType
    timestampz, // TIMESTAMP WITH TIME ZONE(...) dateTimeType
    none,

    fn fromStr(str: []u8) QualType {
        if (std.mem.startsWith(u8, str, "BINARY LARGE OBJECT(") or std.mem.startsWith(u8, str, "BLOB(")) return .blob;
        if (std.mem.startsWith(u8, str, "BINARY VARYING(") or std.mem.startsWith(u8, str, "VARBINARY(")) return .varbinary;
        if (std.mem.startsWith(u8, str, "BINARY(")) return .binary;
        if (std.mem.startsWith(u8, str, "CHARACTER LARGE OBJECT(") or std.mem.startsWith(u8, str, "CLOB(")) return .clob;
        if (std.mem.startsWith(u8, str, "CHARACTER VARYING(") or std.mem.startsWith(u8, str, "CHAR VARYING") or std.mem.startsWith(u8, str, "VARCHAR(")) return .varchar;
        if (std.mem.startsWith(u8, str, "DECIMAL(") or std.mem.startsWith(u8, str, "DEC(")) return .decimal;
        if (std.mem.startsWith(u8, str, "FLOAT(")) return .float;
        if (std.mem.startsWith(u8, str, "NATIONAL CHARACTER LARGE OBJECT(") or std.mem.startsWith(u8, str, "NCHAR LARGE OBJECT(") or std.mem.startsWith(u8, str, "NCLOB(")) return .nclob;
        if (std.mem.startsWith(u8, str, "NATIONAL CHARACTER VARYING(") or std.mem.startsWith(u8, str, "NATIONAL CHAR VARYING(") or std.mem.startsWith(u8, str, "NCHAR VARYING(")) return .nvarchar;
        if (std.mem.startsWith(u8, str, "NATIONAL CHARACTER(") or std.mem.startsWith(u8, str, "NCHAR(") or std.mem.startsWith(u8, str, "NATIONAL CHAR(")) return .nchar;
        if (std.mem.startsWith(u8, str, "NUMERIC(")) return .float;
        if (std.mem.startsWith(u8, str, "TIME(")) return .time;
        if (std.mem.startsWith(u8, str, "TIME WITH TIME ZONE(")) return .timez;
        if (std.mem.startsWith(u8, str, "TIMESTAMP(")) return .timestamp;
        if (std.mem.startsWith(u8, str, "TIMESTAMP WITH TIME ZONE(")) return .timestampz;
        return .none;
    }
};

const Qualified = struct {
    typ: QualType,
    qualifier: [2]u8,

    fn fromStr(str: []u8) Qualified {
        const t = QualType.fromStr(str);
        const q = getQualifier(str);
        if (q == null or t == .none) return Qualified{
            .typ = .none,
            .qualifier = .{ 0, 0 },
        };
        return Qualified{ .typ = t, .qualifier = q.? };
    }

    fn asSqlite(self: Qualified) []const u8 {
        switch (self.typ) {
            .decimal, .numeric => return "NUMERIC",
            .float => return "REAL",
            .clob, .varchar, .char, .nclob, .nvarchar, .nchar, .time, .timez, .timestamp, .timestampz => return "TEXT",
            .blob, .varbinary, .binary => return "BLOB",
            .none => return "",
        }
    }

    fn quote(self: Qualified) bool {
        switch (self) {
            .decimal, .numeric, .float, .none => return false,
            _ => return true,
        }
    }
};

fn getQualifier(str: []u8) ?[2]u8 {
    var sidx: usize = std.mem.indexOfScalar(u8, str, '(') orelse return null;
    sidx += 1;
    var eidx = sidx;
    var ret = [2]u8{ 0, 0 };
    var i: usize = 0;
    while (eidx < str.len) : (eidx += 1) {
        if (str[eidx] == ',') {
            if (eidx == sidx) return null;
            ret[i] = std.fmt.parseInt(u8, str[sidx..eidx], 10) catch return null;
            i += 1;
            if (i > 1) return null;
            eidx += 1;
            sidx = eidx;
            continue;
        }
        if (str[eidx] == ')') {
            if (eidx == sidx) return null;
            ret[i] = std.fmt.parseInt(u8, str[sidx..eidx], 10) catch return null;
            return ret;
        }
    }
    return null;
}

// INTERVAL <start> [TO <end>] xs:duration
const Interval = struct {
    start: u64,
    end: u64,
};

test "types" {
    const types =
        \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\<columns>
        \\   <column>
        \\     <name>ShippedDate</name>
        \\     <type>TIMESTAMP(7)</type>
        \\     <typeOriginal>datetime</typeOriginal>
        \\     <nullable>true</nullable>
        \\   </column>
        \\   <column>
        \\     <name>ShipVia</name>
        \\     <type>INTEGER</type>
        \\     <typeOriginal>int</typeOriginal>
        \\     <nullable>true</nullable>
        \\   </column>
        \\   <column>
        \\     <name>Freight</name>
        \\     <type>DECIMAL(19,4)</type>
        \\     <typeOriginal>money</typeOriginal>
        \\     <nullable>true</nullable>
        \\   </column>
        \\   <column>
        \\     <name>ShipName</name>
        \\     <type>NATIONAL CHARACTER VARYING(40)</type>
        \\     <typeOriginal>nvarchar(40)</typeOriginal>
        \\     <nullable>true</nullable>
        \\   </column>
        \\   <column>
        \\     <name>ShipCity</name>
        \\     <type>NATIONAL CHARACTER VARYING(15)</type>
        \\     <typeOriginal>nvarchar(15)</typeOriginal>
        \\     <nullable>true</nullable>
        \\   </column>
        \\</columns>
    ;
    const d = xml.xmlReadMemory(types.ptr, @intCast(types.len), null, "utf-8", xml.XML_PARSE_NOBLANKS | xml.XML_PARSE_RECOVER | xml.XML_PARSE_NOERROR | xml.XML_PARSE_NOWARNING);
    const root = xml.xmlDocGetRootElement(d);
    var col = xml.xmlFirstElementChild(root);
    const expect = [_]Typ{
        Typ{ .qualified = .{ .typ = .timestamp, .qualifier = .{ 7, 0 } } },
        Typ{ .unqualified = .integer },
        Typ{ .qualified = .{ .typ = .decimal, .qualifier = .{ 19, 4 } } },
        Typ{ .qualified = .{ .typ = .nvarchar, .qualifier = .{ 40, 0 } } },
        Typ{ .qualified = .{ .typ = .nvarchar, .qualifier = .{ 15, 0 } } },
    };
    var i: usize = 0;
    while (col != null) : (col = xml.xmlNextElementSibling(col)) {
        const name = xml.xmlFirstElementChild(col);
        const typ = xml.xmlNextElementSibling(name);
        const t = Typ.fromStr(std.mem.span(xml.xmlNodeGetContent(typ)));
        try std.testing.expect(std.meta.eql(t, expect[i]));
        i += 1;
    }
}
