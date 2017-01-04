expose('require uv once to prevent segfault', function()
  require('luv')
end)

local neovim = require('neovim')
local plugin = require('plugin')

describe('plugin host', function()
  local nvim
  local p1 = 'testdata/rplugin/lua/p1.lua'

  setup(function()
    nvim = neovim.new_child('nvim', {'--embed', '-u', 'NORC'})
  end)

  teardown(function()
    if nvim then
      nvim:close()
    end
  end)

  it('can load scripts', function()
    local host = plugin.new_host(nvim)
    local specs, handlers = host:get_plugin(p1):load_script(p1)
    assert.are.same({
      {
        name = 'Hello',
        type = 'command',
        sync = true,
        opts = {x = 0},
      },
      {
        name = 'Add',
        type = 'function',
        sync = true,
        opts = {x = 0},
      },
    }, specs)
    assert.is.equal('function', type(handlers[':command:Hello']))
    assert.is.equal('function', type(handlers[':function:Add']))
  end)

  it('works with nvim', function()
    local path = 'testdata/rplugin/lua/p1.lua'
    local channel = nvim:get_api_info()[1]
    local host = plugin.new_host(nvim)
    local specs, _ = host:get_plugin(p1):load_script(p1)
    nvim:call('remote#host#RegisterPlugin', 'lua', path, specs)
    nvim:call('remote#host#Register', 'lua', '*.lua', channel)
    assert.is.equal(3, nvim:call('Add', 1, 2))
  end)

  it('isolates global variables', function()
    local host = plugin.new_host(nvim)
    local p = host:get_plugin(p1)
    p:load_script(p1)
    assert.is.equal('global', p.env.example_globar_var)
  end)

end)
