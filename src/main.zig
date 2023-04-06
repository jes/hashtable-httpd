const std = @import("std");

var response_table: std.StringHashMap([]const u8) = undefined;

pub fn main() !void {
    response_table = makeResponseTable();
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

fn makeResponseTable() std.StringHashMap([]const u8) {
    var table = std.StringHashMap([]const u8).init(std.heap.page_allocator);
    table.put("GET / HTTP/1.1", "HTTP/1.1 200 OK\r\nContent-type: text/plain\r\nConnection: close\r\nContent-length: 12\r\n\r\nhello world\n") catch unreachable;
    return table;
}
