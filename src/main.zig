const std = @import("std");
const squadc = @import("squadc");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("Usage: squadc FILE.siard (please provide a siard file)", .{});
        return;
    };
    args.deinit();
    try squadc.convert(init.gpa, path);
}
