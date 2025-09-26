# <div align="center"> a chess engine written in zig </div>

## features
- uci-compatible
- evaluation:
	- simple psqts
- search:
	- aspiration windows
	- null move pruning

## requisites
- git
- zig master

## building
```
$ git clone --depth 1 https://github.com/oilsoundsfunny/zin.git
$ cd zin/
$ zig build --prefix PREFIX --release=safe
```

the binary will be placed in $PREFIX/bin/

