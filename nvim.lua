local uv = require('luv')
local mpack = require('mpack')
local uvutil = require('uvutil')

local nvimError = {}
nvimError.__index = nvimError
function nvimError.new(message) return setmetatable({message=message}, nvimError) end
function nvimError:__tostring() return self.message end

local Nvim = {}

function Nvim.new(w, r)
  local nvim = setmetatable({
      _w = w,
      _r = r,
      _closed = false,
      _proc = false,
      handlers = {},
    }, Nvim)

  -- Setup extension types
  local packext, unpackext = {}, {}
  for type, i in pairs{buf = 0, win = 1, tabpage = 2} do
    local prefix = 'nvim_' .. type .. '_'
    local mt = {
      __tostring = function(self) return type .. ' ' .. tostring(self.id) end,
      __eq = function(self, other) return self.id == other.id end,
      __index = function(_, k) return function(...) return nvim:request_level(3, prefix .. k, ...) end end,
    }
    packext[mt] = function(o) return i, mpack.pack(o.id) end
    unpackext[i] = function(_, s) return setmetatable({id=mpack.unpack(s)}, mt) end
    nvim[type] = function(_, id) return setmetatable({id=id}, mt) end
  end

  nvim._pack = mpack.Packer({ext = packext})
  nvim._session = mpack.Session({unpack = mpack.Unpacker({ext = unpackext})})
  uv.read_start(r, function(err, chunk) return nvim:_on_read(err, chunk) end)
  return nvim
end

function Nvim:close()
  if self._closed then
    return
  end
  self._closed = true
  self._r:read_stop()
  local waiters = {}
  local cb
  cb, waiters[#waiters+1] = uvutil.cb_wait()
  self._w:close(cb)
  cb, waiters[#waiters+1] = uvutil.cb_wait()
  self._r:close(cb)
  if self._proc then
    cb, waiters[#waiters+1] = uvutil.cb_wait()
    self._proc:close(cb)
  end
  for _, wait in pairs(waiters) do
    wait()
  end
end

function Nvim.new_child(cmd, args, env)
  local stdin, stdout = uv.new_pipe(false), uv.new_pipe(false)
  local proc, pid, nvim
  proc, pid = uv.spawn(cmd, {
    stdio = {stdin, stdout, 2},
    args = args,
    env = env,
  }, function()
    if nvim then
      nvim:close()
    end
  end)
  if not proc then
    stdin:close()
    stdout:close()
    error(pid)
  end
  nvim = Nvim.new(stdin, stdout)
  nvim._proc = proc
  return nvim
end

function Nvim.new_stdio()
  local stdin, stdout = uv.new_pipe(false), uv.new_pipe(false)
  stdin:open(0)
  stdout:open(1)
  return Nvim.new(stdout, stdin)
end

function Nvim:__index(k)
  local x = rawget(getmetatable(self), k)
  if x ~= nil then
    return x
  end
  return function(v, ...) return v:request_level(2, 'nvim_' .. k, ...) end
end

local function errorHandler(e)
  if getmetatable(e) ~= nvimError then
    io.stderr:write(tostring(e), '\n', debug.traceback(), '\n')
  end
  return e
end

function Nvim:_on_request(id, method, args)
  local handler = self.handlers[method]
  if not handler then
    self._w:write(self._session:reply(id) .. self._pack("method not found") .. self._pack(mpack.NIL))
    return
  end
  uvutil.add_idle_call(coroutine.resume, {coroutine.create(function()
    local ok, result = xpcall(handler, errorHandler, unpack(args))
    local err, resp = mpack.NIL, mpack.NIL
    if ok then
      if result ~= nil then
        resp = result
      end
    else
      err = "Internal Error"
      if getmetatable(result) == nvimError then
	err = result.message
      end
      err = {0, err}
    end
    self._w:write(self._session:reply(id) .. self._pack(err) .. self._pack(resp))
  end)})
end

function Nvim:_on_notification(_, method, args)
  -- TODO run notifications in a single coroutine to ensure in order execution.
  local handler = self.handlers[method]
  if not handler then
    return
  end
  uvutil.add_idle_call(coroutine.resume, {coroutine.create(function() xpcall(handler, errorHandler, unpack(args)) end)})
end

function Nvim:_on_response(cb, err, result)
  if err == mpack.NIL then
    cb(true, result)
    return
  end

  if type(err) == 'table' and #err == 2 and type(err[2]) == 'string' then
    if err[1] == 0 then
      err = "exception: " .. err[2]
    elseif err[1] == 1 then
      err =  "validation: " .. err[2]
    end
  end
  cb(false, err)
end

function Nvim:_on_read(err, chunk)
  if err then
    error(err)
  end
  if not chunk then
    self:close()
    return
  end
  local pos, len = 1, #chunk
  while pos <= len do
    local mtype, id_or_cb, method_or_error, args_or_result
    mtype, id_or_cb, method_or_error, args_or_result, pos = self._session:receive(chunk, pos)
    if mtype ~= nil then
      -- get from metatable avoid accidental call to constructed methods
      local f = getmetatable(self)['_on_' .. mtype]
      if not f then
        error('unknown mpack receive type: ' .. mtype)
      end
      f(self, id_or_cb, method_or_error, args_or_result)
    end
  end
end

function Nvim:request_async(method, cb, ...)
  self._w:write(self._session:request(cb) .. self._pack(method) .. self._pack({...}))
end

function Nvim:request_level(level, method, ...)
  local cb, wait = uvutil.cb_wait()
  self:request_async(method, cb, ...)
  local ok, result = wait()
  if not ok then
    error(result, level)
  end
  return result
end

function Nvim:request(method, ...)
  return self:request_level(3, method, ...)
end

function Nvim:notify(method, ...)
  self._w:write(self._session:notify() .. self._pack(method) .. self._pack({...}))
end

-- error returns message as error to nvim.
function Nvim.error(message, level)
  error(nvimError.new(message), level)
end

function Nvim:call(f, ...)
  return self:request_level(2, 'nvim_call_function', f, {...})
end

return Nvim
