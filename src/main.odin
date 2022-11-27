package main

import "core:fmt"
import "core:log"
import "cliargs"

main :: proc() {
	context.logger = log.create_console_logger()
	// x: int
	y: struct {
		a:  string `short:"a" long:"a-arg" description:"This is A argument"`,
		b:  int `short:"b" long:"b-arg" description:"This is B argument" default:"123"`,
		c:  i32 `short:"c" long:"c-arg" description:"This is C argument"`,
		d:  f32 `short:"d" long:"d-arg" description:"This is D argument"`,
		d1: f32 `short:"D" long:"d1-arg" description:"This is D1 argument" default:"3.14159"`,
		e:  struct {
			x: bool,
			y: bool `short:"y"`,
			z: string `short:"z" required:"true"`,
		} `cmd:"foocmd"`,
		f:  string `long:"f-arg" description:"This is the F argument" default:"f-arg"`,
		g:  rune `long:"g-arg" description:"This is the G argument" default:"G"`,
	}

	if cliargs.parse_args(
		   "test",
		   "testing things",
		   &y,
		   []string{"-a", "hello", "-c", "999", "foocmd", "-y", "-D", "2.000"},
	   ) {
		fmt.printf("y: %v\n", &y)
		fmt.printf("&y: %p\n", &y)
	}
}
