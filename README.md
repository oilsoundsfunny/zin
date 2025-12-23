# <div align="center"> zin </div>

## features
- uci-compatible
- evaluation:
	- single layer 320hl neural net
	- lazy updates
	- fused updates
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
	- quiet / qs futility pruning
	- late move pruning / reduction
	- see pruning

## dependency
- zig 0.15.2

## building
```
$ git clone --depth 1 https://codeberg.org/oilsoundsfunny/zin
$ cd zin/
$ zig build --prefix PREFIX --release=fast
```

the binary will be placed in $PREFIX/bin/

