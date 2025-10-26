//! This parser is an updated version of https://github.com/andrewrk/xml
//! XML tokenizer. Takes the entire input buffer as the input; provides a
//! streaming, non-allocating API to pull tokens one at a time.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const Parser = @This();

bytes: []const u8,
index: usize = 0,
line: usize = 0,
column: usize = 0,
state: State = .start,
/// This field is populated when `next` returns a `Token` with `Token.Tag.invalid`.
error_note: ErrorNote = undefined,

pub const Token = struct {
    tag: Tag,
    bytes: []const u8,

    pub const Tag = enum {
        /// Error tokenizing the XML. Details can be found at the line, column,
        /// and error_note field.
        invalid,
        /// Example: "xml".
        /// Possible next tags:
        /// * `attr_key`
        /// * `attr_value`
        /// * `tag_open`
        doctype,
        /// Example: "<head>"
        /// Possible next tags:
        /// * `attr_key`
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        tag_open,
        /// Example: "</head>"
        /// Possible next tags:
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        tag_close,
        /// Emitted for empty nodes such as "<head/>".
        /// `bytes` will contain the "/".
        /// Possible next tags:
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        tag_close_empty,
        /// Only the name of the key, does not include the '=' or the value.
        /// Possible next tags:
        /// * `attr_value`
        attr_key,
        /// Exactly the bytes of the string, including the quotes. Does no decoding.
        /// Possible next tags:
        /// * `attr_key`
        /// * `tag_open`
        /// * `tag_close`
        /// * `content`
        attr_value,
        /// The data between tags. Exactly the bytes, does no decoding.
        /// Possible next tags:
        /// * `tag_open`
        /// * `tag_close`
        content,
        /// End of file was reached.
        eof,
    };
};

pub const ErrorNote = enum {
    invalid_byte,
};

pub fn next(self: *Parser) Token {
    var tok_start: usize = undefined;
    while (self.index < self.bytes.len) {
        const byte = self.bytes[self.index];
        switch (self.state) {
            .start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => self.state = .doctype_q,
                else => return self.fail(.invalid_byte),
            },
            .doctype_q => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '?' => self.state = .doctype_name_start,
                else => return self.fail(.invalid_byte),
            },
            .doctype_name_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>', '<' => return self.fail(.invalid_byte),
                else => {
                    tok_start = self.index;
                    self.state = .doctype_name;
                },
            },
            .doctype_name => switch (byte) {
                ' ', '\t', '\r', '\n' => return self.emit(.doctype, .{
                    .tag = .doctype,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '?' => return self.emit(.doctype_end, .{
                    .tag = .doctype,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '>', '<' => return self.fail(.invalid_byte),
                else => {},
            },
            .doctype => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '?' => self.state = .doctype_end,
                '<', '>' => return self.fail(.invalid_byte),
                else => {
                    tok_start = self.index;
                    self.state = .doctype_attr_key;
                },
            },
            .doctype_attr_key => switch (byte) {
                '=' => return self.emit(.doctype_attr_value_q, .{
                    .tag = .attr_key,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '?', '<', '>' => return self.fail(.invalid_byte),
                else => {},
            },
            .doctype_attr_value_q => switch (byte) {
                '"' => {
                    self.state = .doctype_attr_value;
                    tok_start = self.index;
                },
                else => return self.fail(.invalid_byte),
            },
            .doctype_attr_value => switch (byte) {
                '"' => return self.emit(.doctype, .{
                    .tag = .attr_value,
                    .bytes = self.bytes[tok_start .. self.index + 1],
                }),
                '\n' => return self.fail(.invalid_byte),
                else => {},
            },
            .doctype_end => switch (byte) {
                '>' => self.state = .body,
                else => return self.fail(.invalid_byte),
            },
            .body => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => self.state = .tag_name_start,
                else => {
                    self.state = .content;
                    tok_start = self.index;
                },
            },
            .content => switch (byte) {
                '<' => return self.emit(.tag_name_start, .{
                    .tag = .content,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                else => {},
            },
            .tag_name_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '!' => self.state = .comment_start,
                '>', '<' => return self.fail(.invalid_byte),
                '/' => self.state = .tag_close_start,
                else => {
                    tok_start = self.index;
                    self.state = .tag_name;
                },
            },
            .tag_close_start => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>', '<' => return self.fail(.invalid_byte),
                else => {
                    tok_start = self.index;
                    self.state = .tag_close_name;
                },
            },
            .tag_close_name => switch (byte) {
                ' ', '\t', '\r', '\n' => return self.emit(.tag_close_b, .{
                    .tag = .tag_open,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '>' => return self.emit(.body, .{
                    .tag = .tag_close,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '<' => return self.fail(.invalid_byte),
                else => {},
            },
            .tag_close_b => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '>' => self.state = .body,
                else => return self.fail(.invalid_byte),
            },
            .tag_name => switch (byte) {
                ' ', '\t', '\r', '\n' => return self.emit(.tag, .{
                    .tag = .tag_open,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '>' => return self.emit(.body, .{
                    .tag = .tag_open,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '<' => return self.fail(.invalid_byte),
                else => {},
            },
            .tag => switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                '<' => return self.fail(.invalid_byte),
                '>' => self.state = .body,
                '/' => {
                    tok_start = self.index;
                    self.state = .tag_end_empty;
                },
                else => {
                    tok_start = self.index;
                    self.state = .tag_attr_key;
                },
            },
            .tag_end_empty => switch (byte) {
                '>' => return self.emit(.body, .{
                    .tag = .tag_close_empty,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                else => return self.fail(.invalid_byte),
            },
            .tag_attr_key => switch (byte) {
                '=' => return self.emit(.tag_attr_value_q, .{
                    .tag = .attr_key,
                    .bytes = self.bytes[tok_start..self.index],
                }),
                '<', '>' => return self.fail(.invalid_byte),
                else => {},
            },
            .tag_attr_value_q => switch (byte) {
                '"' => {
                    self.state = .tag_attr_value;
                    tok_start = self.index;
                },
                else => return self.fail(.invalid_byte),
            },
            .tag_attr_value => switch (byte) {
                '"' => return self.emit(.tag, .{
                    .tag = .attr_value,
                    .bytes = self.bytes[tok_start .. self.index + 1],
                }),
                '\n' => return self.fail(.invalid_byte),
                else => {},
            },
            .comment_start => switch (byte) {
                '-' => self.state = .comment_body,
                else => return self.fail(.invalid_byte),
            },
            .comment_body => switch (byte) {
                '-' => self.state = .comment_end_maybe,
                else => {},
            },
            .comment_end_maybe => switch (byte) {
                '-' => {},
                '>' => self.state = .body,
                else => self.state = .comment_body,
            },
        }
        self.advanceCursor();
    }
    return .{
        .tag = .eof,
        .bytes = self.bytes[self.bytes.len..],
    };
}

const State = enum {
    start,
    doctype_q,
    doctype_name,
    doctype_name_start,
    doctype,
    doctype_attr_key,
    doctype_attr_value_q,
    doctype_attr_value,
    doctype_end,
    body,
    content,
    tag_name_start,
    tag_name,
    tag,
    tag_attr_key,
    tag_attr_value_q,
    tag_attr_value,
    tag_close_start,
    tag_close_name,
    tag_close_b,
    tag_end_empty,
    comment_start,
    comment_body,
    comment_end_maybe,
};

fn fail(self: *Parser, note: ErrorNote) Token {
    self.error_note = note;
    return .{ .tag = .invalid, .bytes = self.bytes[self.index..][0..0] };
}

fn emit(self: *Parser, next_state: State, token: Token) Token {
    self.state = next_state;
    self.advanceCursor();
    return token;
}

fn advanceCursor(self: *Parser) void {
    const byte = self.bytes[self.index];
    self.index += 1;

    if (byte == '\n') {
        self.line += 1;
        self.column = 0;
    } else {
        self.column += 1;
    }
}

test "hello world xml" {
    const bytes =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<map></map>
    ;
    var xml: Parser = .{ .bytes = bytes };
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .attr_key, "version");
    try testExpect(&xml, .attr_value, "\"1.0\"");
    try testExpect(&xml, .attr_key, "encoding");
    try testExpect(&xml, .attr_value, "\"UTF-8\"");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
    try testExpect(&xml, .eof, "");
}

test "some props" {
    const bytes =
        \\<?xml?>
        \\<map>
        \\ <properties>
        \\  <property name="gravity" type="float" value="12.34"/>
        \\  <property name="never gonna give you up" type="bool" value="true"/>
        \\  <property name="never gonna let you down" type="bool" value="true"/>
        \\ </properties>
        \\</map>
    ;
    var xml: Parser = .{ .bytes = bytes };
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .tag_open, "map");
    try testExpect(&xml, .tag_open, "properties");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"gravity\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"float\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"12.34\"");
    try testExpect(&xml, .tag_close_empty, "/");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"never gonna give you up\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .tag_close_empty, "/");

    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"never gonna let you down\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .tag_close_empty, "/");

    try testExpect(&xml, .tag_close, "properties");
    try testExpect(&xml, .tag_close, "map");
    try testExpect(&xml, .eof, "");
}

test "comments" {
    const bytes =
        \\<?xml?>
        \\ <!-- This is a multi-
        \\       line comment, Rick -->
        \\ <property name="rolled" type="bool" value="true"/>
    ;
    var xml: Parser = .{ .bytes = bytes };
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .tag_open, "property");
    try testExpect(&xml, .attr_key, "name");
    try testExpect(&xml, .attr_value, "\"rolled\"");
    try testExpect(&xml, .attr_key, "type");
    try testExpect(&xml, .attr_value, "\"bool\"");
    try testExpect(&xml, .attr_key, "value");
    try testExpect(&xml, .attr_value, "\"true\"");
    try testExpect(&xml, .tag_close_empty, "/");
}

test "eof mid-comment" {
    const bytes =
        \\<?xml?>
        \\ <!
    ;
    var xml: Parser = .{ .bytes = bytes };
    try testExpect(&xml, .doctype, "xml");
    try testExpect(&xml, .eof, "");
}

fn testExpect(xml: *Parser, tag: Token.Tag, bytes: []const u8) !void {
    const tok = xml.next();
    try testing.expectEqual(tag, tok.tag);
    try testing.expectEqualStrings(bytes, tok.bytes);
}
