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
import lft "font"

Vector2i32 :: distinct [2]i32

freetype: ft.Library

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

vertices: []vertex = {{-0.6, -0.4, 1, 0, 0}, {0.6, -0.4, 0, 1, 0}, {0, 0.7211, 0, 0, 1}}

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

	llft := lft.make_font(5)
	defer lft.delete_font(llft)
	// if err := lft.load_font(llft, freetype, "/usr/share/fonts/source-code-pro/SourceCodePro[wght].ttf"); err != 0 {
	if err := lft.load_font(
		llft,
		freetype,
		"/usr/share/fonts/fira-sans-condensed/FiraSansCondensed-Regular.ttf",
	); err != 0 {
		log.fatalf("Failed to load font: %v", err)
	}
	lft.render_font(llft, 36, 92, 92)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	for !glfw.WindowShouldClose(window) {
		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS do glfw.SetWindowShouldClose(window, true)

		width, height := glfw.GetFramebufferSize(window)
		ratio := (f32)(width) / (f32)(height)

		llft.projection = lft.mat4Ortho3d(0.0, f32(width), 0.0, f32(height))
		gl.Viewport(0, 0, width, height)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		m := linalg.matrix4_from_euler_angle_z_f32(auto_cast glfw.GetTime())
		p := glsl.mat4Ortho3d(-ratio, ratio, -1, 1, 1, -1)
		mvp := p * m

		gl.UseProgram(program)
		gl.UniformMatrix4fv(mvp_location, 1, gl.FALSE, ([^]f32)(&mvp))
		gl.DrawArrays(gl.TRIANGLES, 0, 3)
		lft.draw_text(
			llft,
			"This :iiii:s: IIISISIS sample text",
			10.0,
			100.0,
			36.0,
			glsl.vec3{1, 1, 1},
		)
		// render_texture(f32(width), f32(height), glsl.vec3{1, 1, 1})
		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}
