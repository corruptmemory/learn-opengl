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
import lft "font"

Vector2i32 :: distinct [2]i32

Font :: struct {

}

CharStruct :: struct {
	char:          u8, // The char
	textureID:     u32, // ID handle of the glyph texture
	size:          Vector2i32, // Size of glyph
	bearing:       Vector2i32, // Offset from baseline to left/top of glyph
	texture_coord: Vector2i32, // Coordinate in the texture map
	advance:       u32, // Offset to advance to next glyph
}

chars: [dynamic]CharStruct
freetype: ft.Library
max_height, max_width, ascender, descender, baseline: i32
texture_width, texture_height: i32

font_texture: u32
text_vertex_buffer, text_vertex_shader, text_fragment_shader, text_program: u32
text_color_location, text_text_location, text_vertex, text_projection_location: i32

text_projection: glsl.mat4
VAO, VBO: u32

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

// NOTE: This is a woefully incomplete definition since E can be some other "vector-y" thing
byte_size_slice :: proc(t: $T/[]$E) -> int {
	return size_of(E) * len(t)
}

log_metric :: proc(name: string, pos: ft.Pos) {
	log.infof("     %s: %d", name, pos >> 6)
}

log_glyph_metrics :: proc(gm: ^ft.Glyph_Metrics) {
	log.info("*** glyph metrics")
	log_metric("width", gm.width)
	log_metric("height", gm.height)
	log_metric("horiBearingX", gm.horiBearingX)
	log_metric("horiBearingY", gm.horiBearingY)
	log_metric("horiAdvance", gm.horiAdvance)
	log_metric("vertBearingX", gm.vertBearingX)
	log_metric("vertBearingY", gm.vertBearingY)
	log_metric("vertAdvance", gm.vertAdvance)
}

log_size_metrics :: proc(gm: ^ft.Size_Metrics) {
	log.info("*** size metrics")
	log.infof("     x_ppem: %v", gm.x_ppem)
	log.infof("     y_ppem: %v", gm.y_ppem)
	log.infof("     x_scale: %v", gm.x_scale)
	log.infof("     y_scale: %v", gm.y_scale)
	log_metric("ascender", gm.ascender)
	log_metric("descender", gm.descender)
	log_metric("height", gm.height)
	log_metric("max_advance", gm.max_advance)
}


fill_chars :: proc(face: ft.Face, chars_across: i32) {
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1) // disable byte-alignment restriction

	texture_rows := 128 / chars_across
	if 128 % chars_across > 0 {
		texture_rows += 1
	}

	max_height = i32(face.size.metrics.height >> 6)
	max_width = i32(face.size.metrics.max_advance >> 6)
	ascender = i32(face.size.metrics.ascender >> 6)
	descender = abs(i32(face.size.metrics.descender >> 6))
	baseline = descender-1

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
				ds := baseIdx + left + i32((yi+start) * texture_width)
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
				mem.zero_slice(bits[ds:ds+max_width])
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

// Result[0][0] = static_cast<T>(2) / (right - left);
// Result[1][1] = static_cast<T>(2) / (top - bottom);
// Result[2][2] = - static_cast<T>(1);
// Result[3][0] = - (right + left) / (right - left);
// Result[3][1] = - (top + bottom) / (top - bottom);

mat4Ortho3d :: proc "c" (left, right, bottom, top: f32) -> (m: glsl.mat4) {
	m[0, 0] = +2 / (right - left)
	m[1, 1] = +2 / (top - bottom)
	m[2, 2] = 1
	m[0, 3] = -(right + left)   / (right - left)
	m[1, 3] = -(top   + bottom) / (top - bottom)
	m[3, 3] = 1
	return m
}

render_text :: proc(text: string, x, y: f32, scale: f32, color: glsl.vec3) {
    // activate corresponding render state
    gl.UseProgram(text_program)
    gl.UniformMatrix4fv(text_projection_location, 1, gl.FALSE, ([^]f32)(&text_projection))
    gl.Uniform3f(text_color_location, color.x, color.y, color.z)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindVertexArray(VAO)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.BindTexture(gl.TEXTURE_RECTANGLE, font_texture)

    local_x := x

    for c in text {
        ch := chars[c]
        xpos := local_x + f32(ch.bearing.x) * scale
        ypos := y - f32(ch.size.y - ch.bearing.y) * scale

        w := f32(ch.size.x) * scale
        h := f32(ch.size.y) * scale
        // update VBO for each character
        vertices: [6][4]f32 = {
            { xpos,   ypos+h, f32(ch.texture_coord.x),   f32(ch.texture_coord.y)   }, // { xpos,     ypos + h,   0.0, 0.0 }
            { xpos,   ypos,   f32(ch.texture_coord.x),   f32(ch.texture_coord.y)+h }, // { xpos,     ypos,       0.0, 1.0 }
            { xpos+w, ypos,   f32(ch.texture_coord.x)+w, f32(ch.texture_coord.y)+h }, // { xpos + w, ypos,       1.0, 1.0 }

            { xpos,   ypos+h, f32(ch.texture_coord.x),   f32(ch.texture_coord.y)   }, // { xpos,     ypos + h,   0.0, 0.0 }
            { xpos+w, ypos,   f32(ch.texture_coord.x)+w, f32(ch.texture_coord.y)+h }, // { xpos + w, ypos,       1.0, 1.0 }
            { xpos+w, ypos+h, f32(ch.texture_coord.x)+w, f32(ch.texture_coord.y)   }, // { xpos + w, ypos + h,   1.0, 0.0 }
        }

        gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
        gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(vertices), mem.raw_data(vertices[:]))
        gl.BindBuffer(gl.ARRAY_BUFFER, 0)
        // render quad
        gl.DrawArrays(gl.TRIANGLES, 0, 6)
        // now advance cursors for next glyph (note that advance is number of 1/64 pixels)
        local_x += f32(ch.advance) * scale // bitshift by 6 to get value in pixels (2^6 = 64)
    }
    gl.BindVertexArray(0)
    gl.BindTexture(gl.TEXTURE_RECTANGLE, 0)
}

render_texture :: proc(x: f32,  y: f32, color: glsl.vec3) {
    // activate corresponding render state
    gl.UseProgram(text_program)
    gl.UniformMatrix4fv(text_projection_location, 1, gl.FALSE, ([^]f32)(&text_projection))
    gl.Uniform3f(text_color_location, color.x, color.y, color.z)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindVertexArray(VAO)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

    vertices: [6][4]f32 = {
        // { 0, y,   0,                  f32(texture_height) },
        // { 0, 0,   0,                  0              },
        // { x, 0,   f32(texture_width), 0              },

        // { 0, y,   0,                  f32(texture_height) },
        // { x, 0,   f32(texture_width), 0              },
        // { x, y,   f32(texture_width), f32(texture_height) },


        { 0,                  f32(texture_height), 0,                  0                   },
        { 0,                  0,                   0,                  f32(texture_height) },
        { f32(texture_width), 0,                   f32(texture_width), f32(texture_height) },

        { 0,                  f32(texture_height), 0,                  0                   },
        { f32(texture_width), 0,                   f32(texture_width), f32(texture_height) },
        { f32(texture_width), f32(texture_height), f32(texture_width), 0                   },
    }

    gl.BindTexture(gl.TEXTURE_RECTANGLE, font_texture)
    // update content of VBO memory
    gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(vertices), mem.raw_data(vertices[:]))
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
    // render quad
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
    // now advance cursors for next glyph (note that advance is number of 1/64 pixels)
    gl.BindVertexArray(0)
    gl.BindTexture(gl.TEXTURE_RECTANGLE, 0)
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

	text_projection = mat4Ortho3d(0.0, 640.0, 0.0, 480.0)

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

	llft := lft.make_font(5)
	defer lft.delete_font(llft)
	if err := lft.load_font(llft, freetype, "/usr/share/fonts/source-code-pro/SourceCodePro[wght].ttf"); err != 0 {
		log.fatalf("Failed to load font: %v", err)
	}
	lft.render_font(llft, 36, 92, 92)

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

	text_vertex_shader = gl.CreateShader(gl.VERTEX_SHADER)
	gl.ShaderSource(text_vertex_shader, 1, &text_vertex_shader_text, nil)
	gl.CompileShader(text_vertex_shader)

	text_fragment_shader = gl.CreateShader(gl.FRAGMENT_SHADER)
	gl.ShaderSource(text_fragment_shader, 1, &text_fragment_shader_text, nil)
	gl.CompileShader(text_fragment_shader)

	text_program = gl.CreateProgram()
	gl.AttachShader(text_program, text_vertex_shader)
	gl.AttachShader(text_program, text_fragment_shader)
	gl.LinkProgram(text_program)

	text_projection_location = gl.GetUniformLocation(text_program, "projection")
	text_color_location = gl.GetUniformLocation(text_program, "textColor")
	text_text_location = gl.GetAttribLocation(text_program, "text")
	text_vertex = gl.GetAttribLocation(text_program, "vertex")

	gl.GenVertexArrays(1, &VAO)
	gl.GenBuffers(1, &VBO)
	gl.BindVertexArray(VAO)
	gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * 6 * 4, nil, gl.DYNAMIC_DRAW)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	for !glfw.WindowShouldClose(window) {
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS do glfw.SetWindowShouldClose(window, true)

		width, height := glfw.GetFramebufferSize(window)
		ratio := (f32)(width) / (f32)(height)

		text_projection = mat4Ortho3d(0.0, f32(width), 0.0, f32(height))
		gl.Viewport(0, 0, width, height)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		m := linalg.matrix4_from_euler_angle_z_f32(auto_cast glfw.GetTime())
		p := glsl.mat4Ortho3d(-ratio, ratio, -1, 1, 1, -1)
		mvp := p * m

		gl.UseProgram(program)
		gl.UniformMatrix4fv(mvp_location, 1, gl.FALSE, ([^]f32)(&mvp))
		gl.DrawArrays(gl.TRIANGLES, 0, 3)
		render_text("This is sample text", 10.0, 100.0, 1.0, glsl.vec3{1, 1, 1})
		// render_texture(f32(width), f32(height), glsl.vec3{1, 1, 1})
		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}
