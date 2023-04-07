const std = @import("std");
const os = @import("os");

var response_table: std.StringHashMap([]const u8) = undefined;

var docroot_path = "www";
var max_file_size = 1048576; // bytes

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
    var buf: [1000]u8 = undefined;
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
    response_table = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    var docroot = std.fs.cwd().openIterableDir(docroot_path, .{}) catch return;
    addFiles(docroot, "");
}

fn addFiles(dir: std.fs.IterableDir, name: []const u8) void {
    var d = dir.iterate();

    while (true) {
        var entry = d.next() catch break;
        if (entry == null) break;
        var e = entry.?;
        var filename = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ name, e.name }) catch break;
        if (e.kind == .File) {
            addFile(dir.dir.openFile(e.name, .{}) catch break, filename);
        } else {
            addFiles(dir.dir.openIterableDir(e.name, .{}) catch break, filename);
        }
        std.debug.print("{s}\n", .{filename});
    }
}

fn addFile(file: std.fs.File, name: []const u8) void {
    var content = file.readToEndAlloc(std.heap.page_allocator, max_file_size) catch return;
    var headers10 = std.fmt.allocPrint(std.heap.page_allocator, "Content-type: text/html\r\nContent-length: {d}\r\n", .{content.len}) catch return;
    var headers11 = std.fmt.allocPrint(std.heap.page_allocator, "Connection: close\r\nContent-type: text/html\r\nContent-length: {d}\r\n", .{content.len}) catch return;
    response_table.put(std.fmt.allocPrint(std.heap.page_allocator, "GET {s} HTTP/1.0", .{name}) catch return, std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.0 200 OK\r\n{s}\r\n{s}", .{ headers10, content }) catch return) catch return;
    response_table.put(std.fmt.allocPrint(std.heap.page_allocator, "GET {s} HTTP/1.1", .{name}) catch return, std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 200 OK\r\n{s}\r\n{s}", .{ headers11, content }) catch return) catch return;
    response_table.put(std.fmt.allocPrint(std.heap.page_allocator, "HEAD {s} HTTP/1.0", .{name}) catch return, std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.0 200 OK\r\n{s}\r\n", .{headers10}) catch return) catch return;
    response_table.put(std.fmt.allocPrint(std.heap.page_allocator, "HEAD {s} HTTP/1.1", .{name}) catch return, std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 200 OK\r\n{s}\r\n", .{headers11}) catch return) catch return;
}
