
-- run tests
lsc = require("lsc")

print(string.rep("-", 60))
print(_VERSION .. "  -  " .. lsc.VERSION)

require("test.test_core")
require("test.test_misc")
require("test.test_proc")
require("test.test_lio")


