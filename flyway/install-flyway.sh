#!/usr/bin/env bash

# Command-line - Command-line tool - Flyway by Redgate • Database Migrations Made Easy.
# https://flywaydb.org/documentation/usage/commandline/#download-and-installation
wget -qO- https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/7.0.3/flyway-commandline-7.0.3-linux-x64.tar.gz | tar xvz && sudo ln -s "$(pwd)"/flyway-7.0.3/flyway /usr/local/bin
