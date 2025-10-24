const std = @import("std");

const ItemType = enum {
    attribute,
    element,
};

pub const Attribute = struct {
    const item_type = ItemType.attribute;
    value: []const u8,
};

pub fn NamedAttribute(comptime name: []const u8) type {
    return struct {
        const item_type = ItemType.attribute;
        const attrib_name = name;
        value: []const u8,
    };
}

pub fn Element(comptime name: []const u8, comptime Body: type) type {
    return struct {
        const item_type = ItemType.element;
        const item_name = name;
        value: Body,
    };
}

pub const String = struct {
    data: []const u8,
};

pub fn parse(comptime T: type, data: []const u8) !T {
    _ = data;
    return .{};
}

const Parser = struct {
    // NOTE: skip namespaces, declarations, comments, maybe more
    const State = enum {
        start,
        tag_open, // <
        tag_close, // </
        tag_empty, // />
        attr_name, // ...
        attr_value_quote,
        attr_value, // ... or ...
        string, // >...<
        cdata, // <![CDATA[...]]>
        eof,
        invalid,
    };
    const Token = union(enum) {
        pub const Err = struct {
            pub const Reason = union(enum) {
                invalid_byte: u8,
                unexpected_eof: void,
            };
            line: usize,
            column: usize,
            reason: Reason,
        };
        elem_name: []const u8,
        attr_name: []const u8,
        attr_value: []const u8,
        content: []const u8,
        err: Err,

        pub fn invalidByte(line: usize, column: usize, byte: u8) Token {
            return .{ .err = .{
                .line = line,
                .column = column,
                .reason = .{ .invalid_byte = byte },
            } };
        }

        pub fn unexpectedEof(line: usize, column: usize) Token {
            return .{ .err = .{
                .line = line,
                .column = column,
                .reason = .unexpected_eof,
            } };
        }
    };
    buffer: []const u8,
    state: State,
    index: usize,
    line: usize,
    column: usize,

    pub fn init(buffer: []const u8) Parser {
        return .{
            .buffer = buffer,
            .state = .start,
            .index = 0,
            .line = 0,
            .column = 0,
        };
    }

    pub fn nextToken(self: *Parser) Token {
        var tok_start: usize = undefined;
        tok_start = 0;
        while (self.index < self.buffer.len) {
            const byte = self.buffer[self.index];
            switch (self.state) {
                .start => switch (byte) {
                    ' ', '\t', '\r', '\n' => {},
                    // '<' => self.state = .tag_open,
                    else => return .invalidByte(self.line, self.column, byte),
                },
            }
            self.advance();
        }
    }

    fn advance(self: *Parser) void {
        const byte = self.buffer[self.index];
        self.index += 1;
        if (byte == '\n') {
            self.line += 1;
            self.column = 0;
        } else {
            self.column = 0;
        }
    }

    fn invalidByte(self: *Parser, byte: u8) Token {
        return .{ .invalid = .{
            .line = self.line,
            .column = self.column,
            .reason = .{ .invalid_byte = byte },
        } };
    }

    fn unexpectedEof(self: *Parser) Token {
        return .{ .invalid = .{
            .line = self.line,
            .column = self.column,
            .reason = .unexpected_eof,
        } };
    }
};
