local math = require('helers.math')

plugin.func {
  name = 'Sub',
  func = function(args) 
    return math.sub(unpack(args)) 
  end
}
