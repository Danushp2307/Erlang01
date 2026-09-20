#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage:"
    echo "  Server Mode: ./myprogram.sh <LeadingZeros>   [e.g. ./myprogram.sh 4]"
    echo "  Worker Mode: ./myprogram.sh <ServerIP>       [e.g. ./myprogram.sh 192.168.0.26]"
    exit 1
fi

# Change to the directory containing this script
cd "$(dirname "$0")" || exit 1

# Compile if the BEAM file doesn't exist
if [ ! -f "project1.beam" ]; then
    erlc project1.erl || exit 1
fi

# Start Erlang in non-shell mode
erl -noshell -pa . -s project1 main "$@"