# lua-client

### Setup

1. Install this repo as a Neovim plugin using your plugin manager of choice.
1. Install [LuaJIT](http://luajit.org/install.html)
1. Install [LuaRocks](https://luarocks.org/#quick-start)
1. Install the following rocks:

    - $ luarocks install luv 
    - $ luarcoks install mpack 

## Development 

The development environment requires the following rocks:

- $ luarocks install busted
- $ luarocks install luacheck

The script setup.sh sets up a development environment using [hererocks](https://github.com/mpeterv/hererocks#readme).

## Example

See [garyburd/neols](https://github.com/garyburd/neols#readme).
