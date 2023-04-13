const std = @import("std");
const os = @import("os");

var response_table: std.StringHashMap([]const u8) = undefined;

const listen_port = 8100;
const docroot_path = "www";
const max_file_size = 1048576; // bytes

pub fn main() !void {
    makeResponseTable() catch |err| {
        std.debug.print("makeResponseTable: {}\n", .{err});
        std.process.exit(1);
    };
    var listener = std.net.StreamServer.init(std.net.StreamServer.Options{ .reuse_address = true });
    try listener.listen(try std.net.Address.parseIp4("0.0.0.0", listen_port));
    std.debug.print("listening on port {d}\n", .{listen_port});
    while (true) {
        const conn = listener.accept() catch |err| {
            std.debug.print("accept: {}\n", .{err});
            std.process.exit(1);
        };
        // TODO: how expensive is spawning a thread? would we rather use async
        // io? would we rather have a thread pool with aysnc within each pool?
        _ = std.Thread.spawn(.{}, handler, .{conn}) catch |err| {
            std.debug.print("std.Thread.spawn: {}\n", .{err});
            conn.stream.close();
        };
    }
}

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    const line = (try reader.readUntilDelimiterOrEof(
        buffer,
        '\n',
    )) orelse return null;
    return std.mem.trimRight(u8, line, "\r");
}

fn handler(conn: std.net.StreamServer.Connection) !void {
    defer conn.stream.close();
    handleRequest(conn) catch |err| {
        std.debug.print("handleRequest: {}\n", .{err});
    };
    std.debug.print("disconnected\n", .{});
}

fn handleRequest(conn: std.net.StreamServer.Connection) !void {
    var buf: [1000]u8 = undefined;
    while (true) {
        const request = try nextLine(conn.stream.reader(), &buf) orelse break;
        // TODO: extract important headers; in particular we (might) care about
        // Host, Connection, Range, ...?
        try skipHeaders(conn);
        std.debug.print("> {s}\n", .{request});
        if (response_table.get(request)) |response| {
            try conn.stream.writeAll(response);
        } else {
            try send404(conn);
        }
        // TODO: read request body, if any? do whatever is needed to either read
        // up to the point where we're expecting a new request, or else cleanly
        // close the connection
    }
}

// keep reading until we pass an empty line
fn skipHeaders(conn: std.net.StreamServer.Connection) !void {
    var buf: [1000]u8 = undefined;
    while (true) {
        const line = try nextLine(conn.stream.reader(), &buf) orelse return error.EndOfStream;
        if (line.len == 0) break;
    }
}

fn send404(conn: std.net.StreamServer.Connection) !void {
    // TODO: read from /404.html ?
    try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\nConnection: keep-alive\r\nContent-type: text/html\r\nContent-length: 4\r\n\r\n404\n");
}

fn makeResponseTable() !void {
    response_table = std.StringHashMap([]const u8).init(std.heap.page_allocator);

    const docroot = try std.fs.cwd().openIterableDir(docroot_path, .{});
    try addFiles(docroot, "");
}

fn addFiles(dir: std.fs.IterableDir, name: []const u8) !void {
    var d = dir.iterate();

    while (true) {
        const e = try d.next() orelse break;
        const filename = std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ name, e.name }) catch break;
        if (e.kind == .File) {
            try addFile(dir.dir.openFile(e.name, .{}) catch break, filename);
        } else {
            try addFiles(dir.dir.openIterableDir(e.name, .{}) catch break, filename);
        }
        std.debug.print("{s}\n", .{filename});
    }
}

fn addFile(file: std.fs.File, name: []const u8) !void {
    const content = try file.readToEndAlloc(std.heap.page_allocator, max_file_size);
    const headers10 = try std.fmt.allocPrint(std.heap.page_allocator, "Content-type: text/html\r\nContent-length: {d}\r\n", .{content.len});
    const headers11 = try std.fmt.allocPrint(std.heap.page_allocator, "Connection: keep-alive\r\nContent-type: text/html\r\nContent-length: {d}\r\n", .{content.len});
    try response_table.put(try std.fmt.allocPrint(std.heap.page_allocator, "GET {s} HTTP/1.0", .{name}), try std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.0 200 OK\r\n{s}\r\n{s}", .{ headers10, content }));
    try response_table.put(try std.fmt.allocPrint(std.heap.page_allocator, "GET {s} HTTP/1.1", .{name}), try std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 200 OK\r\n{s}\r\n{s}", .{ headers11, content }));
    try response_table.put(try std.fmt.allocPrint(std.heap.page_allocator, "HEAD {s} HTTP/1.0", .{name}), try std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.0 200 OK\r\n{s}\r\n", .{headers10}));
    try response_table.put(try std.fmt.allocPrint(std.heap.page_allocator, "HEAD {s} HTTP/1.1", .{name}), try std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 200 OK\r\n{s}\r\n", .{headers11}));
}
