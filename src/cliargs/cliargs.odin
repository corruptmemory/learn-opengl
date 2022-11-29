package cliargs

import "core:reflect"
import "core:runtime"
import "core:strconv"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import "core:intrinsics"

Flags :: enum {
	Help,
}

Parser :: struct {
	data:         [dynamic]byte,
	arena:        mem.Arena,
	allocator:    runtime.Allocator,
	program_name: string,
	description:  string,
	flags:        bit_set[Flags],
	cmd_or_arg:   []cmd_or_arg,
	command_path: [dynamic]^cmd,
	errors:       [dynamic]string,
}

Parse_Result :: enum {
	Success = 0,
	Failure,
	Help,
}

parse_args :: proc(
	parser: ^Parser,
	target: $T/^$E,
	args: []string,
) -> (
	result: Parse_Result,
) where intrinsics.type_is_struct(E) {
	context.allocator = parser.allocator
	ok := build_parser(parser, E)
	if !ok do return .Failure
	t := any{(rawptr)(uintptr(target)), typeid_of(T)}
	return parse_into_struct(parser, t, parser.cmd_or_arg, args, nil)
}

parser_init :: proc(
	parser: ^Parser,
	program_name, description: string,
	flags := bit_set[Flags]{.Help},
	size: int = 16384,
	allocator := context.allocator,
) {
	parser.data = make([dynamic]byte, size, allocator)
	mem.arena_init(&parser.arena, parser.data[:])
	parser.allocator = mem.arena_allocator(&parser.arena)
	parser.program_name = program_name
	parser.description = description
	parser.flags = flags
}

parser_destroy :: proc(parser: ^Parser) {
	free_all(parser.allocator)
	delete(parser.data)
	parser.data = nil
	parser.allocator = mem.nil_allocator()
}

print_help :: proc(parser: ^Parser) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	fmt.printf("%s\n     %s\n\n", parser.program_name, parser.description)
	fmt.printf("USAGE: %s", parser.program_name)
	for e in parser.command_path {
		fmt.printf(" %s", e.name)
	}
	args: [dynamic]^arg
	cmds: [dynamic]^cmd
	if parser.command_path == nil {
		for i := 0; i < len(parser.cmd_or_arg); i += 1 {
			if v, ok := &parser.cmd_or_arg[i].(arg); ok {
				append(&args, v)
			} else {
				v, _ := &parser.cmd_or_arg[i].(cmd)
				append(&cmds, v)
			}
		}
	} else {
		c := parser.command_path[len(parser.command_path) - 1]
		for i := 0; i < len(c.items); i += 1 {
			if v, ok := &c.items[i].(arg); ok {
				append(&args, v)
			} else {
				v, _ := &c.items[i].(cmd)
				append(&cmds, v)
			}
		}
	}

	for a in args {
		fmt.print(" ")
		if !a.required {
			fmt.print("[")
		}
		switch {
		case a.short != "" && a.long != "":
			fmt.printf("%s%s|%s%s", SHORT_PREFIX, a.short, LONG_PREFIX, a.long)
		case a.short != "" && a.long == "":
			fmt.printf("%s%s", SHORT_PREFIX, a.short)
		case a.short == "" && a.long != "":
			fmt.printf("%s%s", LONG_PREFIX, a.long)
		}
		#partial switch reflect.type_kind(a.type) {
		case .Integer:
			fmt.print(" <INTEGER>")
		case .Float:
			fmt.print(" <FLOAT>")
		case .String:
			fmt.print(" <STRING>")
		case .Rune:
			fmt.print(" <CHARACTER>")
		}
		if !a.required {
			fmt.print("]")
		}
	}
	fmt.println()
	if len(cmds) > 0 {
		fmt.println("\nAvailable commands:\n")
		for c in cmds {
			fmt.printf("  %-30s %s\n", c.name, c.description)
		}
	}
	if len(args) > 0 {
		builder: strings.Builder
		strings.builder_init(&builder)
		fmt.println("\nDetails:")
		for a in args {
			strings.builder_reset(&builder)
			as: string
			desc := a.description
			def: string
			if !a.required do fmt.sbprint(&builder, "[")
			switch {
			case a.short != "" && a.long != "":
				fmt.sbprintf(&builder, "%s%s|%s%s", SHORT_PREFIX, a.short, LONG_PREFIX, a.long)
			case a.short != "" && a.long == "":
				fmt.sbprintf(&builder, "%s%s", SHORT_PREFIX, a.short)
			case a.short == "" && a.long != "":
				fmt.sbprintf(&builder, "%s%s", LONG_PREFIX, a.long)
			}
			#partial switch reflect.type_kind(a.type) {
			case .Integer:
				fmt.sbprint(&builder, " <INTEGER>")
			case .Float:
				fmt.sbprint(&builder, " <FLOAT>")
			case .String:
				fmt.sbprint(&builder, " <STRING>")
			case .Rune:
				fmt.sbprint(&builder, " <CHARACTER>")
			}
			if !a.required do fmt.sbprint(&builder, "]")
			as = strings.clone(strings.to_string(builder))
			strings.builder_reset(&builder)
			if a.default != nil do def = strings.clone(fmt.sbprintf(&builder, " [DEFAULT: %v]", a.default))
			fmt.printf("  %-30s %s%s\n", as, desc, def)
		}
	}
}


@(private)
LONG_PREFIX :: "--"
@(private)
SHORT_PREFIX :: "-"
@(private)
SHORT_HELP_FLAG :: SHORT_PREFIX + "h"
@(private)
LONG_HELP_FLAG :: LONG_PREFIX + "help"

@(private)
val_type :: union {
	i128,
	f64,
	string,
	rune,
}

@(private)
arg :: struct {
	long:        string,
	short:       string,
	description: string,
	required:    bool,
	assigned:    bool,
	default:     val_type,
	type:        typeid,
	offset:      uintptr,
}

@(private)
cmd :: struct {
	name:        string,
	description: string,
	type:        typeid,
	offset:      uintptr,
	items:       []cmd_or_arg,
}

@(private)
cmd_or_arg :: union {
	arg,
	cmd,
}

@(private)
build_command_parser :: proc(parser: ^Parser, target: ^cmd, S: typeid) -> bool {
	ti := reflect.type_info_base(type_info_of(S))
	src, ok := ti.variant.(reflect.Type_Info_Struct)
	if !ok {
		append(&parser.errors, "command not associated with a structure")
		return false
	}
	items := make([dynamic]cmd_or_arg, 0, len(src.names))
	for i := 0; i < len(src.names); i += 1 {
		field := reflect.struct_field_at(S, i)
		if len(field.tag) > 0 {
			k := reflect.type_kind(field.type.id)
			#partial switch k {
			case .Struct:
				name := string(reflect.struct_tag_get(reflect.Struct_Tag(src.tags[i]), "cmd"))
				if name != "" {
					c := cmd {
						name        = name,
						description = string(
							reflect.struct_tag_get(reflect.Struct_Tag(src.tags[i]), "description"),
						),
						type        = field.type.id,
						offset      = field.offset,
					}
					build_command_parser(parser, &c, field.type.id) or_return
					append(&items, c)
				}
			case .Array:
				// TBD
				panic("not implemented")
			case .Slice:
				// TBD
				panic("not implemented")
			case:
				build_arg_parser(parser, &items, field, k) or_return
			}
		}
	}
	target.items = items[:]
	return true
}

@(private)
build_arg_parser :: proc(
	parser: ^Parser,
	collection: ^[dynamic]cmd_or_arg,
	field: reflect.Struct_Field,
	kind: reflect.Type_Kind,
	allocator := context.allocator,
) -> (
	ok: bool,
) {
	k := kind
	target := arg {
		short       = string(reflect.struct_tag_get(field.tag, "short")),
		long        = string(reflect.struct_tag_get(field.tag, "long")),
		description = string(reflect.struct_tag_get(field.tag, "description")),
		type        = field.type.id,
		offset      = field.offset,
		default     = nil,
	}
	if target.short == "" && target.long == "" do return true

	required := string(reflect.struct_tag_get(field.tag, "required"))
	if required != "" {
		r: bool
		if r, ok = strconv.parse_bool(required); !ok {
			append(
				&parser.errors,
				fmt.aprintf("could not parse '%s' into a boolean (for required)", required),
			)
			return false
		}
		target.required = r
	}
	if k == .Pointer {
		ptr_info := field.type.variant.(reflect.Type_Info_Pointer)
		k = reflect.type_kind(ptr_info.elem.id)
		#partial switch k {
		case .Integer, .Float, .String, .Boolean, .Rune:
		case:
			append(
				&parser.errors,
				fmt.aprintf(
					"cannot process an argument that is a pointer to %v",
					ptr_info.elem.id,
				),
			)
			return false
		}
	}
	#partial switch k {
	case .Integer, .Float, .String, .Boolean, .Rune:
		default := string(reflect.struct_tag_get(field.tag, "default"))
		if default != "" {
			#partial switch k {
			case .Integer:
				d: i128
				if d, ok = strconv.parse_i128(default); !ok {
					append(
						&parser.errors,
						fmt.aprintf("could not parse '%s' into an integer", default),
					)
					return false
				}
				target.default = d
			case .Rune:
				target.default, _ = utf8.decode_rune(default)
			case .Float:
				d: f64
				if d, ok = strconv.parse_f64(default); !ok {
					append(
						&parser.errors,
						fmt.aprintf("could not parse '%s' into a floating point number", default),
					)
					return false
				}
				target.default = d
			case .String:
				target.default = default
			}
		}
	case:
		append(&parser.errors, fmt.aprintf("no support for the '%v' type", field.type))
		return false
	}
	append(collection, target)
	return true
}

@(private)
build_parser :: proc(parser: ^Parser, $T: typeid) -> (ok: bool) {
	ti := reflect.type_info_base(type_info_of(T))
	s: reflect.Type_Info_Struct
	s, _ = ti.variant.(reflect.Type_Info_Struct)
	items := make([dynamic]cmd_or_arg, 0, len(s.names))
	defer if !ok do delete(items)

	for i := 0; i < len(s.names); i += 1 {
		field := reflect.struct_field_at(ti.id, i)
		if len(field.tag) > 0 {
			k := reflect.type_kind(reflect.typeid_core(field.type.id))
			#partial switch k {
			case .Struct:
				name := string(reflect.struct_tag_get(field.tag, "cmd"))
				if name != "" {
					c := cmd {
						name        = name,
						description = string(reflect.struct_tag_get(field.tag, "description")),
						type        = field.type.id,
						offset      = field.offset,
					}
					ok = build_command_parser(parser, &c, field.type.id)
					if !ok do return
					append(&items, c)
				}
			case .Array:
				// TBD
				panic("not implemented")
			case .Slice:
				// TBD
				panic("not implemented")
			case:
				ok = build_arg_parser(parser, &items, field, k)
				if !ok do return
			}
		}
	}

	parser.cmd_or_arg = items[:]
	return true
}

@(private)
find_short :: proc(short: string, cmd_or_arg: []cmd_or_arg) -> (result: ^arg) {
	for v, i in cmd_or_arg {
		if e, ok := v.(arg); ok {
			if e.short == short do return &cmd_or_arg[i].(arg)
		}
	}
	return nil
}

@(private)
find_long :: proc(long: string, cmd_or_arg: []cmd_or_arg) -> (result: ^arg) {
	for v, i in cmd_or_arg {
		if e, ok := v.(arg); ok {
			if e.long == long do return &cmd_or_arg[i].(arg)
		}
	}
	return nil
}

@(private)
find_cmd :: proc(name: string, cmd_or_arg: []cmd_or_arg) -> (result: ^cmd) {
	for v, i in cmd_or_arg {
		if e, ok := v.(cmd); ok {
			if e.name == name do return &cmd_or_arg[i].(cmd)
		}
	}
	return nil
}

@(private)
could_not_parse :: proc(parser: ^Parser, arg, val, expected: string) -> bool {
	append(
		&parser.errors,
		fmt.aprintf("could not parse (%s) argument for %s: %s", expected, arg, val),
	)
	return false
}

@(private)
consume_arg :: proc(
	parser: ^Parser,
	kind: reflect.Type_Kind,
	target: any,
	arg, val: string,
) -> bool {
	#partial switch kind {
	case .Integer:
		v, ok := strconv.parse_i128(val)
		if !ok do return could_not_parse(parser, arg, val, "i128")
		return assign_int(target, v)
	case .Float:
		v, ok := strconv.parse_f64(val)
		if !ok do return could_not_parse(parser, arg, val, "f64")
		return assign_float(target, v)
	case .String:
		return assign_string(target, val)
	case .Rune:
		return assign_rune(target, val)
	}
	return true
}

@(private)
assign_defaults :: proc(target: any, cmd_or_arg: []cmd_or_arg) -> bool {
	for i := 0; i < len(cmd_or_arg); i += 1 {
		if e, ok := &cmd_or_arg[i].(arg); ok {
			t := any{(rawptr)(uintptr(target.data) + e.offset), e.type}
			if e.default == nil do continue
			assigned := false
			switch dv in e.default {
			case i128:
				assigned = assign_int(t, dv)
			case f64:
				assigned = assign_float(t, dv)
			case string:
				assigned = assign_string(t, dv)
			case rune:
				assigned = assign_rune(t, dv)
			}
			e.assigned = assigned
			if !assigned do return false
		}
	}
	return true
}

@(private)
check_required :: proc(parser: ^Parser, cmd_or_arg: []cmd_or_arg) -> (result: Parse_Result) {
	result = .Success
	for v in cmd_or_arg {
		if e, ok := v.(arg); ok {
			if !e.assigned && e.required {
				n := strings.concatenate([]string{SHORT_PREFIX, e.short})
				if e.long != "" do n = strings.concatenate([]string{LONG_PREFIX, e.long})
				append(&parser.errors, fmt.aprintf("missing required argument: %s", n))
				result = .Failure
			}
		}
	}
	return result
}

@(private)
is_help_flag :: proc(parser: ^Parser, arg: string) -> bool {
	if .Help in parser.flags {
		switch arg {
		case SHORT_HELP_FLAG, LONG_HELP_FLAG:
			return true
		case:
			return false
		}
	}
	return false
}

@(private)
parse_into_struct :: proc(
	parser: ^Parser,
	target: any,
	cmd_or_arg: []cmd_or_arg,
	remaining: []string,
	current_command: ^cmd,
) -> (
	result: Parse_Result,
) {
	if current_command != nil {
		append(&parser.command_path, current_command)
	}
	assign_defaults(target, cmd_or_arg)
	r := remaining
	for len(r) > 0 {
		v := r[0]
		a: ^arg
		switch {
		case is_help_flag(parser, v):
			return .Help
		case strings.has_prefix(v, LONG_PREFIX):
			a = find_long(v[2:], cmd_or_arg)
		case strings.has_prefix(v, SHORT_PREFIX):
			a = find_short(v[1:], cmd_or_arg)
		case:
			c := find_cmd(v, cmd_or_arg)
			if c == nil {
				append(&parser.errors, fmt.aprintf("unrecognized command: %s", v))
				return .Failure
			}
			data := any{(rawptr)(uintptr(target.data) + c.offset), c.type}
			return parse_into_struct(parser, data, c.items, r[1:], c)
		}
		if a == nil {
			append(&parser.errors, fmt.aprintf("unrecognized flag: %s", v))
			return .Failure
		}
		k := reflect.type_kind(a.type)
		data := any{(rawptr)(uintptr(target.data) + a.offset), a.type}
		#partial switch k {
		case .Integer, .Float, .String, .Rune:
			if len(r) == 1 {
				append(&parser.errors, fmt.aprintf("no value supplied for %s", v))
				return .Failure
			}
			a.assigned = consume_arg(parser, k, data, v, r[1])
			if !a.assigned do return .Failure
			r = r[2:]
		case .Boolean:
			a.assigned = true
			assign_bool(data, true)
			r = r[1:]
		}
	}
	return check_required(parser, cmd_or_arg)
}


@(private)
assign_bool :: proc(val: any, b: bool) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case bool:
		dst = bool(b)
	case b8:
		dst = b8(b)
	case b16:
		dst = b16(b)
	case b32:
		dst = b32(b)
	case b64:
		dst = b64(b)
	case:
		return false
	}
	return true
}

@(private)
assign_int :: proc(val: any, i: $T) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case i8:
		dst = i8(i)
	case i16:
		dst = i16(i)
	case i16le:
		dst = i16le(i)
	case i16be:
		dst = i16be(i)
	case i32:
		dst = i32(i)
	case i32le:
		dst = i32le(i)
	case i32be:
		dst = i32be(i)
	case i64:
		dst = i64(i)
	case i64le:
		dst = i64le(i)
	case i64be:
		dst = i64be(i)
	case i128:
		dst = i128(i)
	case i128le:
		dst = i128le(i)
	case i128be:
		dst = i128be(i)
	case u8:
		dst = u8(i)
	case u16:
		dst = u16(i)
	case u16le:
		dst = u16le(i)
	case u16be:
		dst = u16be(i)
	case u32:
		dst = u32(i)
	case u32le:
		dst = u32le(i)
	case u32be:
		dst = u32be(i)
	case u64:
		dst = u64(i)
	case u64le:
		dst = u64le(i)
	case u64be:
		dst = u64be(i)
	case u128:
		dst = u128(i)
	case u128le:
		dst = u128le(i)
	case u128be:
		dst = u128be(i)
	case int:
		dst = int(i)
	case uint:
		dst = uint(i)
	case uintptr:
		dst = uintptr(i)
	case:
		return false
	}
	return true
}

@(private)
assign_float :: proc(val: any, f: $T) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case f16:
		dst = f16(f)
	case f16le:
		dst = f16le(f)
	case f16be:
		dst = f16be(f)
	case f32:
		dst = f32(f)
	case f32le:
		dst = f32le(f)
	case f32be:
		dst = f32be(f)
	case f64:
		dst = f64(f)
	case f64le:
		dst = f64le(f)
	case f64be:
		dst = f64be(f)

	case complex32:
		dst = complex(f16(f), 0)
	case complex64:
		dst = complex(f32(f), 0)
	case complex128:
		dst = complex(f64(f), 0)

	case quaternion64:
		dst = quaternion(f16(f), 0, 0, 0)
	case quaternion128:
		dst = quaternion(f32(f), 0, 0, 0)
	case quaternion256:
		dst = quaternion(f64(f), 0, 0, 0)

	case:
		return false
	}
	return true
}

@(private)
assign_string :: proc(val: any, f: string) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case string:
		dst = f
	case:
		return false
	}
	return true
}

@(private)
get_rune_from_string :: proc(thing: string) -> rune {
	r, _ := utf8.decode_rune_in_string(thing)
	return r
}

@(private)
get_rune_from_rune :: proc(thing: rune) -> rune {
	return thing
}

@(private)
get_rune :: proc {
	get_rune_from_string,
	get_rune_from_rune,
}


@(private)
assign_rune :: proc(val: any, f: $T) -> bool {
	v := reflect.any_core(val)
	switch dst in &v {
	case rune:
		dst = get_rune(f)
	case:
		return false
	}
	return true
}
