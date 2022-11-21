#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)"
rm -f learn-opengl
/home/jim/projects/Odin/odin build src -out:learn-opengl -vet -debug
