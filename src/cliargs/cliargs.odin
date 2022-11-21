package cliargs

import "core:reflect"
import "core:log"
import "core:strconv"
import "core:unicode/utf8"

val_type :: union {
	i128,
	f64,
	string,
	rune,
}

arg :: struct {
	long:        string,
	short:       string,
	description: string,
	required:    bool,
	default:     val_type,
	type:        ^reflect.Type_Info,
	offset:      uintptr,
}

cmd :: struct {
	name:        string,
	description: string,
	type:        reflect.Type_Info_Struct,
	offset:      uintptr,
	items:       []cmd_or_arg,
}

cmd_or_arg :: union {
	arg,
	cmd,
}

root :: struct {
	items: []cmd_or_arg,
}

build_command_parser :: proc(
	target: ^cmd,
	src: reflect.Type_Info_Struct,
	allocator := context.allocator,
) -> (
	ok: bool,
) {
	items := make([dynamic]cmd_or_arg, 0, len(src.names))

	for i := 0; i < len(src.names); i += 1 {
		tag := src.tags[i]
		if len(tag) > 0 {
			#partial switch elem in src.types[i].variant {
			case reflect.Type_Info_Struct:
				name := string(reflect.struct_tag_get(reflect.Struct_Tag(src.tags[i]), "cmd"))
				if name != "" {
					c := cmd {
						name = name,
						description = string(reflect.struct_tag_get(reflect.Struct_Tag(src.tags[i]), "description")),
						type = elem,
						offset = src.offsets[i],
					}
					ok = build_command_parser(&c, elem)
					if !ok {
						return
					}
					append(&items, c)
				}
			case reflect.Type_Info_Array:
				// TBD
				panic("not implemented")
			case reflect.Type_Info_Slice:
				// TBD
				panic("not implemented")
			case:
				ok = build_arg_parser(&items, src.types[i], reflect.Struct_Tag(src.tags[i]), src.offsets[i])
				if !ok {
					return
				}
			}
		}
	}
	target.items = items[:]
	return true
}

build_arg_parser :: proc(
	collection: ^[dynamic]cmd_or_arg,
	src: ^reflect.Type_Info,
	tag: reflect.Struct_Tag,
	offset: uintptr,
	allocator := context.allocator,
) -> (
	ok: bool,
) {
	target := arg{}
	#partial switch elem in src.variant {
	case reflect.Type_Info_Pointer:
		if ok = build_arg_parser(collection, elem.elem, tag, offset); !ok {
			return
		}
		target.type = src
	case reflect.Type_Info_Integer, reflect.Type_Info_Rune, reflect.Type_Info_Float, reflect.Type_Info_String, reflect.Type_Info_Boolean:
		target.short = string(reflect.struct_tag_get(tag, "short"))
		target.long = string(reflect.struct_tag_get(tag, "long"))
		if target.short == "" && target.long == "" {
			return true
		}
		target.description = string(reflect.struct_tag_get(tag, "description"))
		target.type = src
		target.offset = offset
		target.required = false
		required := string(reflect.struct_tag_get(tag, "required"))
		if required != "" {
			r: bool
			if r, ok = strconv.parse_bool(required); !ok {
				log.errorf("error: could not parse '%s' into a boolean (for required)", required)
				return false
			}
			target.required = r
		}
		default := string(reflect.struct_tag_get(tag, "default"))
		if default != "" {
			#partial switch in elem {
			case reflect.Type_Info_Integer:
				d: i128
				if d, ok = strconv.parse_i128(default); !ok {
					log.errorf("error: could not parse '%s' into an integer", default)
					return false
				}
				target.default = d
			case reflect.Type_Info_Rune:
				target.default, _ = utf8.decode_rune(default)
			case reflect.Type_Info_Float:
				d: f64
				if d, ok = strconv.parse_f64(default); !ok {
					log.errorf("error: could not parse '%s' into a floating point number", default)
					return false
				}
				target.default = d
			case reflect.Type_Info_String:
				// I think this works and is safe
				target.default = default
			}
		}
		append(collection, target)
	case:
		log.errorf("error: no support for the '%v' type", src)
		return false
	}
	return true
}


build_root_parser :: proc($T: typeid, r: ^root, allocator := context.allocator) -> (ok: bool) {
	ti := type_info_of(T)
	ok = true
	p: reflect.Type_Info_Pointer
	if p, ok = ti.variant.(reflect.Type_Info_Pointer); !ok {
		log.errorf("Error: input '%v' not a pointer", typeid_of(T))
		return
	}
	s: reflect.Type_Info_Struct
	if s, ok = p.elem.variant.(reflect.Type_Info_Struct); !ok {
		log.errorf("Error: input '%v' not a pointer to struct", p.elem)
		return
	}
	items := make([dynamic]cmd_or_arg, 0, len(s.names))

	for i := 0; i < len(s.names); i += 1 {
		tag := s.tags[i]
		if len(tag) > 0 {
			#partial switch elem in s.types[i].variant {
			case reflect.Type_Info_Struct:
				name := string(reflect.struct_tag_get(reflect.Struct_Tag(s.tags[i]), "cmd"))
				if name != "" {
					c := cmd {
						name = name,
						description = string(reflect.struct_tag_get(reflect.Struct_Tag(s.tags[i]), "description")),
						type = elem,
						offset = s.offsets[i],
					}
					ok = build_command_parser(&c, elem)
					if !ok {
						return
					}
					append(&items, c)
				}
			case reflect.Type_Info_Array:
				// TBD
				panic("not implemented")
			case reflect.Type_Info_Slice:
				// TBD
				panic("not implemented")
			case:
				ok = build_arg_parser(&items, s.types[i], reflect.Struct_Tag(s.tags[i]), s.offsets[i])
				if !ok {
					return
				}
			}
		}
	}

	r.items = items[:]

	return
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
