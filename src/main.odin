package main

import "core:fmt"
import "core:log"
import "cliargs"

main :: proc() {
	context.logger = log.create_console_logger()
	// x: int
	y: struct {
	  a: string `short:"a" long:"a-arg" description:"This is A argument"`,
	  b: int `short:"b" long:"b-arg" description:"This is B argument" default:"123"`,
	  c: i32 `short:"c" long:"c-arg" description:"This is C argument"`,
	  d: f32 `short:"d" long:"d-arg" description:"This is D argument"`,
	  e: struct {
	  	x: bool,
	  	y: bool `short:"y"`,
	  	z: string `short:"z" required:"true"`,
	  } `cmd:"foocmd"`,
	}
	parser: cliargs.argparse
	cliargs.build_parser(&parser, type_of(&y))

	fmt.printf("rt: %v\n", parser)
}
