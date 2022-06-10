#!/usr/bin/env bash
echo_msg step "golang build..."
go test
go build -o bin/build