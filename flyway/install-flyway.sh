#!/usr/bin/env bash

# Command-line - Command-line tool - Flyway by Redgate • Database Migrations Made Easy.
# https://flywaydb.org/documentation/usage/commandline/#download-and-installation

# flyway_ver=7.5.4
flyway_ver="$(curl -sSL 'https://flywaydb.org/documentation/usage/commandline/#download-and-installation' | grep -oP -m1 '(?<=flyway-commandline-)\d+\.\d+\.\d+' | head -n 1)"
wget -qO- https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/"$flyway_ver"/flyway-commandline-"$flyway_ver"-linux-x64.tar.gz | tar xvz && sudo ln -s "$(pwd)"/flyway-"$flyway_ver"/flyway /usr/local/bin
