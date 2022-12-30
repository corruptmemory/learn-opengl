package font

import "core:fmt"
import "core:log"
import "core:runtime"
import "core:os"
import "core:mem"
import "core:c"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "vendor:glfw"
import gl "vendor:OpenGL"
import ft "../freetype"
import stb "vendor:stb/image"

Vec2u16 :: distinct [2]u16

Char_Struct :: struct {
	char_value:    rune,
	displayable:   bool,
	size:          Vec2u16, // Size of glyph
	bearing:       Vec2u16, // Offset from baseline to left/top of glyph
	texture_coord: Vec2u16, // Coordinate in the texture map
}

Font :: struct {
	byte_size:         u32,
	allocator:         mem.Allocator,
	max_rendered_font: int,
	face:              ft.Face,
	rendered_font:     []^Rendered_Font,
}

Rendered_Font :: struct {
	byte_size:         u32,
	font_size:         f32,
	texture_dims:      Vec2u16,
	char_height:       i32,
	max_width:         i32,
	ascender:          i32,
	descender:         i32,
	baseline:          i32,
	opengl_texture_id: u32,
	char_map:          []Char_Struct,
	bits:              []byte,
}


compute_font_size_in_bytes :: proc(max_rendered_font: int) -> int {
	assert(max_rendered_font > 0, "error: max_rendered_font must be greater than zero (> 0)")
	return size_of(Font) + size_of(^Rendered_Font) * max_rendered_font
}


in_place_font_init :: proc(
	memory: rawptr,
	max_rendered_font: int,
	allocator: runtime.Allocator,
) -> ^Font {
	memsize := compute_font_size_in_bytes(max_rendered_font)
	mem.zero(memory, memsize)
	result := (^Font)(memory)
	result.byte_size = u32(memsize)
	result.allocator = allocator
	data_start := rawptr(uintptr(memory) + size_of(Font))
	result.rendered_font = mem.slice_ptr((^^Rendered_Font)(data_start), max_rendered_font)
	return result
}


make_font :: proc(max_rendered_font: int, allocator := context.allocator) -> ^Font {
	memsize := compute_font_size_in_bytes(max_rendered_font)
	memory := mem.alloc(memsize, align_of(^Font), allocator)
	return in_place_font_init(memory, max_rendered_font, allocator)
}


load_font :: proc(font: ^Font, freetype: ft.Library, path: cstring) -> ft.Error {
	return ft.New_Face(
		freetype,
		path,
		0, // TBD
		&font.face,
	)
}


delete_font :: proc(font: ^Font) {
	assert(font != nil)
	assert(font.byte_size != 0)
	for rf in font.rendered_font {
		delete_rendered_font(rf, font.allocator)
	}
	ft.Done_Face(font.face)
	allocator := font.allocator
	mem.zero(font, auto_cast font.byte_size)
	mem.free(font, allocator)
}


// find_open_slot looks for an open slot in the list of rendered fonts.
// @font: a Font structure instance
// @target_size: the desired font rendering size
//
// Returns:
//   -1: If there is no room to render the font (all slots are occupied)
//   N : Where N corresponds to either an open slot (font.rendered_font[N] == nil) or
//       a location where the `target_size` rendering already exists.
find_open_render_slot :: proc(font: ^Font, target_size: f32) -> int {
	open_slot: int = -1
	for v, i in font.rendered_font {
		if v != nil {
			if v.font_size == target_size do return i
		} else if open_slot == -1 do open_slot = i
	}
	return open_slot
}

compute_texture_height :: proc(face: ft.Face, texture_width: i32) -> i32 {
	char_height := i32(face.size.metrics.height >> 6)
	x: i32
	texture_height := char_height

	for c : i64 = 0; c < face.num_glyphs; c += 1 {
		if err := ft.Load_Char(face, u32(c), ft.LOAD_RENDER); err != 0 {
			log.fatalf("Failed to load Glyph[%c]: %v", c, err)
		}
		abs_pitch := i32(abs(face.glyph.bitmap.pitch))
		if abs_pitch > 0 {
			x += abs_pitch
			if x >= texture_width {
				x = 0
				texture_height += char_height
			}
		}
	}
	return texture_height
}

prepare_texture :: proc(face: ft.Face, font_size: f32, texture_width: i32, horz_resolution, vert_resolution: u32) -> ^Rendered_Font {
	if err := ft.Set_Char_Size(face, 0, ft.F26Dot6(font_size * 64), horz_resolution, vert_resolution); err != 0 do log.fatalf("Failed to set face size: %v", err)
	texture_height := compute_texture_height(face, texture_width)

}


make_renderd_font :: proc(face: ft.Face,
	                      glyph_count: int,
	                      texture_height, texture_width: int,
	                      font_size: f32,
	                      char_height: i32,
						  max_width: i32,
						  ascender: i32,
						  descender: i32,
						  baseline: i32,
						  allocator: runtime.Allocator) -> ^Rendered_Font {
	sz := compute_rendered_font_size_in_bytes(glyph_count, texture_width, texture_height)
	bts := mem.alloc(sz, align_of(^Rendered_Font), allocator)
	mem.zero(bts, sz)
	result := (^Rendered_Font)(bts)
	result.byte_size = auto_cast sz
	result.font_size = font_size
	result.texture_dims = Vec2u16{u16(texture_width), u16(texture_height)}
	result.char_height = char_height
	result.max_width = max_width
	result.ascender = ascender
	result.descender = descender
	result.baseline = baseline
	after_start := uintptr(bts)+size_of(Rendered_Font)
	char_structs := mem.align_forward_uintptr(after_start, 8)
	after_char_structs := char_structs + uintptr(size_of(Char_Struct) * glyph_count)
	bits_start := mem.align_forward_uintptr(after_char_structs, 8)
	result.char_map = mem.slice_ptr((^Char_Struct)(char_structs),glyph_count)
	result.bits = mem.slice_ptr((^byte)(bits_start),texture_width*texture_height)
	return result
}


compute_rendered_font_size_in_bytes :: proc(glyph_count: int, texture_height, texture_width: int) -> int {
	assert(glyph_count > 0, "error: glyph_count must be greater than zero (> 0)")
	assert(texture_height > 0, "error: texture_height must be greater than zero (> 0)")
	assert(texture_width > 0, "error: texture_width must be greater than zero (> 0)")
	rf := size_of(Rendered_Font)
	rf_rem := 8 - rf % 8
	base_size := rf + rf_rem + size_of(Char_Struct) * glyph_count
	rem := 8 - base_size % 8
	texture_size := size_of(byte)*texture_width*texture_height
	return base_size + rem + texture_size
}

render_chars :: proc(face: ft.Face, chars_across: i32) {
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1) // disable byte-alignment restriction

	texture_rows := 128 / chars_across
	if 128 % chars_across > 0 {
		texture_rows += 1
	}

	max_height := i32(face.size.metrics.height >> 6)
	max_width := i32(face.size.metrics.max_advance >> 6)
	ascender := i32(face.size.metrics.ascender >> 6)
	descender := abs(i32(face.size.metrics.descender >> 6))
	baseline := descender - 1

	texture_width = max_width * chars_across
	texture_height = max_height * texture_rows
	bits := make([]byte, texture_width * texture_height)
	defer delete(bits)

	gl.GenTextures(1, &font_texture)
	x, y: i32
	baseIdx: i32
	for c: u32 = 0; c < 128; c += 1 {
		if err := ft.Load_Char(face, c, ft.LOAD_RENDER); err != 0 {
			log.fatalf("Failed to load Glyph: %v", err)
		}
		if face.glyph.bitmap.width > 0 && face.glyph.bitmap.rows > 0 {
			abs_pitch := i32(abs(face.glyph.bitmap.pitch))
			row_end := abs_pitch
			glyph_len := row_end * auto_cast face.glyph.bitmap.rows
			glyph_bits := mem.slice_ptr(face.glyph.bitmap.buffer, auto_cast glyph_len)
			start := ascender - face.glyph.bitmap_top
			left := face.glyph.bitmap_left
			for yi: i32 = 0; yi < i32(face.glyph.bitmap.rows); yi += 1 {
				ds := baseIdx + left + i32((yi + start) * texture_width)
				ss := yi * abs_pitch
				copy(bits[ds:], glyph_bits[ss:row_end])
				row_end += abs_pitch
			}
			append(
				&chars,
				CharStruct{
					char = u8(c),
					textureID = font_texture,
					size = Vector2i32{i32(max_width), i32(max_height)},
					bearing = Vector2i32{0, 0},
					texture_coord = Vector2i32{i32(x), i32(y)},
					advance = u32(face.glyph.advance.x) >> 6,
				},
			)
		} else {
			for yi: i32 = 0; yi < i32(face.glyph.bitmap.rows); yi += 1 {
				ds := baseIdx + i32(yi * texture_width)
				mem.zero_slice(bits[ds:ds + max_width])
			}
			append(
				&chars,
				CharStruct{
					char = u8(c),
					textureID = font_texture,
					size = Vector2i32{i32(max_width), i32(max_height)},
					bearing = Vector2i32{0, 0},
					texture_coord = Vector2i32{i32(x), i32(y)},
					advance = u32(face.glyph.advance.x) >> 6,
				},
			)
		}
		x += max_width
		if x >= texture_width {
			x = 0
			y += max_height
		}
		baseIdx = x + (y * texture_width)
	}
	stb.write_png(
		"./glyphs.png",
		texture_width,
		texture_height,
		1,
		mem.raw_data(bits),
		texture_width,
	)
	gl.BindTexture(gl.TEXTURE_RECTANGLE, font_texture)
	gl.TexImage2D(
		gl.TEXTURE_RECTANGLE,
		0,
		gl.RED,
		i32(texture_width),
		i32(texture_height),
		0,
		gl.RED,
		gl.UNSIGNED_BYTE,
		mem.raw_data(bits),
	)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.BindTexture(gl.TEXTURE_RECTANGLE, 0)
}


delete_rendered_font :: proc(rendered_font: ^Rendered_Font, allocator: runtime.Allocator) {
	assert(rendered_font != nil)
	assert(rendered_font.byte_size != 0)
	mem.zero(rendered_font, auto_cast rendered_font.byte_size)
	mem.free(rendered_font)
}
