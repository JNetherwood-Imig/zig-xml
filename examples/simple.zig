const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;

const Document = struct {
    items: xml.ElementList("item", Item),
};

const Item = struct {
    name: xml.Attribute("name"),
    version: xml.Attribute("version"),
    optional: xml.OptionalElement("optional", struct { body: xml.String }),
    elems: xml.ElementList("element", Element),
};

const Optional = struct {
    body: xml.String,
};

const Element = struct {
    index: xml.Attribute("index"),
    ty: xml.OptionalAttribute("type"),
    body: xml.String,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const data = @embedFile("simple.xml");

    var doc = try xml.parse(xml.Document(Document), alloc, data);
    defer doc.deinit(alloc);

    for (doc.value.items.value.items) |item| {
        std.debug.print("Item (name: {s}, version: {s}):\n", .{ item.name.value, item.version.value });
        if (item.optional.value) |value| std.debug.print("\tOptional: {s}\n", .{value.body.data});
        for (item.elems.value.items) |elem| {
            std.debug.print("\tElement (index: {s}", .{elem.index.value});
            if (elem.ty.value) |value| std.debug.print(", type: {s}", .{value});
            std.debug.print("):\n", .{});
            std.debug.print("\t\t{s}\n", .{elem.body.data});
        }
    }
}
