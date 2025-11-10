.DEFAULT_GOAL	:= default

net:
	git submodule update --init --depth 1 --remote

ifdef	EVALFILE
NET	= -Dnet=$(EVALFILE)
else
NET	=
endif

default:	net
	zig build $(NET) --prefix . --release=fast
