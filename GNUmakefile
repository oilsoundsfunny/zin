# from: https://github.com/JonathanHallstrom/pawnocchio/blob/dev/Makefile

ifndef EXE
EXE = zin
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
	# TODO: fix avx512 build
	-zig build --release=fast \
		-Dtarget=x86_64-linux-musl \
		-Dcpu=native-avx512f-avx512vnni \
		$(NETWORK)
	@$(MV)
