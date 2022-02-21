
local misc = require "lsc.misc"

function test_time()
	local t1 = os.time()
	local t2 = misc.time()
	-- t1 and t2 should _almost_ always be the same value
	assert(math.abs(t1 - t2) <= 1) 
end --time

function test_uname()	
	local ul = assert(misc.uname())
--~ 	for i,u in ipairs(ul) do print(i, u) end
	assert(ul[1] == "Linux")
	assert(ul[5] == "x86_64") -- ATM, lsc is implemented only for x86_64
end --uname

function test_gettime()
	local t, x, y, s, ns, ms, us
	x, y = misc.clock_getres(misc.CLOCK_REALTIME)
--~ 	print('getres', x,y)
	assert(x==0 and y==1) -- on a recent linux, x86_64
	t = os.time()
	x, y = misc.clock_gettime(misc.CLOCK_REALTIME)
	ms = misc.time_msec()
	us = misc.time_usec()
	-- the following tests should be "statically correct" :-)
	-- but they could fail in several ways...
	assert(
		(x == t) 
		or -- less than 10 ms (10,000,000 ns) between both times
		((x == t+1) and y < 10000000)
	)
	assert((ms - t * 1000) <= 1000)
	assert((us - t * 1000000) <= 1000000)
end


test_time()
test_uname()
test_gettime()

print("test_misc: ok.")
