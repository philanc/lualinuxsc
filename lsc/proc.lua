-- Copyright (c) 2022  Phil Leblanc  -- see LICENSE file
-- ---------------------------------------------------------------------

--[[   

lsc.proc  - process-related functions

--- system calls

getpid()
getppid()	
getcwd()
chdir()	

kill()
fork()
waitpid()
execve()

--- utilities

msleep()    sleep for x milliseconds (wraps nanosleep())
		

caveats:
** this is implemented for and tested only on x86_64. **
** this doesn't support multi-threaded programs. **


]]

local lsc = require "lsc"
local nr = require "lsc.nr"

local gets, puts = lsc.getstr, lsc.putstr
local geti, puti = lsc.getuint, lsc.putuint
local syscall, errno = lsc.syscall, lsc.errno


local proc = {} -- the lsc.proc module

function proc.getpid()
	return lsc.syscall(nr.getpid)
end

function proc.getppid()
	return lsc.syscall(nr.getppid)
end

function proc.getcwd()
	local buf, buflen = lsc.buf, lsc.buflen
	local r, eno = syscall(nr.getcwd, buf, buflen)
	if r then return gets(buf) else return nil, eno end
end

function proc.chdir(path)
	local buf = lsc.buf
	puts(buf, path, 0)
	return syscall(nr.chdir, buf)
end

function proc.msleep(ms)
	-- suspend the execution for ms milliseconds
	--
	-- built with nanosleep(2)
	-- argument is a stuct timespec {tv_sec:long, tv_nsec:long}
	-- Note: the nanosleep optional argument (remaining time in case 
	-- of interruption) is not used/returned. 
	local buf = lsc.buf
	puti(buf, ms // 1000, 8) -- seconds
	puti(buf+8, (ms % 1000) * 1000000, 8) -- nanoseconds
	return syscall(nr.nanosleep, buf)
end

function proc.kill(pid, sig)
	-- see kill(2)
	return syscall(nr.kill, pid, sig)
end

function proc.fork()
	-- !! doesn't support multithreading !!
	return syscall(nr.fork)
end

function proc.waitpid(pid, opt)
	-- wait for state changes in a child process (see waitpid(2))
	-- return pid, status
	-- pid, opt and status are integers
	-- (for status consts and macros, see sys/wait.h)
	--	exitstatus: (status & 0xff00) >> 8
	--	termsig: status & 0x7f
	--	coredump: status & 0x80
	-- pid and opt are optional:
	-- pid default value is -1 (wait for any child - same as wait())
	-- pid=0: wait for any child in same process group
	-- pid=123: wait for child with pid 123
	-- opt=1 (WNOHANG) => return immediately if no child has exited.
	-- default is opt=0
	--
	-- !! doesn't support multithreading !!
	--
	pid = pid or -1
	opt = opt or 0
	local status, eno
	local buf = lsc.buf
	pid, eno = syscall(nr.wait4, pid, buf, opt)
	if pid then
		status = geti(buf, 4)
		return pid, status
	else
		return nil, eno
	end
end

------------------------------------------------------------------------
-- execve


-- utilities to convert between a Lua list of string and a list of
-- C strings as used for example by `argv` and `environ` ("csl")

--[[ a C string list is stored in a buffer as follows:

starting at address b:
	addr of string1 (a char *)
	addr of string2
	...
	addr of stringN
	0  (a null ptr)
	string1 \0 (a null byte must be  appended at end of string)
	string2 \0
	... 
	stringN \0
	
]]

function proc.make_csl(a, alen, t)
	-- create a C string list (csl) in memory at address a.
	-- the csl must fit between a and a+alen. if not, the 
	-- function returns nil, errmsg
	-- strings are taken for the list part of Lua table t.
	-- return a, len on success or nil, errmsg. len is the actual 
	-- length of the csl in memory
	--
	local psz = 8 -- size of a pointer
	local len = (#t + 1) * psz  -- space used for the string pointers
	-- store the strings and check the total length of the future csl
	local pa = a -- address of the pointer to the first string
	for i, s in ipairs(t) do
		local ts = type(s)
		if ts == "string" then --nothing to do
		elseif ts == "number" then s = tostring(s)
		else error("make_csl: list element not string or number")
		end
		assert(type(s) == "string")
		sa = a + len -- -- address of the first string chars
		len = len + #s + 1  -- add 1 for the '\0' terminator
		if len > alen then return nil, "not enough space" end
		puts(sa, s, true) -- write s, add a '\0'
		puti(pa, sa, psz)
		pa = pa + psz
	end
	return a, len
end

function proc.parse_csl(a)
	-- parse a C string list (csl) at address a
	-- return a Lua table containing the list of strings
	--
	local psz = 8 -- size of a pointer
	local t = {}  -- the Lua table to be filled by strings
	while true do
		local sa = geti(a, psz)
		if sa == 0 then break end
		local s = gets(sa)
		table.insert(t, s)
		a = a + psz
	end
	return t
end

function proc.csl_size(t)
	-- return the memory size required to store a list 
	-- of strings (a lua table) as a csl
	-- (this is the total size of strings, plus pointers 
	-- and null terminators)
	local psz = 8 -- size of a pointer
	local len = (#t + 1) * psz  -- space used for the string pointers	
	for i, s in ipairs(t) do
		len = len + #s + 1 -- +1 for null terminator
	end
	return len
end
	

function proc.execve_raw(exepath, argv_addr, env_addr)
	-- Return nil, eno (the errno value set by the system call)
	-- This function does not return on success.
	-- argv_addr is the address of the argument list (as a csl).
	-- env_addr is the address of the environment (as a csl)
	local buf = lsc.buf
	return syscall(nr.execve, puts(buf, exepath), argv_addr, env_addr)
end

function proc.execve(exepath, argv, env)
	-- this is a convenience function wrapping execve_raw()
	-- argv is a lua list of string. First element should be 
	-- the program path
	-- env is a lua table {name:string = value:string, ...}
	-- a buffer is allocated and the csl are built before execve
	-- if env is nil, the current environment is used
	-- if argv is nil, a list with only the program path is used.
	-- Return nil, eno (the errno value set by the system call)
	-- This function does not return on success.
	--
	local r, eno, errmsg
	local argv_addr, env_addr
	local argv_len, env_len
	-- prepare argv
	argv = argv or {exepath}
	argv_len = proc.csl_size(argv)
	argv_addr = assert(lsc.newbuffer(argv_len))
	assert(proc.make_csl(argv_addr, argv_len, argv))
	-- prepare env
	if env then
		-- create a list of "name=value" strings
		envl = {}
		for name, value in pairs(env) do
			table.insert(envl, 
				tostring(name) .. "=" .. tostring(value))
		end
		-- create the env csl
		env_len = proc.csl_size(envl)
		env_addr = assert(lsc.newbuffer(env_len))
		assert(proc.make_csl(env_addr, env_len, envl))
		
	else    -- env is nil: use the current environment
		env_addr = lsc.environ()
	end
	-- call execve
	r, eno = proc.execve_raw(exepath, argv_addr, env_addr)
	-- here, execve has failed
	-- deallocate buffers as needed
	lsc.freebuffer(argv_addr)
	if not env then lsc.freebuffer(env_addr) end
	return r, eno
end
	
	

------------------------------------------------------------------------
return proc

