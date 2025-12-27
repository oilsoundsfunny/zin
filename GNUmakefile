# mostly yoinked from pawnocchio
# https://github.com/JonathanHallstrom/pawnocchio/blob/main/Makefile

ifndef EXE
EXE = zin
endif

ifdef ARCH
CPU = -Dcpu=$(ARCH)
else
CPU =
endif

ifeq ($(OS), Windows_NT)
MV = move .\zig-out\bin\zin.exe $(EXE).exe
else
MV = mv ./zig-out/bin/zin $(EXE)
endif

ifdef EVALFILE
NETWORK = -Devalfile=$(EVALFILE)
else
NETWORK =
endif

default:
	-zig build $(CPU) $(NETWORK) --release=fast
	@$(MV)
