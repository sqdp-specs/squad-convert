const std = @import("std");
const squadc = @import("squadc");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("Usage: squadc FILE.siard (please provide a siard file)", .{});
        return;
    };
    try squadc.convert(allocator, path);
}
