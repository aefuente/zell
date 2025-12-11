const std = @import("std");
const Allocator = std.mem.Allocator;

const context = struct {};


pub fn filterAndSort(allocator: Allocator, query: []const u8, candidates: [][]const  u8, threshold: i32) ![][]const u8 {
    var tmp = try std.ArrayList(FuzzyMatch).initCapacity(allocator, 10);
    defer tmp.deinit(allocator);
    for (candidates)  |c| {
            const score = try FuzzyScore(allocator, query, c);
            if (score > threshold) {
                try tmp.append(allocator, FuzzyMatch{.text = c, .score = score});
            }
    }

    std.sort.heap(FuzzyMatch, tmp.items, context{}, cmp);
    var result = try allocator.alloc([]const u8, tmp.items.len);
    for (tmp.items, 0..) |c, idx| {
        result[idx] = c.text;
    }
    return result;
}

fn FuzzyScore(allocator: Allocator, query: []const u8, candidate: []const u8) ! i32 {
    const WEIGHT_MATCH_START: i32 = 1000;
    const WEIGHT_WORD_START: i32 = 15;
    const WEIGHT_CONSECUTIVE: i32 = 10;
    const PENALTY_GAP: i32 = -3;
    const PENALTY_LEADING: i32 = -5;

    var score: i32 = 0;
    var match_indices = try std.ArrayList(usize).initCapacity(allocator, 10);
    defer match_indices.deinit(allocator);

    var file_ptr: usize = 0;
    var query_ptr: usize = 0;
    
    var last_match_index: usize = std.math.maxInt(usize) - 1;


    while (query_ptr < query.len and file_ptr < candidate.len) {
        const q_char = query[query_ptr];
        var found_match = false;
        var best_match_index: usize = std.math.maxInt(usize) - 1;

        var idx = file_ptr;
        while (idx < candidate.len) : (idx += 1){
            const f_char = candidate[idx];

            if (q_char == f_char) {
                var current_match_score: i32 = 0;
                if (isWordStart(candidate, idx)) {
                    current_match_score += WEIGHT_WORD_START;
                }

                if (idx == 0) {
                    current_match_score += WEIGHT_MATCH_START;
                }

                if (idx == last_match_index + 1) {
                    current_match_score += WEIGHT_CONSECUTIVE;
                }

                var gap_legnth: usize = 0;
                if (last_match_index == std.math.maxInt(usize) - 1) {
                    gap_legnth = idx;
                }else {
                    gap_legnth = idx - last_match_index - 1;
                }
                current_match_score += (@as(i32, @intCast(gap_legnth)) * PENALTY_GAP);

                best_match_index = idx;
                score += current_match_score;
                try match_indices.append(allocator, idx);
                last_match_index = idx;
                file_ptr = idx + 1;
                query_ptr += 1;
                found_match = true;
                break;
            }
        }
        if (! found_match) {
            return 0;
        }
    }
    if (query_ptr == query.len) {
        if (match_indices.items.len > 0 and match_indices.items[0] != std.math.maxInt(usize)-1) {
            score += (@as(i32, @intCast(match_indices.items[0])) * PENALTY_LEADING);
        }
        return score;
    }
    return 0;
}


fn isWordStart(candidate: []const u8, position: usize) bool{ 
    if (position == 0) {
        return true;
    }
    const prev = candidate[position-1]; 
    if (prev == '/') return true;
    if (prev == '_') return true;
    if (prev == '-') return true;
    return false;
}


const FuzzyMatch = struct {
    text: []const u8,
    score: i32,
};


fn cmp(ctx: context, lhs: FuzzyMatch, rhs: FuzzyMatch) bool {
    _ = ctx;
    if (lhs.score >= rhs.score) {
        return true;
    }
    return false;
}

