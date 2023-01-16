package font

// import "core:fmt"
import "core:log"
import "core:runtime"
// import "core:os"
import "core:mem"
// import "core:c"
// import "core:math/linalg"
import "core:math/linalg/glsl"
// import "vendor:glfw"
import gl "vendor:OpenGL"
import ft "../freetype"
import stb "vendor:stb/image"

Vec2u16 :: distinct [2]u16

Texture_Width :: 512

text_vertex_shader_text: cstring = `#version 330 core
layout (location = 0) in vec4 vertex; // <vec2 pos, vec2 tex>
out vec2 TexCoords;

uniform mat4 projection;

void main()
{
    gl_Position = projection * vec4(vertex.xy, 0.0, 1.0);
    TexCoords = vertex.zw;
}
`

text_fragment_shader_text: cstring = `#version 330 core
in vec2 TexCoords;
out vec4 color;

uniform sampler2DRect text;
uniform vec3 textColor;

void main()
{
    vec4 sampled = vec4(1.0, 1.0, 1.0, texture(text, TexCoords).r);
    color = vec4(textColor, 1.0) * sampled;
}
`


Char_Struct :: struct {
	char_value:    rune,
	displayable:   bool,
	advance:       u16,
	size:          Vec2u16, // Size of glyph
	bearing:       Vec2u16, // Offset from baseline to left/top of glyph
	texture_coord: Vec2u16, // Coordinate in the texture map
}

Font :: struct {
	byte_size:           u32,
	allocator:           mem.Allocator,
	max_rendered_font:   int,
	face:                ft.Face,
	vertex_shader: u32,
	fragment_shader: u32,
	program:             u32,
	color_location:      i32,
	text_location:       i32,
	text_vertex:         i32,
	projection_location: i32,
	projection:          glsl.mat4,
	VAO:                 u32,
	VBO:                 u32,
	rendered_font:       []^Rendered_Font,
}

Rendered_Font :: struct {
	byte_size:         u32,
	allocator:         mem.Allocator,
	font_size:         f32,
	texture_dims:      Vec2u16,
	char_height:       i32,
	max_width:         i32,
	ascender:          i32,
	descender:         i32,
	baseline:          i32,
	horz_resolution:   u32,
	vert_resolution:   u32,
	opengl_texture_id: u32,
	char_map:          []Char_Struct,
	bits:              []byte,
}


compute_font_size_in_bytes :: proc(max_rendered_font: int) -> int {
	assert(max_rendered_font > 0, "error: max_rendered_font must be greater than zero (> 0)")
	return size_of(Font) + size_of(^Rendered_Font) * max_rendered_font
}

mat4Ortho3d :: proc "c" (left, right, bottom, top: f32) -> (m: glsl.mat4) {
	m[0, 0] = +2 / (right - left)
	m[1, 1] = +2 / (top - bottom)
	m[2, 2] = 1
	m[0, 3] = -(right + left)   / (right - left)
	m[1, 3] = -(top   + bottom) / (top - bottom)
	m[3, 3] = 1
	return m
}

in_place_font_init :: proc(
	memory: rawptr,
	memsize: u32,
	max_rendered_font: int,
	allocator: runtime.Allocator,
) -> ^Font {
	mem.zero(memory, auto_cast memsize)
	result := (^Font)(memory)
	result.byte_size = u32(memsize)
	result.allocator = allocator
	data_start := rawptr(uintptr(memory) + size_of(Font))
	result.rendered_font = mem.slice_ptr((^^Rendered_Font)(data_start), max_rendered_font)
	result.projection = mat4Ortho3d(0.0, 640.0, 0.0, 480.0)
	result.vertex_shader = gl.CreateShader(gl.VERTEX_SHADER)
	gl.ShaderSource(result.vertex_shader, 1, &text_vertex_shader_text, nil)
	gl.CompileShader(result.vertex_shader)

	result.fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER)
	gl.ShaderSource(result.fragment_shader, 1, &text_fragment_shader_text, nil)
	gl.CompileShader(result.fragment_shader)

	result.program = gl.CreateProgram()
	gl.AttachShader(result.program, result.vertex_shader)
	gl.AttachShader(result.program, result.fragment_shader)
	gl.LinkProgram(result.program)

	result.projection_location = gl.GetUniformLocation(result.program, "projection")
	result.color_location = gl.GetUniformLocation(result.program, "textColor")
	result.text_location = gl.GetAttribLocation(result.program, "text")
	result.text_vertex = gl.GetAttribLocation(result.program, "vertex")

	gl.GenVertexArrays(1, &result.VAO)
	gl.GenBuffers(1, &result.VBO)
	gl.BindVertexArray(result.VAO)
	gl.BindBuffer(gl.ARRAY_BUFFER, result.VBO)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * 6 * 4, nil, gl.DYNAMIC_DRAW)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	return result
}


make_font :: proc(max_rendered_font: int, allocator := context.allocator) -> ^Font {
	memsize := compute_font_size_in_bytes(max_rendered_font)
	memory := mem.alloc(memsize, align_of(^Font), allocator)
	return in_place_font_init(memory, auto_cast memsize, max_rendered_font, allocator)
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


render_font :: proc(font: ^Font, target_size: f32, horz_resolution, vert_resolution: u32) -> bool {
	slot := find_open_render_slot(font, target_size)
	if slot < 0 do return false
	if err := ft.Set_Char_Size(font.face, 0, ft.F26Dot6(target_size * 64), 92, 92); err != 0 {
		log.fatal("Failed to set face size")
	}
	th, ch := compute_texture_height(font.face, Texture_Width)
	max_width := i32(font.face.size.metrics.max_advance >> 6)
	ascender := i32(font.face.size.metrics.ascender >> 6)
	descender := abs(i32(font.face.size.metrics.descender >> 6))
	baseline := descender - 1

	rf := make_renderd_font(
		font.face,
		auto_cast font.face.num_glyphs,
		auto_cast th,
		Texture_Width,
		horz_resolution,
		vert_resolution,
		target_size,
		ch,
		max_width,
		ascender,
		descender,
		baseline,
		font.allocator,
	)
	render_chars(rf, font.face)
	font.rendered_font[slot] = rf
	return true
}

// TODO: Figure out a sensible way to combind this calculation and the rendering
//       of the font into the texture without having to walk this twice.  This just smells
//       of bad design.  Which is most certainly is.
compute_texture_height :: proc(face: ft.Face, texture_width: i32) -> (i32, i32) {
	char_height := i32(face.size.metrics.height >> 6)
	x: i32
	char_rows : i32 = 1
	max_width := i32(face.size.metrics.max_advance >> 6)

	for c: i64 = 0; c < face.num_glyphs; c += 1 {
		if err := ft.Load_Char(face, u32(c), ft.LOAD_RENDER); err != 0 {
			log.fatalf("Failed to load Glyph[%c]: %v", c, err)
		}
		abs_pitch: i32
		if face.glyph.bitmap.width > 0 && face.glyph.bitmap.rows > 0 {
			abs_pitch = i32(abs(face.glyph.bitmap.pitch))
			if char_height < auto_cast face.glyph.bitmap.rows {
				char_height = auto_cast face.glyph.bitmap.rows
			}
		} else {
			abs_pitch = max_width
		}
		if abs_pitch == 0 {
			abs_pitch = max_width
		}
		x += abs_pitch
		if x >= texture_width {
			x = abs_pitch
			char_rows += 1
		}
	}
	return char_rows * char_height, char_height
}


in_place_rendered_font_init :: proc(
	face: ft.Face,
	memory: rawptr,
	memsize: u32,
	glyph_count: int,
	texture_height, texture_width: int,
	horz_resolution, vert_resolution: u32,
	font_size: f32,
	char_height: i32,
	max_width: i32,
	ascender: i32,
	descender: i32,
	baseline: i32,
	allocator: runtime.Allocator,
) -> ^Rendered_Font {
	mem.zero(memory, auto_cast memsize)
	result := (^Rendered_Font)(memory)
	result.byte_size = auto_cast memsize
	result.font_size = font_size
	result.texture_dims = Vec2u16{u16(texture_width), u16(texture_height)}
	result.horz_resolution = horz_resolution
	result.vert_resolution = vert_resolution
	result.char_height = char_height
	result.max_width = max_width
	result.ascender = ascender
	result.descender = descender
	result.baseline = baseline
	result.allocator = allocator
	after_start := uintptr(memory) + size_of(Rendered_Font)
	char_structs := mem.align_forward_uintptr(after_start, 8)
	after_char_structs := char_structs + uintptr(size_of(Char_Struct) * glyph_count)
	bits_start := mem.align_forward_uintptr(after_char_structs, 8)
	result.char_map = mem.slice_ptr((^Char_Struct)(char_structs), glyph_count)
	result.bits = mem.slice_ptr((^byte)(bits_start), texture_width * texture_height)
	return result
}


make_renderd_font :: proc(
	face: ft.Face,
	glyph_count: int,
	texture_height, texture_width: int,
	horz_resolution, vert_resolution: u32,
	font_size: f32,
	char_height: i32,
	max_width: i32,
	ascender: i32,
	descender: i32,
	baseline: i32,
	allocator: runtime.Allocator,
) -> ^Rendered_Font {
	sz := compute_rendered_font_size_in_bytes(glyph_count, texture_width, texture_height)
	bts := mem.alloc(sz, align_of(^Rendered_Font), allocator)
	return in_place_rendered_font_init(
		face,
		bts,
		u32(sz),
		glyph_count,
		texture_height,
		texture_width,
		horz_resolution,
		vert_resolution,
		font_size,
		char_height,
		max_width,
		ascender,
		descender,
		baseline,
		allocator,
	)
}


compute_rendered_font_size_in_bytes :: proc(
	glyph_count: int,
	texture_height, texture_width: int,
) -> int {
	assert(glyph_count > 0, "error: glyph_count must be greater than zero (> 0)")
	assert(texture_height > 0, "error: texture_height must be greater than zero (> 0)")
	assert(texture_width > 0, "error: texture_width must be greater than zero (> 0)")
	rf := size_of(Rendered_Font)
	rf_rem := 8 - rf % 8
	base_size := rf + rf_rem + size_of(Char_Struct) * glyph_count
	rem := 8 - base_size % 8
	texture_size := size_of(byte) * texture_width * texture_height
	return base_size + rem + texture_size
}


render_chars :: proc(rf: ^Rendered_Font, face: ft.Face) {
	char_height := rf.char_height
	max_width := rf.max_width
	ascender := rf.ascender
	// descender := rf.descender
	// baseline := rf.baseline

	texture_width := i32(rf.texture_dims.x)
	texture_height := i32(rf.texture_dims.y)
	bits := rf.bits

	// TODO: Descide what we should do with the OpenGL texture generation.  Not sure that we should
	//       do this right here or do it lazily on demand when we need to use a particular rendered
	//       font.
	x, y: i32
	baseIdx: i32
	for c: u32 = 0; c < auto_cast len(rf.char_map); c += 1 {
		if err := ft.Load_Char(face, c, ft.LOAD_RENDER); err != 0 {
			log.fatalf("Failed to load Glyph: %v", err)
		}
		cm := &rf.char_map[c]
		cm.char_value = auto_cast c
		cm.displayable = true
		cm.bearing = Vec2u16{auto_cast face.glyph.metrics.horiBearingX >> 6, 0}
		cm.advance = u16(u32(face.glyph.advance.x) >> 6)
		if face.glyph.bitmap.width > 0 && face.glyph.bitmap.rows > 0 {
			abs_pitch := i32(abs(face.glyph.bitmap.pitch))
			row_end := abs_pitch
			if x + abs_pitch >= texture_width {
				x = 0
				y += char_height
			}
			baseIdx = x + (y * texture_width)
			glyph_len := row_end * auto_cast face.glyph.bitmap.rows
			glyph_bits := mem.slice_ptr(face.glyph.bitmap.buffer, auto_cast glyph_len)
			start := ascender - face.glyph.bitmap_top
			if start < 0 do start = 0
			left := face.glyph.bitmap_left
			for yi: i32 = 0; yi < i32(face.glyph.bitmap.rows); yi += 1 {
				// ds := baseIdx + left + i32((yi + start) * texture_width)
				ds := baseIdx + i32((yi + start) * texture_width)
				ss := yi * abs_pitch
				copy(bits[ds:], glyph_bits[ss:row_end])
				row_end += abs_pitch
			}
			cm.size = Vec2u16{u16(abs_pitch), u16(char_height)}
		} else {
			if x + max_width >= texture_width {
				x = 0
				y += char_height
			}
			baseIdx = x + (y * texture_width)
			for yi: i32 = 0; yi < i32(face.glyph.bitmap.rows); yi += 1 {
				ds := baseIdx + i32(yi * texture_width)
				mem.zero_slice(bits[ds:ds + max_width])
			}
			cm.size = Vec2u16{u16(max_width), u16(char_height)}
		}
		cm.texture_coord = Vec2u16{u16(x), u16(y)}
		x += auto_cast cm.size.x
	}
	log.info("Starting to write glyphs")
	stb.write_png(
		"./glyphs-new.png",
		texture_width,
		texture_height,
		1,
		mem.raw_data(bits),
		texture_width,
	)
}


delete_rendered_font :: proc(rendered_font: ^Rendered_Font, allocator: runtime.Allocator) {
	assert(rendered_font != nil)
	assert(rendered_font.byte_size != 0)
	mem.zero(rendered_font, auto_cast rendered_font.byte_size)
	mem.free(rendered_font)
}


create_opengl_texture :: proc(font: ^Font, font_size: f32) -> bool {
	idx := -1
	for i := 0; i < len(font.rendered_font); i += 1 {
		if font.rendered_font[i].font_size == font_size {
			if font.rendered_font[i].opengl_texture_id != 0 do return true
			idx = i
			break
		}
	}
	if idx == -1 do return false
	rf := font.rendered_font[idx]

	gl.GenTextures(1, &rf.opengl_texture_id)
	gl.BindTexture(gl.TEXTURE_RECTANGLE, rf.opengl_texture_id)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1) // disable byte-alignment restriction
	gl.TexImage2D(
		gl.TEXTURE_RECTANGLE,
		0,
		gl.RED,
		i32(rf.texture_dims.x),
		i32(rf.texture_dims.y),
		0,
		gl.RED,
		gl.UNSIGNED_BYTE,
		mem.raw_data(rf.bits),
	)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.BindTexture(gl.TEXTURE_RECTANGLE, 0)
	return true
}


draw_text :: proc(font: ^Font, text: string, x, y: f32, size: f32, color: glsl.vec3) {
	// activate corresponding render state
	if !create_opengl_texture(font, size) {
		log.errorf("error: failed to create/find a rendered font of size %v", size)
		return
	}
	rendered_font: ^Rendered_Font
	for i := 0; i < len(font.rendered_font); i += 1 {
		rendered_font = font.rendered_font[i]
		if rendered_font.font_size == size && rendered_font.opengl_texture_id != 0 do break
	}
	gl.UseProgram(font.program)
	gl.UniformMatrix4fv(font.projection_location, 1, gl.FALSE, ([^]f32)(&font.projection))
	gl.Uniform3f(font.color_location, color.x, color.y, color.z)
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindVertexArray(font.VAO)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.BindTexture(gl.TEXTURE_RECTANGLE, rendered_font.opengl_texture_id)

	local_x := x

	for c in text {
		ch := rendered_font.char_map[c]
		xpos := local_x + f32(ch.bearing.x)
		ypos := y - f32(ch.size.y - ch.bearing.y)

		w := f32(ch.size.x)
		h := f32(ch.size.y)
		// update VBO for each character
		vertices: [6][4]f32 = {
			{xpos, ypos + h, f32(ch.texture_coord.x), f32(ch.texture_coord.y)}, // { xpos,     ypos + h,   0.0, 0.0 }
			{xpos, ypos, f32(ch.texture_coord.x), f32(ch.texture_coord.y) + h}, // { xpos,     ypos,       0.0, 1.0 }
			{xpos + w, ypos, f32(ch.texture_coord.x) + w, f32(ch.texture_coord.y) + h}, // { xpos + w, ypos,       1.0, 1.0 }
			{xpos, ypos + h, f32(ch.texture_coord.x), f32(ch.texture_coord.y)}, // { xpos,     ypos + h,   0.0, 0.0 }
			{xpos + w, ypos, f32(ch.texture_coord.x) + w, f32(ch.texture_coord.y) + h}, // { xpos + w, ypos,       1.0, 1.0 }
			{xpos + w, ypos + h, f32(ch.texture_coord.x) + w, f32(ch.texture_coord.y)}, // { xpos + w, ypos + h,   1.0, 0.0 }
		}

		gl.BindBuffer(gl.ARRAY_BUFFER, font.VBO)
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(vertices), mem.raw_data(vertices[:]))
		gl.BindBuffer(gl.ARRAY_BUFFER, 0)
		// render quad
		gl.DrawArrays(gl.TRIANGLES, 0, 6)
		// now advance cursors for next glyph (note that advance is number of 1/64 pixels)
		local_x += f32(ch.advance) // bitshift by 6 to get value in pixels (2^6 = 64)
	}
	gl.BindVertexArray(0)
	gl.BindTexture(gl.TEXTURE_RECTANGLE, 0)
}
