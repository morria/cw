SAMPLE ?= Tests/cwTests/samples/sample_12_600_30_CQ_CQ_CQ_DE_W2ASM_K.wav

build:
	swift build

build.debug:
	swift build -c debug

run:
	swift run listen $(SAMPLE)

clean:
	swift package clean

test:
	swift test
