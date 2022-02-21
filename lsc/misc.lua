-- Copyright (c) 2022  Phil Leblanc  -- see LICENSE file
-- ---------------------------------------------------------------------

--[[   

lsc.misc  -  misc functions (mostly time-related)


--- System calls
	
time()	
clock_getres()
clock_gettime()
uname()

	
--- Utilities

time_msec()     return the current time in milliseconds
time_usec()     return the current time in microseconds
	

caveats:
** this is implemented for and tested only on x86_64. **
** this doesn't support multi-threaded programs. **


]]

local lsc = require "lsc"
local nr = require "lsc.nr"

local gets, puts = lsc.getstr, lsc.putstr
local geti, puti = lsc.getuint, lsc.putuint
local syscall, errno = lsc.syscall, lsc.errno


local misc = {} -- the lsc.misc module

------------------------------------------------------------------------
-- time-related syscalls

--- time(2)

function misc.time()
	-- return the number of seconds since the Unix epoch
	-- should be ~ the same as Lua os.time()
	return syscall(nr.time)
end


--- clock_getres(2), clock_gettime(2) -- constants from time.h

misc.CLOCK_REALTIME = 0
misc.CLOCK_MONOTONIC = 1
misc.CLOCK_MONOTONIC_RAW = 4

function misc.clock_getres(clockid)
	-- system call writes a stuct timespec {tv_sec:long, tv_nsec:long}
	-- in buffer
	local buf = lsc.buf
	local r, eno = syscall(nr.clock_getres, clockid, buf)
	if not r then return nil, eno end
	return geti(buf, 8), geti(buf+8, 8)
end
	
function misc.clock_gettime(clockid)
	-- system call writes a stuct timespec {tv_sec:long, tv_nsec:long}
	local buf = lsc.buf
	local r, eno = syscall(nr.clock_gettime, clockid, buf)
	if not r then return nil, eno end
	return geti(buf, 8), geti(buf+8, 8)
end

-- utility functions based on clock_gettime(CLOCK_REALTIME is 0)

function misc.time_msec()
	-- same as os.time, but return time in milliseconds
	-- (number of milliseconds since the Unix epoch)
	local buf = lsc.buf
	local r, eno = syscall(nr.clock_gettime, 0, buf)
	if not r then return nil, eno end
	local s, ns = geti(buf, 8), geti(buf+8, 8)
	return s * 1000 + ns // 1000000
end
	
function misc.time_usec()
	-- same as os.time, but return time in microseconds
	-- (number of microseconds since the Unix epoch)
	local buf = lsc.buf
	local r, eno = syscall(nr.clock_gettime, 0, buf)
	if not r then return nil, eno end
	local s, ns = geti(buf, 8), geti(buf+8, 8)
	return s * 1000000 + ns // 1000
end
	


--

--[[ uname(2)  

the uname syscall returns system  information  in the following structure

   struct utsname {
       char sysname[];    /* Operating system name (e.g., "Linux") */
       char nodename[];   /* Name within "some implementation-defined
			     network" */
       char release[];    /* Operating system release (e.g., "2.6.28") */
       char version[];    /* Operating system version */
       char machine[];    /* Hardware identifier */
   #ifdef _GNU_SOURCE
       char domainname[]; /* NIS or YP domain name */
   #endif
   };
   
   in a recent linux, with system call __NR_UNAME (nr.uname), 
   all fields should be 65 bytes, incl. null terminator
   
]]

function misc.uname()
	-- return a Lua list with fields `sysname` to `machine`
	--
	local buf = lsc.buf
	local r, eno = syscall(nr.uname, buf)
	-- b contains a struct utsname (see above)
	if not r then return nil, eno end
	ul = {}
	for i = 0, 4 do
		table.insert(ul, gets(buf + 65*i))
	end
	return ul
end--uname



------------------------------------------------------------------------
return misc

