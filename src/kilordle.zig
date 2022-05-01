const std = @import("std");
const assets = @import("assets");
const builtin = @import("builtin");
const liu = @import("liu");

const wasm = liu.wasm;
pub usingnamespace wasm;

const ArrayList = std.ArrayList;

const ext = struct {
    extern fn setPuzzles(obj: wasm.Obj) void;
    extern fn setWordsLeft(count: usize) void;
};

const WordSubmission = struct {
    word: [5]u8,
};

const Wordle = struct {
    text: [5]u8,
    matches: [5]Match,
    letters_found: u8,
    places_found: u8,
};

pub const WasmCommand = WordSubmission;
const Letters = std.bit_set.IntegerBitSet(26);
const Puzzle = struct {
    solution: [5]u8,
    filled: [5]u8,
    submits: []u8,
};

const MatchKind = enum(u8) { none, letter, exact };
const Match = union(MatchKind) {
    none: void,
    exact: void,
    letter: u8,
};

var wordles_left: ArrayList(Wordle) = undefined;
var submissions: ArrayList([5]u8) = undefined;

fn setWordsLeft(count: usize) void {
    if (builtin.target.cpu.arch != .wasm32) return;

    ext.setWordsLeft(count);
}

fn setPuzzles(puzzles: []Puzzle) void {
    if (builtin.target.cpu.arch != .wasm32) return;

    const mark = wasm.watermarkObj();
    defer wasm.clearObjBufferForObjAndAfter(mark);

    const arr = wasm.makeArray();
    const solution_key = wasm.stringObj("solution");
    const filled_key = wasm.stringObj("filled");
    const submits_key = wasm.stringObj("submits");

    for (puzzles) |puzzle| {
        const obj = wasm.makeObj();

        const solution = wasm.stringObj(&puzzle.solution);
        const filled = wasm.stringObj(&puzzle.filled);
        const submits = wasm.stringObj(puzzle.submits);

        wasm.objSet(obj, solution_key, solution);
        wasm.objSet(obj, filled_key, filled);
        wasm.objSet(obj, submits_key, submits);

        wasm.arrayPush(arr, obj);
    }

    ext.setPuzzles(arr);
}

fn searchList(word: []const u8, dict: []const u8) bool {
    var word_index: u32 = 0;
    while (word_index < dict.len) : (word_index += 6) {
        const dict_slice = dict[word_index..(word_index + 5)];

        if (std.mem.eql(u8, word, dict_slice)) {
            return true;
        }
    }

    return false;
}

// Returns array of matches. Value v at index i is a match between wordle[i]
// and submission[v], or null if that match doesn't exist.
fn matchWordle(wordle: [5]u8, submission: [5]u8) [5]Match {
    var text = submission;
    var match = [_]Match{.none} ** 5;

    for (wordle) |c, idx| {
        if (submission[idx] == c) {
            match[idx] = .exact;
            text[idx] = 0;
        }
    }

    for (wordle) |c, idx| {
        if (match[idx] == .exact) {
            continue;
        }

        for (text) |*slot, text_idx| {
            if (slot.* == c) {
                match[idx] = .{ .letter = @truncate(u8, text_idx) };
                slot.* = 0;
            }
        }
    }

    return match;
}

pub export fn submitWord(l0: u8, l1: u8, l2: u8, l3: u8, l4: u8) bool {
    var _temp = liu.Temp.init();
    const temp = _temp.allocator();
    defer _temp.deinit();

    const word = [_]u8{ l0, l1, l2, l3, l4 };

    // lowercase
    for (word) |letter| {
        if (letter < 'a' or letter > 'z') {
            wasm.postFmt(.err, "invalid string {s}", .{word});
            return false;
        }
    }

    const is_wordle = searchList(&word, assets.wordles);
    if (!is_wordle and !searchList(&word, assets.wordle_words)) {
        wasm.postFmt(.err, "{s} doesn't exist", .{word});
        return false;
    }

    submissions.append(word) catch @panic("failed to save submission");

    var write_head: u32 = 0;
    var read_head: u32 = 0;
    var solved = ArrayList([5]u8).init(temp);

    const arena_len = wordles_left.items.len;
    while (read_head < arena_len) : (read_head += 1) {
        const wordle = &wordles_left.items[read_head];

        const new_matches = matchWordle(wordle.text, word);
        for (new_matches) |new_match, idx| {
            const old_match = wordle.matches[idx];
            if (@enumToInt(old_match) >= @enumToInt(new_match)) continue;

            wordle.matches[idx] = new_match;

            if (old_match == .none) wordle.letters_found += 1;
            if (new_match == .exact) wordle.places_found += 1;
        }

        // wordle is done, so we "delete" it by not writing it back to the buffer
        if (wordle.places_found >= 5) {
            solved.append(wordle.text) catch @panic("failed to append to arraylist");
            continue;
        }

        // write would be no-op
        if (read_head == write_head) {
            write_head += 1;
            continue;
        }

        wordles_left.items[write_head] = wordle.*;
        write_head += 1;
    }

    wordles_left.items.len = write_head;

    std.sort.insertionSort(Wordle, wordles_left.items, {}, compareWordles);

    const top_count = std.math.min(wordles_left.items.len, 32);
    var puzzles = ArrayList(Puzzle).init(temp);
    for (wordles_left.items[0..top_count]) |wordle| {
        var relevant_submits = ArrayList(u8).init(temp);
        var matches = [_]Match{.none} ** 5;

        // This gets displayed in the app; in debug mode, we output the lowercase
        // letter so we can see it in the UI to spot-check math. In release,
        // we don't do that, because tha'd be bad.
        var filled = if (builtin.mode == .Debug) wordle.text else [_]u8{' '} ** 5;

        var found: u32 = 0;
        for (wordle.matches) |match, idx| {
            if (match == .exact) {
                matches[idx] = .exact;
                filled[idx] = wordle.text[idx] - 'a' + 'A';
            }
        }

        for (submissions.items) |submit| {
            if (found >= 5) {
                break;
            }

            const found_before = found;
            var submit_letters = submit;
            const new_matches = matchWordle(wordle.text, submit);
            for (matches) |*slot, idx| {
                switch (slot.*) {
                    .exact => continue,
                    .letter => continue,
                    .none => {},
                }

                switch (new_matches[idx]) {
                    .none => continue,
                    .exact => unreachable,
                    .letter => |submit_idx| {
                        // Uppercase means the output text should be orange.
                        submit_letters[submit_idx] = submit[submit_idx] - 'a' + 'A';
                        slot.* = .{ .letter = submit_idx };
                        found += 1;
                    },
                }
            }

            if (found_before < found) {
                relevant_submits.appendSlice(&submit_letters) catch
                    @panic("failed to append submission");
                relevant_submits.append(',') catch
                    @panic("failed to append submission");
            }
        }

        if (relevant_submits.items.len > 0) {
            _ = relevant_submits.pop();
        }

        const err = puzzles.append(.{
            .solution = wordle.text,
            .filled = filled,
            .submits = relevant_submits.items,
        });
        err catch @panic("failed to add puzzle");
    }

    setPuzzles(puzzles.items);
    setWordsLeft(wordles_left.items.len);

    return true;
}

fn compareWordles(context: void, left: Wordle, right: Wordle) bool {
    _ = context;

    if (left.places_found != right.places_found) {
        return left.places_found > right.places_found;
    }

    if (left.letters_found != right.letters_found) {
        return left.letters_found > right.letters_found;
    }

    return false;
}

pub export fn init() void {
    wasm.initIfNecessary();

    wordles_left = ArrayList(Wordle).init(liu.Pages);
    submissions = ArrayList([5]u8).init(liu.Pages);

    const wordles = assets.wordles;

    const wordle_count = (wordles.len - 1) / 6 + 1;
    wordles_left.ensureUnusedCapacity(wordle_count) catch
        @panic("failed to allocate room for wordles");

    var word_index: u32 = 0;
    while ((word_index + 5) < wordles.len) : (word_index += 6) {
        var wordle = Wordle{
            .text = undefined,
            .matches = .{.none} ** 5,
            .letters_found = 0,
            .places_found = 0,
        };

        std.mem.copy(u8, &wordle.text, wordles[word_index..(word_index + 5)]);
        wordles_left.appendAssumeCapacity(wordle);
    }

    setWordsLeft(wordles_left.items.len);
    std.log.info("WASM initialized!", .{});
}
