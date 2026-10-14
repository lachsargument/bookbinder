#!/bin/bash
# Builds Core.swift with the self-check and runs it; sample PDFs land in .build/.
set -e
mkdir -p .build
swiftc Core.swift tests/main.swift -o .build/selftest
.build/selftest .build
