.PHONY: build clean clean-bin clean-cache run strip test

.ifndef optimize
optimize	= off
.endif
.ifndef prefix
prefix	= ./zig-out
.endif

bin	= $(prefix)/bin/zin

build:
	zig build \
		-freference-trace \
		--prominent-compile-errors \
		--release=$(optimize) \
		--summary all

clean:	clean-bin clean-cache
clean-bin:
	rm -f $(bin)
clean-cache:
	rm -rf ./.zig-cache

run:
	$(bin)

strip:
	llvm-strip --strip-all-gnu -sx $(bin)

test:
	zig build test \
		-freference-trace \
		--prominent-compile-errors \
		--release=$(optimize) \
		--summary all
