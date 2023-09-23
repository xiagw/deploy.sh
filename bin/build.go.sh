#!/usr/bin/env bash
_msg step "golang build..."
go test
go build -o bin/build