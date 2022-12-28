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
	opengl_texture_id: u32,
	char_map:          []Char_Struct,
	bits:              []u8,
}


compute_font_size_in_bytes :: proc(max_rendered_font: int) -> int {
	assert(max_rendered_font > 0, "error: max_rendered_font must be greater than zero (> 0)")
	return size_of(Font) + size_of(^Rendered_Font) * max_rendered_font
}


in_place_font_init :: proc(memory: rawptr, max_rendered_font: int, allocator: runtime.Allocator) -> ^Font {
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


delete_rendered_font :: proc(rendered_font: ^Rendered_Font, allocator: runtime.Allocator) {
	assert(rendered_font != nil)
	assert(rendered_font.byte_size != 0)
	mem.zero(rendered_font, auto_cast rendered_font.byte_size)
	mem.free(rendered_font)
}