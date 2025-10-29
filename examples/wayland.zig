const std = @import("std");
const xml = @import("xml");

const Protocol = struct {
    name: xml.Attribute("name"),
    copyright: xml.OptionalElement("copyright", Copyright),
    description: xml.OptionalElement("description", Description),
    interfaces: xml.ElementList("interface", Interface),
};

const Interface = struct {
    name: xml.Attribute("name"),
    version: xml.Attribute("version"),
    description: xml.OptionalElement("description", Description),
    requests: xml.ElementList("request", Request),
    events: xml.ElementList("event", Event),
    enums: xml.ElementList("enum", Enum),
};

const Request = struct {
    name: xml.Attribute("name"),
    type: xml.OptionalAttribute("type"),
    since: xml.OptionalAttribute("since"),
    deprecated_since: xml.OptionalAttribute("deprecated-since"),
    description: xml.OptionalElement("description", Description),
    args: xml.ElementList("arg", Arg),
};

const Event = struct {
    name: xml.Attribute("name"),
    type: xml.OptionalAttribute("type"),
    since: xml.OptionalAttribute("since"),
    deprecated_since: xml.OptionalAttribute("deprecated-since"),
    description: xml.OptionalElement("description", Description),
    args: xml.ElementList("arg", Arg),
};

const Enum = struct {
    name: xml.Attribute("name"),
    since: xml.OptionalAttribute("since"),
    bitfield: xml.OptionalAttribute("bitfield"),
    description: xml.OptionalElement("description", Description),
    entries: xml.ElementList("entry", Entry),
};

const Entry = struct {
    name: xml.Attribute("name"),
    value: xml.Attribute("value"),
    summary: xml.OptionalAttribute("summary"),
    since: xml.OptionalAttribute("since"),
    deprecated_since: xml.OptionalAttribute("deprecated-since"),
    description: xml.OptionalElement("description", Description),
};

const Arg = struct {
    name: xml.Attribute("name"),
    type: xml.Attribute("type"),
    summary: xml.OptionalAttribute("summary"),
    interface: xml.OptionalAttribute("interface"),
    allow_null: xml.OptionalAttribute("allow-null"),
    @"enum": xml.OptionalAttribute("enum"),
    description: xml.OptionalElement("description", Description),
};

const Description = struct {
    summary: xml.Attribute("summary"),
    body: xml.String,
};

const Copyright = struct {
    body: xml.String,
};

fn printProtocol(protocol: Protocol, writer: *std.Io.Writer) !void {
    try writer.print("Protocol: {s}\n", .{protocol.name.value});
    for (protocol.interfaces.value.items) |ifce| {
        try writer.print("\tInterface: {s} (version {s})\n", .{ ifce.name.value, ifce.version.value });
        for (ifce.requests.value.items) |req| {
            try writer.print("\t\tRequest: {s}\n", .{req.name.value});
        }
        for (ifce.events.value.items) |ev| {
            try writer.print("\t\tEvent: {s}\n", .{ev.name.value});
        }
        for (ifce.enums.value.items) |en| {
            try writer.print("\t\tEnum: {s}\n", .{en.name.value});
        }
    }
    try writer.flush();
}

pub fn main() !void {
    const wayland_src = @embedFile("wayland.xml");
    const xdg_shell_src = @embedFile("xdg-shell.xml");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var buf = [_]u8{0} ** 4096;
    var stdout = std.fs.File.stdout().writer(&buf);
    const writer = &stdout.interface;

    var wayland = try xml.parse(xml.Document(Protocol), alloc, wayland_src);
    defer wayland.deinit(alloc);

    var xdg_shell = try xml.parse(xml.Document(Protocol), alloc, xdg_shell_src);
    defer xdg_shell.deinit(alloc);

    try printProtocol(wayland.value, writer);
    try printProtocol(xdg_shell.value, writer);
}
