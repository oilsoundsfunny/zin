# mostly yoinked from pawnocchio
# https://github.com/JonathanHallstrom/pawnocchio/blob/main/Makefile

.DEFAULT_GOAL	:= default

net:
	git submodule update --init --depth 1 --remote

ifndef	EXE
EXE	= zin
endif

ifeq	($(OS), Windows_NT)
MV	= move .\zig-out\bin\$(EXE).exe $(EXE).exe
else
MV	= mv ./zig-out/bin/$(EXE) $(EXE)
endif

ifdef	EVALFILE
NET	= -Dnet=$(EVALFILE)
else
NET	=
endif

default:	net
	zig build -Dname=$(EXE) $(NET) --release=fast
	@$(MV)
