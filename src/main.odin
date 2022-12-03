package main

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
import ft "freetype"
import stb "vendor:stb/image"

Vector2i32 :: distinct [2]i32

CharStruct :: struct {
	textureID:     u32, // ID handle of the glyph texture
	size:          Vector2i32, // Size of glyph
	bearing:       Vector2i32, // Offset from baseline to left/top of glyph
	texture_coord: Vector2i32, // Coordinate in the texture map
	advance:       u32, // Offset to advance to next glyph
}


chars: [dynamic]CharStruct
freetype: ft.Library
max_height, max_width: i32
texture_width, texture_height: i32

error_handler :: proc "c" (error: c.int, description: cstring) {
	context = runtime.default_context()
	fmt.printf("error from GLFW[%d]: %s\n", error, description)
}

vertex :: struct {
	x: f32,
	y: f32,
	r: f32,
	g: f32,
	b: f32,
}

vertices: []vertex = {{-0.6, -0.4, 1, 0, 0}, {0.6, -0.4, 0, 1, 0}, {0, 0.6, 0, 0, 1}}

vertex_shader_text: cstring = `#version 110
uniform mat4 MVP;
attribute vec3 vCol;
attribute vec2 vPos;
varying vec3 color;
void main()
{
    gl_Position = MVP * vec4(vPos, 0.0, 1.0);
    color = vCol;
}
`

fragment_shader_text: cstring = `#version 110
varying vec3 color;
void main()
{
    gl_FragColor = vec4(color, 1.0);
}
`
// NOTE: This is a woefully incomplete definition since E can be some other "vector-y" thing
byte_size_slice :: proc(t: $T/[]$E) -> int {
	return size_of(E) * len(t)
}

fill_chars :: proc(face: ft.Face, chars_across: i32) {
	// gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1) // disable byte-alignment restriction

	texture_rows := 128 / chars_across
	if 128 % chars_across > 0 {
		texture_rows += 1
	}

	// TODO(jim): This can be improved.  Look at using the BBox struct in the Face
	for c: u32 = 0; c < 128; c += 1 {
		if err := ft.Load_Char(face, c, ft.LOAD_RENDER); err != 0 {
			log.errorf("Failed to load Glyph: %v", err)
			os.exit(-1)
		}
		w := i32(face.glyph.metrics.width >> 6)
		if face.glyph.metrics.width % 64 > 0 {
			w += 1
		}
		h := i32(face.glyph.metrics.height >> 6)
		if face.glyph.metrics.height % 64 > 0 {
			h += 1
		}

		if w > max_width {
			max_width = w
		}
		if h > max_height {
			max_height = h
		}
	}

	// origin := face.ascender >> 6
	// half_glyph := max_width / 2
	texture_width = max_width * chars_across
	texture_height = max_height * texture_rows
	bits := make([]byte, texture_width * texture_height)
	defer delete(bits)

	texture: u32
	// gl.GenTextures(1, &texture)
	x, y: i32
	baseIdx: i32
	for c: u32 = 0; c < 128; c += 1 {
		// load character glyph
		if err := ft.Load_Char(face, c, ft.LOAD_RENDER); err != 0 {
			log.errorf("Failed to load Glyph: %v", err)
			os.exit(-1)
		}
		if face.glyph.bitmap.width > 0 && face.glyph.bitmap.rows > 0 {
			log.infof("glyph: %v", face.glyph)
			abs_pitch := i32(abs(face.glyph.bitmap.pitch))
			row_end := abs_pitch
			glyph_len := row_end * auto_cast face.glyph.bitmap.rows
			glyph_bits := mem.slice_ptr(face.glyph.bitmap.buffer, auto_cast glyph_len)

			for yi: i32 = 0; yi < i32(face.glyph.bitmap.rows); yi += 1 {
				ds := baseIdx + i32(yi * texture_width)
				ss := yi * abs_pitch
				copy(bits[ds:], glyph_bits[ss:row_end])
				row_end += abs_pitch
			}
			append(
				&chars,
				CharStruct{
					textureID = texture,
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
	// log.debugf("texture: %d", texture)
	// gl.BindTexture(gl.TEXTURE_RECTANGLE, texture);
	// gl.TexImage2D(
	//   gl.TEXTURE_RECTANGLE,
	//   0,
	//   gl.RED,
	//   i32(texture_width),
	//   i32(texture_height),
	//   0,
	//   gl.RED,
	//   gl.UNSIGNED_BYTE,
	//   mem.raw_data(bits),
	// )
	// gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	// gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	// gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	// gl.TexParameteri(gl.TEXTURE_RECTANGLE, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	// gl.BindTexture(gl.TEXTURE_RECTANGLE, 0)
}

main :: proc() {
	context.logger = log.create_console_logger()

	if glfw.Init() == 0 {
		log.errorf("error: could not initialize glfw")
		os.exit(-1)
	}
	defer glfw.Terminate()
	glfw.SetErrorCallback(error_handler)

	window := glfw.CreateWindow(640, 480, "My Title", nil, nil)
	if window == nil {
		log.errorf("error: could not create window")
		os.exit(-1)
	}
	defer glfw.DestroyWindow(window)
	glfw.MakeContextCurrent(window)
	gl.load_up_to(4, 6, glfw.gl_set_proc_address)

	vertex_buffer, vertex_shader, fragment_shader, program: u32
	mvp_location, vpos_location, vcol_location: i32

	gl.GenBuffers(1, &vertex_buffer)
	gl.BindBuffer(gl.ARRAY_BUFFER, vertex_buffer)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		byte_size_slice(vertices),
		mem.raw_data(vertices),
		gl.STATIC_DRAW,
	)

	vertex_shader = gl.CreateShader(gl.VERTEX_SHADER)
	gl.ShaderSource(vertex_shader, 1, &vertex_shader_text, nil)
	gl.CompileShader(vertex_shader)

	fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER)
	gl.ShaderSource(fragment_shader, 1, &fragment_shader_text, nil)
	gl.CompileShader(fragment_shader)

	program = gl.CreateProgram()
	gl.AttachShader(program, vertex_shader)
	gl.AttachShader(program, fragment_shader)
	gl.LinkProgram(program)

	mvp_location = gl.GetUniformLocation(program, "MVP")
	vpos_location = gl.GetAttribLocation(program, "vPos")
	vcol_location = gl.GetAttribLocation(program, "vCol")

	gl.EnableVertexAttribArray(auto_cast vpos_location)
	gl.VertexAttribPointer(auto_cast vpos_location, 2, gl.FLOAT, gl.FALSE, size_of(vertices[0]), 0)
	gl.EnableVertexAttribArray(auto_cast vcol_location)
	gl.VertexAttribPointer(
		auto_cast vcol_location,
		3,
		gl.FLOAT,
		gl.FALSE,
		size_of(vertices[0]),
		(size_of(f32) * 2),
	)

	if err := ft.Init_FreeType(&freetype); err != 0 {
		log.error("Failed to initialize Freetype")
		os.exit(-1)
	}
	defer ft.Done_FreeType(freetype)

	face: ft.Face
	if err := ft.New_Face(
		freetype,
		"/usr/share/fonts/source-code-pro/SourceCodePro[wght].ttf",
		0,
		&face,
	); err != 0 {
		log.error("Failed to load face")
		os.exit(-1)
	}
	defer ft.Done_Face(face)
	if err := ft.Set_Char_Size(face, 0, 36 * 64, 92, 92); err != 0 {
		log.error("Failed to set face size")
		os.exit(-1)
	}
	fill_chars(face, 64)

	for !glfw.WindowShouldClose(window) {
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS do glfw.SetWindowShouldClose(window, true)

		width, height := glfw.GetFramebufferSize(window)
		ratio := (f32)(width) / (f32)(height)

		gl.Viewport(0, 0, width, height)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		m := linalg.matrix4_from_euler_angle_z_f32(auto_cast glfw.GetTime())
		p := glsl.mat4Ortho3d(-ratio, ratio, -1, 1, 1, -1)
		mvp := p * m

		gl.UseProgram(program)
		gl.UniformMatrix4fv(mvp_location, 1, gl.FALSE, ([^]f32)(&mvp))
		gl.DrawArrays(gl.TRIANGLES, 0, 3)

		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}
