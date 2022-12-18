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

Vector2u16 :: distinct [2]u16

Char_Struct :: struct {
	char_value:          rune,
	displayable:         bool,
	size:                Vector2u16, // Size of glyph
	bearing:             Vector2u16, // Offset from baseline to left/top of glyph
	texture_coord:       Vector2u16, // Coordinate in the texture map
}

Font :: struct {
	byte_size:         u32,
	font_name:         string,
	font_variant:      string,

}

Rendered_Font :: struct {
	byte_size:         u32,
	font_size:         f32,
	texture_dims:      Vector2u16,
	opengl_texture_id: u32,
	char_hashmap:      []Char_Struct,
	bits:              []u8,
}
