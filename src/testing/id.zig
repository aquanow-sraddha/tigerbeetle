const std = @import("std");
const stdx = @import("../stdx.zig");

/// Permute indices (or other encoded data) into ids to:
///
/// * test different patterns of ids (e.g. random, ascending, descending), and
/// * allow the original index to recovered from the id, enabling less stateful testing.
///
pub const IdPermutation = union(enum) {
    /// Ascending indices become ascending ids.
    identity: void,

    /// Ascending indices become descending ids.
    inversion: void,

    /// Ascending indices alternate between ascending/descending (e.g. 1,100,3,98,…).
    zigzag: void,

    /// Ascending indices become pseudo-UUIDs.
    ///
    /// Sandwich the index "data" between random bits — this randomizes the id's prefix and suffix,
    /// but the index is easily recovered:
    ///
    /// * id_bits[_0.._32] = random
    /// * id_bits[32.._96] = data
    /// * id_bits[96..128] = random
    random: u64,

    pub fn encode(self: *const IdPermutation, data: usize) u128 {
        return switch (self.*) {
            .identity => data,
            .inversion => std.math.maxInt(u128) - @as(u128, data),
            .zigzag => {
                if (data % 2 == 0) {
                    return data;
                } else {
                    // -1 to stay odd.
                    return std.math.maxInt(u128) - @as(u128, data) -% 1;
                }
            },
            .random => |seed| {
                var prng = stdx.PRNG.from_seed(seed +% data);
                const random_mask = ~@as(u128, std.math.maxInt(u64) << 32);
                const random_bits = random_mask & prng.bytes(u128);
                return @as(u128, data) << 32 | random_bits;
            },
        };
    }

    pub fn decode(self: *const IdPermutation, id: u128) usize {
        return switch (self.*) {
            .identity => @intCast(id),
            .inversion => @intCast(std.math.maxInt(u128) - id),
            .zigzag => {
                if (id % 2 == 0) {
                    return @intCast(id);
                } else {
                    // -1 to stay odd.
                    return @intCast(std.math.maxInt(u128) - id -% 1);
                }
            },
            .random => @truncate(id >> 32),
        };
    }

    pub fn generate(prng: *stdx.PRNG) IdPermutation {
        return switch (prng.enum_uniform(std.meta.Tag(IdPermutation))) {
            .identity => .{ .identity = {} },
            .inversion => .{ .inversion = {} },
            .zigzag => .{ .zigzag = {} },
            .random => .{ .random = prng.bytes(u64) },
        };
    }
};

test "IdPermutation" {
    var prng = stdx.PRNG.from_seed(123);

    for ([_]IdPermutation{
        .{ .identity = {} },
        .{ .inversion = {} },
        .{ .zigzag = {} },
        .{ .random = prng.bytes(u64) },
    }) |permutation| {
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            const r = prng.bytes(usize);
            try test_id_permutation(permutation, r);
            try test_id_permutation(permutation, i);
            try test_id_permutation(permutation, std.math.maxInt(usize) - i);
        }
    }
}

fn test_id_permutation(permutation: IdPermutation, value: usize) !void {
    try std.testing.expectEqual(value, permutation.decode(permutation.encode(value)));
}
