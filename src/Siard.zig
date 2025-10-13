const std = @import("std");

dbname: []const u8,
dataOwnder: []const u8,
dataOriginTimespan: []const u8,
lobFolder: []const u8,
producerApplication: []const u8,
archivalData: []const u8,
messageDigest: []const u8,
clientMachine: []const u8,
databaseProduct: []const u8,
connection: []const u8,
databaseUser: []const u8,

const Schema = struct {
    name: []const u8,
    folder: []const u8,
};

const Table = struct {};
