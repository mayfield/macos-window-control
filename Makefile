build:
	mkdir -p dist
	swiftc -v src/main.swift -target arm64-apple-macos10.15 -O -o dist/macos-window-control.arm64
	swiftc -v src/main.swift -target x86_64-apple-macos10.15 -O -o dist/macos-window-control.x86_64
	strip dist/*
