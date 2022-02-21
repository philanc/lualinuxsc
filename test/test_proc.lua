local lsc = require "lsc"
local proc = require "lsc.proc"
local util = require "lsc.util"

------------------------------------------------------------------------

function test_chdir()
	-- test chdir, getcwd
	local path, here, eno
	local tmp = "/tmp"
	here = assert(proc.getcwd())
	assert(proc.chdir(tmp))
	assert(proc.getcwd() == tmp)
	-- return to initial dir
	assert(proc.chdir(here))
	assert(proc.getcwd() == here)
end

function test_fork()	
	-- test fork, getpid, getppid, waitpid, kill
	--
	local pid, childpid, parentpid, eno
	parentpid = proc.getpid()
	
	pid = assert(proc.fork())
	if pid == 0 then -- child
		assert(parentpid == proc.getppid())
		os.exit(3)
	else -- parent
		childpid = pid
		-- wait for child to exit
		pid, status = proc.waitpid()
		assert(pid == childpid)
		-- extract exit status, signal and coredump 
		-- indicator from status:
		exit = (status & 0xff00) >> 8
		sig = status & 0x7f
		core = status & 0x80
--~ 		print("  status => exit, sig, coredump =>", exit, sig, core)
		-- child has exited with os.exit(3), so:
		assert(exit==3 and sig==0 and core==0)
	end
	--
	-- now fork the process and try to interrupt the child:
	
	-- 		
	pid, eno = assert(proc.fork())
	if pid == 0 then -- child
		assert(parentpid == proc.getppid())
		-- do not exit before being terminated by parent
		proc.msleep(5000) -- 5 sec is more than enough!
	else -- parent
		childpid = pid
		proc.kill(pid, 15) -- interrupt child with SIGTERM (15)
		pid, status = proc.waitpid()
		assert(pid == childpid)
		-- extract exit status, signal and coredump 
		-- indicator from status:
		exit = (status & 0xff00) >> 8
		sig = status & 0x7f
		core = status & 0x80
--~ 		print("  status => exit, sig, coredump =>", exit, sig, core)
		-- child has been sent signal 15 so:
		assert(exit==0 and sig==15 and core==0)
	end
end

local function test_csl()
	-- test make_csl() and parse_csl()
	local b, blen = lsc.buf, lsc.buflen
	local sl = {"abc", "", "defg", "", string.rep('A', 1000)}
	local b1, em = proc.make_csl(b, blen, sl)
	assert(b1, em)
	c = lsc.getstr(b, 100)
	-- test parse_csl()
	r, em = proc.parse_csl(b, blen, sl)
	assert(r, em)
	-- assert r eq sl
	for k, v in pairs(sl) do assert(sl[k] == r[k]) end
	for k, v in pairs(r) do assert(sl[k] == r[k]) end
end

local function test_execve()
	local r, eno
	if assert(proc.fork()) == 0 then --child
		r, eno = proc.execve("/bin/sh"
		   , { "/bin/sh", "-c", "env >zzexecve 2>&1", } --argv
		   , {AAA="AAAVALUE", ZZZ="ZZZVALUE"} --env
		   )
		assert(r, eno) -- executed only if execve failed
	else -- parent
		assert(proc.waitpid())
		local env = assert(util.fget("zzexecve")
			, "'env' redirection error"
			)
		r = env:find("AAA=AAAVALUE\n") and env:find("ZZZ=ZZZVALUE\n")
		os.remove("zzexecve")
		assert(r, "environment content error")
	end
end

test_chdir()
test_fork()
test_csl()
test_execve()

print("test_proc: ok.")
