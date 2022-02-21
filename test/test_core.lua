
-- test lsccore

local lsc = require "lsc"
local syscall = lsc.syscall

local nr = require "lsc.nr"



local t1 = os.time()
local t2 = syscall(nr.time)
-- t1 and t2 should _almost_ always be the same value
assert(t1 - t2 <= 1) 

------------------------------------------------------------------------
-- test buffer/memory functions

local b, b1, i, j, i1, j1, r, s

b = lsc.newbuffer(1024)
i, j = 123456, 789
lsc.putuint(b, i, 8)
lsc.putuint(b+8, j, 8)
s = lsc.getstr(b, 16)
i1,j1 = string.unpack("I8I8", s)
assert(i==i1 and j==j1)

i, j = 99, 1001
lsc.putuint(b, i, 1)
lsc.putuint(b+1, j, 2)
s = lsc.getstr(b, 16)
i1,j1 = string.unpack("I1I2", s)
assert(i==i1 and j==j1)

b1 = lsc.newbuffer(1024)
lsc.putstr(b1, string.pack("I8I8", i, j))
i1 = lsc.getuint(b1, 8)
j1 = lsc.getuint(b1+8, 8)
assert(i==i1 and j==j1)

lsc.putstr(b, "AAAAAAAAAA")
lsc.zero(b, 100)
assert(lsc.getstr(b, 100) == string.rep('\0', 100))

r = lsc.syscall(nr.getcwd, b, 1000)
s = lsc.getstr(b)
print("getcwd: " .. s)

lsc.freebuffer(b)
lsc.freebuffer(b1)

------------------------------------------------------------------------
print("test_core: ok.")
