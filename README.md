# <div align="center"> a chess engine written in zig </div>

## features
- uci-compatible
- evaluation:
	- hl320 neural net
	- horizontal mirroring
	- pairwise multiplication
- search:
	- iterative deepening
	- aspiration windows
	- mate distance pruning
	- internal iterative reduction
	- reverse futility pruning
	- null move pruning
	- razoring
	- late move pruning / reduction
	- see pruning

## dependency
- zig 0.15.2

## building
```
$ git clone --depth 1 https://github.com/oilsoundsfunny/zin.git
$ cd zin/
$ git submodule update --init --depth 1 --remote
$ zig build --prefix PREFIX --release=safe
```

the binary will be placed in $PREFIX/bin/

