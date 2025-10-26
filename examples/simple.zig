const std = @import("std");
const xml = @import("xml");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Document = struct {
    items: ArrayList(Item),

    pub fn deinit(self: *Document, alloc: Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(alloc);
        }
        self.items.deinit(alloc);
    }
};

const Item = xml.Element("item", struct {
    name: xml.Attribute("name"),
    version: xml.Attribute("version"),
    opt: ?Optional,
    elems: ArrayList(Element),
});

const Optional = xml.Element("optional", struct {
    body: ?xml.String,
});

const Element = xml.Element("element", struct {
    index: xml.Attribute("index"),
    ty: ?xml.Attribute("type"),
    body: xml.String,
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const data = @embedFile("simple.xml");

    var doc = try xml.parse(Document, alloc, data);
    defer doc.deinit(alloc);
    std.debug.print("{any}\n", .{doc});
}
