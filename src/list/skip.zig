const std = @import("std");
const builtin = @import("builtin");

const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const math = std.math;

pub fn Skip(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        pub const Error = error{
            Frozen,
        };

        pub const Node = struct {
            next: []?*Element,
        };

        pub const Element = struct {
            node: *Node,
            key: K,
            value: V,
        };

        allocator: mem.Allocator,

        node: *Node,

        pub fn init(allocator: mem.Allocator) !Self {
            return try initWithLevel(allocator);
        }

        pub fn initWithLevel(allocator: mem.Allocator) !Self {
            return Self{
                .node = try newNode(allocator, 25),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.deleteNode(self.node);
            self.allocator.free(self.node.next);
            self.allocator.destroy(self.node);
        }

        fn deleteNode(self: *Self, node: *Node) void {
            for (node.next) |element| {
                if (element) |elem| {
                    self.deleteNode(elem.node);
                    self.allocator.destroy(elem);
                }
            }

            self.allocator.free(node.next);
            self.allocator.destroy(node);
        }

        fn newNode(allocator: mem.Allocator, level: usize) !*Node {
            var elements: []?*Element = try allocator.alloc(?*Element, level);
            for (0..level) |idx| {
                elements[idx] = null;
            }

            const node = try allocator.create(Node);
            node.next = elements;
            return node;
        }

        fn newElement(allocator: mem.Allocator, level: usize, key: K, value: V) !*Element {
            const element = try allocator.create(Element);
            element.node = try newNode(allocator, level);
            element.key = key;
            element.value = value;
            return element;
        }
    };
}
