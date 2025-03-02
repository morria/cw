build:
	swift build

build.debug:
	swift build -c debug

run:
	swift run listen

clean:
	swift package clean

test:
	swift test