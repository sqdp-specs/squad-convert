const std = @import("std");
const xml = @import("xml");

fn index(z: u8, a: [*]const xml.xmlChar) ?usize {
    var i: usize = 0;
    while (true) : (i += 1) {
        if (a[i] == 0) return null;
        if (a[i] == z) return i;
    }
}

fn equals(a: [*]const xml.xmlChar, b: []const u8) bool {
    return equalsz(0, a, b);
}

fn equalsz(z: u8, a: [*]const xml.xmlChar, b: []const u8) bool {
    for (b, 0..) |char, idx| if (a[idx] != char) return false;
    return a[b.len] == z;
}

pub const Typ = union {
    unqualified: Unqualified,
    qualified: Qualified,
    interval: Interval,

    fn fromStr(str: [*]const xml.xmlChar) Typ {}
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

    fn fromStr(str: [*]const xml.xmlChar) Unqualified {
        if (equals(str, "BIGINT")) return .bigInt;
        if (equals(str, "BOOLEAN")) return .boolean;
        if (equals(str, "DATE")) return .date;
        if (equals(str, "DATALINK")) return .dataLink;
        if (equals(str, "DOUBLE PRECISION")) return .double;
        if (equals(str, "INTEGER") or equals(str, "INT")) return .integer;
        if (equals(str, "REAL")) return .real;
        if (equals(str, "SMALLINT")) return .smallInt;
        if (equals(str, "XML")) return .xml;
        return .none;
    }

    pub fn toStr(uq: Unqualified) []const u8 {
        return switch (uq) {
            else => "None",
        };
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

    fn fromStr(str: [*]const xml.xmlChar) QualType {
        if (equalsz('(', str, "BINARY LARGE OBJECT") or equalsz('(', str, "BLOB")) return .blob;
        if (equalsz('(', str, "BINARY VARYING") or equalsz('(', str, "VARBINARY")) return .varbinary;
        if (equalsz('(', str, "BINARY")) return .binary;
        if (equalsz('(', str, "CHARACTER LARGE OBJECT") or equalsz('(', str, "CLOB")) return .clob;
        if (equalsz('(', str, "CHARACTER VARYING") or equalsz('(', str, "CHAR VARYING") or equalsz('(', str, "VARCHAR")) return .varchar;
        if (equalsz('(', str, "DECIMAL") or equalsz('(', str, "DEC")) return .decimal;
        if (equalsz('(', str, "FLOAT")) return .float;
        if (equalsz('(', str, "NATIONAL CHARACTER LARGE OBJECT") or equalsz('(', str, "NCHAR LARGE OBJECT") or equalsz('(', str, "NCLOB")) return .nclob;
        if (equalsz('(', str, "NATIONAL CHARACTER VARYING") or equalsz('(', str, "NATIONAL CHAR VARYING") or equalsz('(', str, "NCHAR VARYING")) return .nvarchar;
        if (equalsz('(', str, "NNATIONAL CHARACTER") or equalsz('(', str, "NCHAR") or equalsz('(', str, "NATIONAL CHAR")) return .nchar;
        if (equalsz('(', str, "NUMERIC")) return .float;
        if (equalsz('(', str, "TIME")) return .time;
        if (equalsz('(', str, "TIME WITH TIME ZONE")) return .timez;
        if (equalsz('(', str, "TIMESTAMP")) return .timestamp;
        if (equalsz('(', str, "TIMESTAMP WITH TIME ZONE")) return .timestampz;
        return .none;
    }

    pub fn toStr(uq: QualType) []const u8 {
        return switch (uq) {
            else => "None",
        };
    }
};

const Qualified = struct {
    typ: QualType,
    qualifier: [2]u8,

    fn fromStr(str: [*]const xml.xmlChar) Qualified {
        const t = QualType.fromStr(str);

        if (idx == null or t == .none) return Qualified{
            .typ = .none,
            .qualifier = .{ 0, 0 },
        };

        std.fmt.parseInt(u8, foo, 10);
    }
};

fn getQualifier(str: [*]const xml.xmlChar) ?[2]u8 {
    var sidx: usize = index('(', str) orelse return null;
    sidx += 1;
    var eidx = sidx;
    var ret = [2]u8;
    var i = 0;
    while (true) : (eidx += 1) {
      if (eidx == ',') {
        if (eidx == sidx) return null;
        i += 1;
        if (i > 1) return null;
        eidx += 1;
        sidx = eidx;
        continue;
      }
      if (eidx == ')' or eidx == 0) {
         if (eidx == sidx) return null;
         ret[i] = std.fmt.parseInt(u8, ))
      }
    }
}

// INTERVAL <start> [TO <end>] xs:duration
const Interval = struct {
    start: u64,
    end: u64,
};
