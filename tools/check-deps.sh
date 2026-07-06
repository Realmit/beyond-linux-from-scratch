#!/bin/bash
# Checks for required commands
for cmd in bash gcc make bison gawk m4 wget tar gzip xorriso parted; do
    if ! command -v $cmd &>/dev/null; then
        echo "Missing: $cmd"
    else
        echo "$cmd"
    fi
done