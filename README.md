# <div align="center"> a chess engine written in zig </div>

## features
- uci-compatible
- evaluation:
	- smallnet
- search:
	- aspiration windows

## requisites
- git
- zig master

## building
```
$ git clone --depth 1 https://github.com/oilsoundsfunny/zin.git
$ cd zin/
$ git submodule update --init --depth 1 --remote
$ zig build --prefix PREFIX --release=safe
```

the binary will be placed in $PREFIX/bin/

