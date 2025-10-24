const std = @import("std");
const xml = @import("xml");

const Document = struct {
    items: []Item,
};

const Item = xml.Element("item", struct {
    name: xml.Attribute,
    version: xml.Attribute,
    opt: ?Optional,
    elems: []Element,
});

const Optional = xml.Element("optional", struct {
    body: ?xml.String,
});

const Element = xml.Element("element", struct {
    index: xml.Attribute,
    ty: ?xml.NamedAttribute("type"),
    body: xml.String,
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const data = @embedFile("simple.xml");

    const result = try xml.parse(Document, alloc, data);
    defer result.deinit(alloc);

    std.debug.print("{s}\n", .{result.buffer});
}
