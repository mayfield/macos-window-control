build: dist
	swiftc src/main.swift -target arm64-apple-macos11 -g -O -o dist/.macos-window-control.arm64
	swiftc src/main.swift -target x86_64-apple-macos11 -g -O -o dist/.macos-window-control.x86_64
	lipo -create dist/.macos-window-control.arm64 dist/.macos-window-control.x86_64 -output dist/macos-window-control

dist:
	mkdir -p dist

clean:
	rm -rf dist
