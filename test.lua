local class = require 'middleclass'
local Foo = class('Foo')
function Foo:initialize(args) self.x = args.x end
local foo = Foo:new{ x = 42 }
print('foo.x =', foo.x)