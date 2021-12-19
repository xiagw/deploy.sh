#!/usr/bin/env bash
echo_time_step "golang build..."
go test
go build -o bin/build