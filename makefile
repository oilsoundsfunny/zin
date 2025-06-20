.PHONY: build clean clean-bin clean-cache clean-log run selfplay strip test

.ifndef optimize
optimize	= off
.endif
.ifndef prefix
prefix	= ./zig-out
.endif

name	= zin
bin	= $(prefix)/bin/$(name)

time	!= TZ=UTC date "+%y%m%d-%H%M%S"

build:
	zig build \
		-freference-trace \
		--prominent-compile-errors \
		--release=$(optimize) \
		--summary all

clean:	clean-bin clean-cache clean-log
clean-bin:
	rm -f $(bin)
clean-cache:
	rm -rf .zig-cache
clean-log:
	rm -f *.core *.log

run:
	$(bin)

selfplay:
	fastchess \
		-engine cmd=$(bin) name="$(name)1" \
		-engine cmd=$(bin) name="$(name)2" \
		-each tc=1+0.01 option.Hash=128 option.Threads=2 \
		-openings file=books/noob_5moves.epd format=epd order=random \
		-rounds 10 \
		-log file=fastchess-$(time).log \
		compress=false level=trace engine=true

strip:
	llvm-strip --strip-all-gnu -sx $(bin)

test:
	zig build test \
		-freference-trace \
		--prominent-compile-errors \
		--release=$(optimize) \
		--summary all
