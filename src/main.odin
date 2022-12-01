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
	gl.load_up_to(4, 5, glfw.gl_set_proc_address)

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
