-- Copyright (c) 2021  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

--[[   

LuaLinuxSC  -  a minimal Lua binding to the Linux syscall interface.

This is for Lua 5.3+ only, built with default 64-bit integers



]]


local lsc = require "lsccore"

-- create a default buffer that will be used for system calls 
-- by all lsc submodules, except where noted.
if not lsc.buf then
	lsc.buflen = 32768 -- should be enough for most use cases.
	
	-- allocate the default buffer. No need to test the result
	-- (if allocation fails, newbuffer() raises a Lua error)
	lsc.buf = lsc.newbuffer(lsc.buflen)
end



return lsc

