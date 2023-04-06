const std = @import("std");
const os = @import("os");

var response_table: std.StringHashMap([]const u8) = undefined;

pub fn main() !void {
    makeResponseTable();
    var listener = std.net.StreamServer.init(std.net.StreamServer.Options{ .reuse_address = true });
    const port = 8100;
    try listener.listen(try std.net.Address.parseIp4("0.0.0.0", port));
    std.debug.print("listening on port {d}\n", .{port});
    while (true) {
        var conn = listener.accept() catch break;
        _ = try std.Thread.spawn(std.Thread.SpawnConfig{}, handler, .{conn});
    }
    std.debug.print("dieded\n", .{});
}

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(
        buffer,
        '\n',
    )) orelse return null;
    return std.mem.trimRight(u8, line, "\r");
}

fn handler(conn: std.net.StreamServer.Connection) !void {
    var buf: [100000]u8 = undefined;
    while (true) {
        const line = (nextLine(conn.stream.reader(), &buf) catch break);
        if (line == null) break;
        const request = line.?;
        std.debug.print("> {s}\n", .{request});
        var response = response_table.get(request);
        if (response == null) {
            send_404(conn) catch break;
            break;
        }
        _ = conn.stream.write(response.?) catch break;
        break;
    }
    conn.stream.close();
    std.debug.print("disconnected\n", .{});
}

fn send_404(conn: std.net.StreamServer.Connection) !void {
    _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\nContent-type: text/plain\r\nConnection: close\r\n\r\n404\n");
}

fn makeResponseTable() void {
    var dir = std.fs.cwd().openDir("www", .{}) catch return;
    var iterabledir = dir.openIterableDir(".", .{}) catch return;
    //if (dir == null) {
    //    std.debug.print("can't open www/\n", .{});
    //    return;
    //}
    var d = iterabledir.iterate();

    response_table = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    while (true) {
        var entry = d.next() catch break;
        if (entry == null) break;
        var e = entry.?;
        addFile(dir, e.name);
        std.debug.print("{s}\n", .{e.name});
    }
}

fn addFile(dir: std.fs.Dir, name: []const u8) void {
    var file = dir.openFile(name, .{}) catch return;
    var content = file.readToEndAlloc(std.heap.page_allocator, 1024) catch return;
    var headers = std.fmt.allocPrint(std.heap.page_allocator, "Connection: close\r\nContent-type: text/html\r\nContent-length: {d}\r\n", .{content.len}) catch return;
    response_table.put(std.fmt.allocPrint(std.heap.page_allocator, "GET /{s} HTTP/1.0", .{name}) catch return, std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.0 200 OK\r\n{s}\r\n{s}", .{ headers, content }) catch return) catch return;
    response_table.put(std.fmt.allocPrint(std.heap.page_allocator, "GET /{s} HTTP/1.1", .{name}) catch return, std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 200 OK\r\n{s}\r\n{s}", .{ headers, content }) catch return) catch return;
}
