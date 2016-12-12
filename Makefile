default:
	luacheck --no-color --no-self --formatter plain --std luajit *.lua --exclude-files '*_spec.lua' 
	luacheck --no-color --formatter plain --std luajit+busted  *_spec.lua
	busted .
