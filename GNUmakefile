# mostly yoinked from pawnocchio
# https://github.com/JonathanHallstrom/pawnocchio/blob/main/Makefile

.DEFAULT_GOAL	:= default

ifndef	EXE
EXE	= zin
endif

ifeq	($(OS), Windows_NT)
MV	= move .\zig-out\bin\zin.exe $(EXE).exe
else
MV	= mv ./zig-out/bin/zin $(EXE)
endif

net:
	-git submodule update --init --depth 1 --recursive

ifdef	EVALFILE
NET	= -Dnet=$(EVALFILE)
else
NET	=
endif

default:	net
	-zig build $(NET) --release=fast
	@$(MV)
