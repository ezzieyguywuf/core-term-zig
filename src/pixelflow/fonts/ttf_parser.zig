const std = @import("std");
const mem = std.mem;

pub const Reader = struct {
    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data, .pos = 0 };
    }

    pub fn seek(self: *Reader, pos: usize) void {
        self.pos = pos;
    }

    pub fn skip(self: *Reader, n: usize) !void {
        if (self.pos + n > self.data.len) return error.EndOfStream;
        self.pos += n;
    }

    pub fn readU8(self: *Reader) !u8 {
        if (self.pos >= self.data.len) return error.EndOfStream;
        const v = self.data[self.pos];
        self.pos += 1;
        return v;
    }

    pub fn readI8(self: *Reader) !i8 {
        return @as(i8, @bitCast(try self.readU8()));
    }

    pub fn readU16(self: *Reader) !u16 {
        if (self.pos + 2 > self.data.len) return error.EndOfStream;
        const v = mem.readInt(u16, self.data[self.pos..][0..2], .big);
        self.pos += 2;
        return v;
    }

    pub fn readI16(self: *Reader) !i16 {
        return @as(i16, @bitCast(try self.readU16()));
    }

    pub fn readU32(self: *Reader) !u32 {
        if (self.pos + 4 > self.data.len) return error.EndOfStream;
        const v = mem.readInt(u32, self.data[self.pos..][0..4], .big);
        self.pos += 4;
        return v;
    }
};

pub const Font = struct {
    data: []const u8,
    glyf_offset: usize,
    loca_offset: usize,
    cmap_offset: usize,
    hmtx_offset: usize,
    num_hmetrics: usize,
    units_per_em: u16,
    ascent: i16,
    descent: i16,
    line_gap: i16,
    index_to_loc_format: i16, // 0 for short, 1 for long

    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Font {
        _ = allocator;
        var r = Reader.init(data);
        
        // Offset Table (12 bytes)
        _ = try r.readU32(); // scaler type
        const num_tables = try r.readU16();
        try r.skip(6); // searchRange, entrySelector, rangeShift

        var glyf: usize = 0;
        var loca: usize = 0;
        var cmap: usize = 0;
        var hmtx: usize = 0;
        var head: usize = 0;
        var hhea: usize = 0;

        // Table Directory
        for (0..num_tables) |_| {
            const tag = try r.readU32();
            _ = try r.readU32(); // checksum
            const offset = try r.readU32();
            _ = try r.readU32(); // length

            // Tags are u32 big endian.
            // 'head' = 0x68656164
            // 'glyf' = 0x676C7966
            // 'loca' = 0x6C6F6361
            // 'cmap' = 0x636D6170
            // 'hmtx' = 0x686D7478
            // 'hhea' = 0x68686561
            
            switch (tag) {
                0x68656164 => head = offset,
                0x676C7966 => glyf = offset,
                0x6C6F6361 => loca = offset,
                0x636D6170 => cmap = offset,
                0x686D7478 => hmtx = offset,
                0x68686561 => hhea = offset,
                else => {},
            }
        }

        if (head == 0 or glyf == 0 or loca == 0 or cmap == 0 or hhea == 0 or hmtx == 0) {
            return error.MissingTable;
        }

        // Parse 'head'
        r.seek(head + 18);
        const units_per_em = try r.readU16();
        r.seek(head + 50);
        const index_to_loc_format = try r.readI16();

        // Parse 'hhea'
        r.seek(hhea + 4);
        const ascent = try r.readI16();
        const descent = try r.readI16();
        const line_gap = try r.readI16();
        r.seek(hhea + 34);
        const num_hmetrics = try r.readU16();

        return Font{
            .data = data,
            .glyf_offset = glyf,
            .loca_offset = loca,
            .cmap_offset = cmap,
            .hmtx_offset = hmtx,
            .num_hmetrics = num_hmetrics,
            .units_per_em = units_per_em,
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .index_to_loc_format = index_to_loc_format,
        };
    }

    pub fn getGlyphOffset(self: *const Font, glyph_index: u16) !usize {
        var r = Reader.init(self.data);
        if (self.index_to_loc_format == 0) {
            r.seek(self.loca_offset + @as(usize, glyph_index) * 2);
            const offset = try r.readU16();
            return @as(usize, offset) * 2;
        } else {
            r.seek(self.loca_offset + @as(usize, glyph_index) * 4);
            return try r.readU32();
        }
    }

    pub fn getGlyphLen(self: *const Font, glyph_index: u16) !usize {
        const start = try self.getGlyphOffset(glyph_index);
        const end = try self.getGlyphOffset(glyph_index + 1);
        return end - start;
    }

    pub fn getCmap(self: *const Font, codepoint: u32) !u16 {
        var r = Reader.init(self.data);
        r.seek(self.cmap_offset + 2);
        const num_subtables = try r.readU16();
        
        var subtable_offset: usize = 0;
        
        // Find platform 3 (Windows) / encoding 1 (Unicode BMP) or 10 (Full)
        // Or platform 0 (Unicode)
        
        for (0..num_subtables) |_| {
            const platform_id = try r.readU16();
            const encoding_id = try r.readU16();
            const offset = try r.readU32();
            
            if ((platform_id == 3 and (encoding_id == 1 or encoding_id == 10)) or 
                (platform_id == 0)) {
                subtable_offset = self.cmap_offset + offset;
                break; // Use first matching
            }
        }

        if (subtable_offset == 0) return 0;

        r.seek(subtable_offset);
        const format = try r.readU16();

        if (format == 4) {
            // Format 4: Segment mapping to delta values
            _ = try r.readU16(); // length
            _ = try r.readU16(); // language
            const seg_count_x2 = try r.readU16();
            const seg_count = seg_count_x2 / 2;
            _ = try r.readU16(); // searchRange
            _ = try r.readU16(); // entrySelector
            _ = try r.readU16(); // rangeShift

            const end_counts_offset = r.pos;
            const start_counts_offset = end_counts_offset + (seg_count * 2) + 2; // +2 for padding
            const id_deltas_offset = start_counts_offset + (seg_count * 2);
            const id_range_offsets_offset = id_deltas_offset + (seg_count * 2);

            // Find segment
            for (0..seg_count) |i| {
                r.seek(end_counts_offset + i * 2);
                const end_code = try r.readU16();
                if (codepoint <= end_code) {
                    r.seek(start_counts_offset + i * 2);
                    const start_code = try r.readU16();
                    if (codepoint >= start_code) {
                        r.seek(id_deltas_offset + i * 2);
                        const id_delta = try r.readI16();
                        r.seek(id_range_offsets_offset + i * 2);
                        const id_range_offset = try r.readU16();

                        if (id_range_offset == 0) {
                            return @as(u16, @intCast(@as(i32, @intCast(codepoint)) + id_delta));
                        } else {
                            // obscure pointer math
                            const offset_addr = id_range_offsets_offset + i * 2;
                            const glyph_index_addr = offset_addr + id_range_offset + (codepoint - start_code) * 2;
                            r.seek(glyph_index_addr);
                            const glyph_index = try r.readU16();
                            if (glyph_index == 0) return 0;
                            return @as(u16, @intCast(@as(i32, @intCast(glyph_index)) + id_delta));
                        }
                    } else {
                        return 0; // Not in this segment
                    }
                }
            }
        }
        // TODO: Handle Format 12 for non-BMP
        return 0;
    }
};
