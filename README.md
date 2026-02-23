# <div align="center"> zin </div>

## features
- uci-compatible
- evaluation:
	- (768hm->384pw)x2->1x8 neural net
	- fused+lazy updates
- search:
	- iterative deepening
	- aspiration windows
	- mate distance pruning
	- internal iterative reduction
	- reverse futility pruning
	- null move pruning
	- razoring
	- quiet / qsearch futility pruning
	- late move pruning / reduction
	- see pruning

## dependency
- zig 0.15.2

## building
```
$ git clone --depth 1 https://codeberg.org/oilsoundsfunny/zin.git
$ cd zin
$ zig build --prefix PREFIX --release=fast
```

the binary will be at $PREFIX/bin/zin

