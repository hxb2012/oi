const target = @import("builtin").target;
const std = @import("std");
const meta = std.meta;
const math = std.math;
const assert = std.debug.assert;
const max_format_args = @typeInfo(std.fmt.ArgSetType).Int.bits;
const ArgState = std.fmt.ArgState;
const Placeholder = std.fmt.Placeholder;
const defaultSpec = std.fmt.defaultSpec;
const comptimePrint = std.fmt.comptimePrint;
const Alignment = std.fmt.Alignment;

extern "c" fn snprintf(str: [*]u8, size: usize, format: [*:0]const u8, ...) c_int;

const ANY = "any";

const NumberTag = enum {
    literal,
    arg,
};

const Number = union(NumberTag) {
    literal: usize,
    arg: usize,
};

const FormatOptions = struct {
    specifier_arg: [:0]const u8,
    arg: ?usize = null,
    precision: ?Number = null,
    width: ?Number = null,
    alignment: Alignment = .right,
    fill: u8 = ' ',
};

const ArgSpecTag = enum {
    Int,
    Ascii,
    Len,
    Buf,
    Str,
    Float,
};

const ArgSpec = union(ArgSpecTag) {
    Int: std.builtin.Type.Int,
    Ascii: void,
    Len: void,
    Buf: void,
    Str: void,
    Float: void,
};

const Arg = struct {
    pos: usize,
    spec: ArgSpec,
};

const PrintSpec = struct {
    fmt: [:0]const u8,
    args: []const Arg,
};

fn parseFmt(comptime fmt: [:0]const u8, comptime ArgsType: type) []const FormatOptions {
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.Struct.fields;
    if (fields_info.len > max_format_args) {
        @compileError("32 arguments max are supported per format call");
    }

    comptime var arg_state: ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    comptime var spec: []const FormatOptions = &[0]FormatOptions{};

    inline while (i < fmt.len) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        // Write out the literal
        if (start_index != end_index) {
            spec = spec ++ .{.{ .specifier_arg = fmt[start_index..end_index] ++ "" }};
        }

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        comptime assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        comptime assert(fmt[i] == '}');
        i += 1;

        const placeholder = comptime Placeholder.parse(fmt[fmt_begin..fmt_end].*);

        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| meta.fieldIndex(ArgsType, arg_name) orelse
                @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width: ?Number = comptime switch (placeholder.width) {
            .none => null,
            .number => |v| .{ .literal = v },
            .named => |arg_name| blk: {
                const arg_i = meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk .{ .arg = arg_i };
            },
        };

        const precision: ?Number = comptime switch (placeholder.precision) {
            .none => null,
            .number => |v| .{ .literal = v },
            .named => |arg_name| blk: {
                const arg_i = meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk .{ .arg = arg_i };
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse
            @compileError("too few arguments");

        spec = spec ++ .{.{
            .specifier_arg = placeholder.specifier_arg ++ "",
            .arg = arg_to_print,
            .fill = placeholder.fill,
            .alignment = placeholder.alignment,
            .width = width,
            .precision = precision,
        }};
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("unused argument in '" ++ fmt ++ "'"),
            else => @compileError(comptimePrint("{d}", .{missing_count}) ++ " unused arguments in '" ++ fmt ++ "'"),
        }
    }

    return spec;
}

fn printSpec(comptime fmt: [:0]const u8, comptime ArgsType: type) PrintSpec {
    const options_slice = parseFmt(fmt, ArgsType);

    const fields_info = @typeInfo(ArgsType).Struct.fields;

    comptime var c_fmt: [:0]const u8 = "";
    comptime var args_spec: []const Arg = &[0]Arg{};

    inline for (options_slice) |options| {
        if (options.arg) |arg| {
            const spec = printSpecType(fields_info[arg], options);
            c_fmt = c_fmt ++ spec.fmt;
            args_spec = args_spec ++ spec.args;
        } else {
            c_fmt = c_fmt ++ options.specifier_arg;
        }
    }

    return .{ .fmt = c_fmt, .args = args_spec };
}

fn invalidFmtError(comptime fmt: []const u8, comptime T: type) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(T) ++ "'");
}

fn printSpecType(comptime field: std.builtin.Type.StructField, comptime options: FormatOptions) PrintSpec {
    const T = field.type;
    const fmt = options.specifier_arg;
    const actual_fmt = if (std.mem.eql(u8, fmt, ANY))
        defaultSpec(T)
    else if (fmt.len != 0 and (fmt[0] == '?' or fmt[0] == '!')) switch (@typeInfo(T)) {
        .Optional, .ErrorUnion => fmt,
        else => stripOptionalOrErrorUnionSpec(fmt),
    } else fmt;

    if (options.alignment == .center) {
        @compileError("align center not supported");
    }

    switch (@typeInfo(T)) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float => {
            return printSpecValue(field, actual_fmt, options);
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => |info| {
                    if (info.child == u8) {
                        if (actual_fmt.len == 0)
                            @compileError("cannot format array ref without a specifier (i.e. {s} or {*})");
                        switch (actual_fmt[0]) {
                            's' => {
                                if (meta.sentinel(ptr_info.child)) |sentinel| {
                                    if (sentinel == 0)
                                        return printSpecString(options);
                                }
                                return printSpecBuf(options);
                            },
                            else => invalidFmtError(fmt, T),
                        }
                    }
                },
                else => {},
            },
            .Many => {
                if (meta.sentinel(T)) |sentinel| {
                    if (sentinel == 0) {
                        if (ptr_info.child == u8) {
                            if (actual_fmt.len == 0)
                                @compileError("cannot format pointer without a specifier (i.e. {s} or {*})");
                            switch (actual_fmt[0]) {
                                's' => {
                                    return printSpecString(options);
                                },
                                else => {},
                            }
                        }
                    }
                }
            },
            .Slice => {
                if (actual_fmt.len == 0)
                    @compileError("cannot format slice without a specifier (i.e. {s} or {any})");
                if (ptr_info.child == u8) {
                    switch (actual_fmt[0]) {
                        's' => {
                            if (meta.sentinel(T)) |sentinel| {
                                if (sentinel == 0)
                                    return printSpecString(options);
                            }
                            return printSpecBuf(options);
                        },
                        else => {},
                    }
                }
                invalidFmtError(fmt, T);
            },
            else => {
                invalidFmtError(fmt, T);
            },
        },
        .Array => |info| {
            if (info.child == u8) {
                if (actual_fmt.len == 0)
                    @compileError("cannot format array without a specifier (i.e. {s} or {any})");
                switch (actual_fmt[0]) {
                    's' => {
                        if (meta.sentinel(T)) |sentinel| {
                            if (sentinel == 0)
                                return printSpecString(options);
                        }
                        return printSpecBuf(options);
                    },
                    else => invalidFmtError(fmt, T),
                }
            }
        },
        else => {},
    }

    @compileError("unable to format type '" ++ @typeName(T) ++ "'");
}

fn printSpecValue(comptime field: std.builtin.Type.StructField, comptime fmt: [:0]const u8, comptime options: FormatOptions) PrintSpec {
    const T = field.type;
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => return printSpecFloatValue(field.type, fmt, options),
        .Int, .ComptimeInt => return printSpecIntValue(field, fmt, options),
        else => comptime unreachable,
    }
}

fn stripOptionalOrErrorUnionSpec(comptime fmt: [:0]const u8) []const u8 {
    return if (std.mem.eql(u8, fmt[1..], ANY))
        ANY
    else
        fmt[1..];
}

fn printSpecIntValue(comptime field: std.builtin.Type.StructField, comptime fmt: [:0]const u8, comptime options: FormatOptions) PrintSpec {
    comptime var base = 10;
    comptime var uppercase: bool = false;

    const Int = if (field.type == comptime_int) blk: {
        if (field.default_value) |default_value| {
            const value = @as(*const comptime_int, @ptrCast(default_value)).*;
            break :blk math.IntFittingRange(value, value);
        } else comptime unreachable;
    } else field.type;

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
        base = 10;
    } else if (comptime std.mem.eql(u8, fmt, "c")) {
        if (@typeInfo(Int).Int.bits <= 8) {
            return printSpecAsciiChar(options);
        } else {
            @compileError("cannot print integer that is larger than 8 bits as an ASCII character");
        }
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        base = 16;
    } else if (comptime std.mem.eql(u8, fmt, "X")) {
        base = 16;
        uppercase = true;
    } else if (comptime std.mem.eql(u8, fmt, "o")) {
        base = 8;
    } else {
        invalidFmtError(fmt, Int);
    }

    return printSpecInt(@typeInfo(Int).Int, base, uppercase, options);
}

fn printSpecFloatValue(comptime T: type, comptime fmt: []const u8, comptime options: FormatOptions) PrintSpec {
    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "e")) {
        return printSpecFloat("e", options);
    } else if (comptime std.mem.eql(u8, fmt, "d")) {
        return printSpecFloat("f", options);
    } else {
        invalidFmtError(fmt, T);
    }
}

fn printSpecFloat(comptime format: [:0]const u8, comptime options: FormatOptions) PrintSpec {
    if (options.fill != ' ') {
        @compileError("float fill character not supported");
    }

    const spec = comptime printSpecCommon(options);
    comptime var fmt: [:0]const u8 = spec.fmt;
    comptime var args: []const Arg = spec.args;

    if (options.precision) |precision| {
        switch (precision) {
            .literal => |literal| {
                fmt = fmt ++ comptimePrint(".{}", .{literal});
            },
            .arg => |arg| {
                fmt = fmt ++ ".*";
                args = args ++ .{.{ .pos = arg, .spec = .{ .Int = std.builtin.Type.Int{ .bits = target.c_type_bit_size(.int), .signedness = .signed } } }};
            },
        }
    }

    fmt = fmt ++ format;

    if (options.arg) |arg| {
        args = args ++ .{.{ .pos = arg, .spec = .{ .Float = void{} } }};
    } else comptime unreachable;

    return .{ .fmt = fmt, .args = args };
}

fn printSpecAsciiChar(comptime options: FormatOptions) PrintSpec {
    if (options.precision) |_| {
        @compileError("ascii char precision not supported");
    }

    if (options.fill != ' ') {
        @compileError("ascii char fill character not supported");
    }

    const spec = comptime printSpecCommon(options);
    comptime var fmt: [:0]const u8 = spec.fmt;
    comptime var args: []const Arg = spec.args;
    fmt = fmt ++ "c";

    if (options.arg) |arg| {
        args = args ++ .{.{ .pos = arg, .spec = .{ .Ascii = void{} } }};
    } else comptime unreachable;

    return .{ .fmt = fmt, .args = args };
}

fn printSpecIntLength(comptime bits: u16) struct { bits: u16, fmt: [:0]const u8 } {
    inline for ([_]std.Target.CType{ .char, .short, .int, .long, .longlong }, [_][:0]const u8{ "hh", "h", "", "l", "ll" }) |c_type, format| {
        if (bits <= target.c_type_bit_size(c_type))
            return .{ .bits = target.c_type_bit_size(c_type), .fmt = format };
    }
    @compileError(comptimePrint("integer with {} bits not supported", .{bits}));
}

fn printSpecIntConversion(comptime signed: bool, comptime base: u8, comptime uppercase: bool) [:0]const u8 {
    if (signed) {
        if (base != 10) {
            @compileError("conversion from signed integer not supported");
        }
        return "d";
    }

    switch (base) {
        8 => {
            return "o";
        },
        10 => {
            return "u";
        },
        16 => {
            return if (uppercase) return "X" else "x";
        },
        else => comptime unreachable,
    }
}

fn printSpecInt(comptime Int: std.builtin.Type.Int, comptime base: u8, comptime uppercase: bool, comptime options: FormatOptions) PrintSpec {
    if (options.precision) |_| {
        @compileError("integer precision not supported");
    }

    const spec = comptime printSpecCommon(options);
    comptime var fmt: [:0]const u8 = spec.fmt;
    comptime var args: []const Arg = spec.args;

    const length = comptime printSpecIntLength(Int.bits);
    fmt = fmt ++ length.fmt ++ comptime printSpecIntConversion(Int.signedness == .signed, base, uppercase);

    if (options.arg) |arg| {
        args = args ++ .{.{ .pos = arg, .spec = .{ .Int = std.builtin.Type.Int{ .bits = length.bits, .signedness = Int.signedness } } }};
    } else comptime unreachable;

    return .{ .fmt = fmt, .args = args };
}

fn printSpecString(comptime options: FormatOptions) PrintSpec {
    if (options.precision) |_| {
        @compileError("buf precision not supported");
    }

    if (options.fill != ' ') {
        @compileError("buf fill character not supported");
    }

    const spec = comptime printSpecCommon(options);
    comptime var fmt: [:0]const u8 = spec.fmt;
    comptime var args: []const Arg = spec.args;
    fmt = fmt ++ "s";

    if (options.arg) |arg| {
        args = args ++ .{.{ .pos = arg, .spec = .{ .Str = void{} } }};
    } else comptime unreachable;

    return .{ .fmt = fmt, .args = args };
}

fn printSpecBuf(comptime options: FormatOptions) PrintSpec {
    if (options.precision) |_| {
        @compileError("buf precision not supported");
    }

    if (options.fill != ' ') {
        @compileError("buf fill character not supported");
    }

    const spec = comptime printSpecCommon(options);
    comptime var fmt: [:0]const u8 = spec.fmt;
    comptime var args: []const Arg = spec.args;
    fmt = fmt ++ ".*s";

    if (options.arg) |arg| {
        args = args ++ .{ .{ .pos = arg, .spec = .{ .Len = void{} } }, .{ .pos = arg, .spec = .{ .Buf = void{} } } };
    } else comptime unreachable;

    return .{ .fmt = fmt, .args = args };
}

fn printSpecCommon(comptime options: FormatOptions) PrintSpec {
    comptime var fmt: [:0]const u8 = "%";
    comptime var args: []const Arg = &[0]Arg{};

    if (options.fill == '0') {
        if (options.alignment == .left) {
            @compileError("zero padding conflicts with align left");
        }
        fmt = fmt ++ "0";
    } else {
        if (options.fill != ' ') {
            @compileError("fill character not supported");
        }
    }

    if (options.alignment == .left) {
        fmt = fmt ++ "-";
    }

    if (options.width) |width| {
        switch (width) {
            .literal => |literal| {
                fmt = fmt ++ comptimePrint("{}", .{literal});
            },
            .arg => |arg| {
                fmt = fmt ++ "*";
                args = args ++ .{.{ .pos = arg, .spec = .{ .Int = std.builtin.Type.Int{ .bits = target.c_type_bit_size(.int), .signedness = .signed } } }};
            },
        }
    }

    return .{ .fmt = fmt, .args = args };
}

fn printSpecArgType(comptime spec: ArgSpec) type {
    switch (spec) {
        .Int => |Int| {
            return @Type(std.builtin.Type{ .Int = Int });
        },
        .Ascii => {
            return u8;
        },
        .Len => {
            return c_int;
        },
        .Buf => {
            return [*]const u8;
        },
        .Str => {
            return [*:0]const u8;
        },
        .Float => {
            return f64;
        },
    }
}

fn printSpecArgField(comptime spec: ArgSpec, comptime name: []const u8, comptime field: std.builtin.Type.StructField) std.builtin.Type.StructField {
    const T = printSpecArgType(spec);
    return .{
        .name = name,
        .type = T,
        .default_value = if (field.default_value) |default_value| @as(*const anyopaque, @ptrCast(&printSpecArgValue(spec, @as(*const field.type, @alignCast(@ptrCast(default_value))).*))) else null,
        .is_comptime = field.is_comptime,
        .alignment = @alignOf(T),
    };
}

inline fn printSpecArgValue(comptime spec: ArgSpec, value: anytype) printSpecArgType(spec) {
    if (spec == .Float)
        return @as(f64, value);
    const T = @TypeOf(value);
    if (T == comptime_int)
        return value;
    switch (spec) {
        .Len => return @intCast(value.len),
        .Buf => return switch (@typeInfo(T)) {
            .Array => {
                return &value;
            },
            .Pointer => value.ptr,
            else => comptime unreachable,
        },
        .Str => return switch (@typeInfo(T)) {
            .Array => &value,
            else => value,
        },
        else => return value,
    }
}

fn printSpecTupleType(comptime args: []const Arg, comptime ArgsType: type) type {
    comptime var fields: []const std.builtin.Type.StructField = &.{};
    for (args, 0..) |arg, i| {
        const field = @typeInfo(ArgsType).Struct.fields[arg.pos];
        fields = fields ++ .{printSpecArgField(arg.spec, comptimePrint("{d}", .{i}), field)};
    }

    return @Type(std.builtin.Type{ .Struct = .{
        .layout = .Auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = true,
    } });
}

inline fn printSpecTuple(comptime spec: []const Arg, args: anytype) printSpecTupleType(spec, @TypeOf(args)) {
    const fields = @typeInfo(@TypeOf(args)).Struct.fields;
    const T = printSpecTupleType(spec, @TypeOf(args));
    var tuple: T = undefined;
    inline for (spec, @typeInfo(T).Struct.fields, 0..) |arg, field, i| {
        if (!field.is_comptime)
            @field(tuple, comptimePrint("{d}", .{i})) = printSpecArgValue(arg.spec, @field(args, fields[arg.pos].name));
    }
    return tuple;
}

pub fn sprintf(str: []u8, comptime fmt: [:0]const u8, args: anytype) c_int {
    const spec = comptime printSpec(fmt, @TypeOf(args));
    return @call(.auto, snprintf, .{ str.ptr, str.len, spec.fmt } ++ printSpecTuple(spec.args, args));
}

pub fn printf(comptime fmt: [:0]const u8, args: anytype) void {
    const spec = comptime printSpec(fmt, @TypeOf(args));
    _ = @call(.auto, std.c.printf, .{spec.fmt} ++ printSpecTuple(spec.args, args));
}

fn expectFmt(comptime expected: []const u8, comptime template: [:0]const u8, args: anytype) !void {
    var a: [128]u8 = undefined;
    const len = sprintf(&a, template, args);
    if (len >= a.len) {
        return error.Overflow;
    }

    var result = a[0..@intCast(len) :0];

    if (std.mem.eql(u8, result, expected)) return;

    std.debug.print("\n====== expected this output: =========\n", .{});
    std.debug.print("{s}", .{expected});
    std.debug.print("\n======== instead found this: =========\n", .{});
    std.debug.print("{s}", .{result});
    std.debug.print("\n======================================\n", .{});
    return error.TestExpectedFmt;
}

test {
    try expectFmt("10", "{}", .{0xA});
    try expectFmt(" 10", "{:3}", .{0xA});
    try expectFmt("10 ", "{:<3}", .{0xA});
    try expectFmt("010", "{:0>3}", .{0xA});
    try expectFmt("b", "{x}", .{0xB});
    try expectFmt("B", "{X}", .{0xB});
    try expectFmt("11", "{d}", .{0xB});
    try expectFmt("13", "{o}", .{0xB});
    try expectFmt("A", "{c}", .{'A'});

    try expectFmt("1.50", "{d:.2}", .{1.5});

    var buf: []const u8 = "A";
    try expectFmt("A", "{s}", .{buf});
    try expectFmt("    A", "{s:5}", .{buf});
    try expectFmt("A    ", "{s:<5}", .{buf});

    var str: [:0]const u8 = "A";
    try expectFmt("A", "{s}", .{str});

    var ptr: [*:0]const u8 = "A";
    try expectFmt("A", "{s}", .{ptr});

    var array = [_]u8{'A'};
    try expectFmt("A", "{s}", .{array});

    var cstr_array = [_:0]u8{ 'A', 0 };
    try expectFmt("A", "{s}", .{cstr_array});

    try expectFmt("A", "{s}", .{"A"});
    try expectFmt("A", "{s}", .{[_]u8{'A'}});
    try expectFmt("A", "{s}", .{[_:0]u8{'A'}});
    try expectFmt("A", "{s}", .{&[_]u8{'A'}});
    try expectFmt("A", "{s}", .{&[_:0]u8{'A'}});
}
