
-- simple tests for module lsc.io

local lsc = require "lsc"
local lio = require "lsc.lio"
local util = require "lsc.util"
local proc = require "lsc.proc"

------------------------------------------------------------------------

local function test_file()
	-- use open, read, write, close, dup2
	--
	local fname = "zzlio"
	local str = "HELLO WORLD!"
	local mode = tonumber("600", 8) -- "rw- --- ---"
	local fd, fd2, fd3, r, eno, s
	fd = assert(lio.open(fname, lio.O_CREAT | lio.O_RDWR, mode))
	fd2, eno = lio.open(fname, lio.O_CREAT | lio.O_RDWR | lio.O_EXCL, mode)
	assert(not fd2 and eno == 17) -- 17=EEXIST
	local r, eno
	r = lio.write(fd, str)
	assert(r == #str)
	assert(util.fget(fname) == str)
	assert(lio.close(fd))
	--
	-- now reopen, dup2, ftruncate, lseek and read from the new fd
	-- open as writable (if readonly, ftruncate fails wih EINVAL)
	fd2 = assert(lio.open(fname, lio.O_RDWR))
	fd3 = assert(lio.dup2(fd2, fd2+10)) -- assume fd2+10 does not exist
	assert(fd3 == fd2+10)
	assert(lio.close(fd2))
	assert(lio.ftruncate(fd3, 5)) -- keep only 5 bytes
	r = assert(lio.lseek(fd3, 2)) -- set file position before 3rd byte
	assert(r == 2) 
	s = assert(lio.read(fd3)) -- read 3 bytes ("LLO")
	assert(s == str:sub(3,5)) 
	assert(lio.close(fd3))
	--
	-- stat
	t = {}
	assert(lio.stat(fname, t) == t)
	t0 = os.time()
	assert(math.abs(t.atime - t0) <= 1)
	assert(math.abs(t.ctime - t0) <= 1)
	assert(math.abs(t.mtime - t0) <= 1)
	assert(atime_ns == ctime_ns and atime_ns == mtime_ns)
	assert(t.nlink == 1)
	assert(t.size == 5)
	assert(t.type == "r")
	assert(util.n2o(t.perm) == "0600")
	--
	-- remove file
	assert(lio.unlink(fname))
	-- check that file is no longer there:
	r, eno = lio.stat(fname)
	assert(not r and eno == 2) -- 2 = ENOENT 
end--test_file

local function test_mkdir()
	local r, eno
	local dname = "zzdir"
	local mode = util.o2n"700"
	assert(lio.mkdir(dname, mode))
	local t = lio.stat(dname)
	assert(t.type == "d" and util.n2o(t.perm) == "0700")
	assert(lio.rmdir(dname))
end--test_mkdir

local function test_pipe()
	local r, eno, pid, status
	local p0, p1 = lio.pipe2() -- should be 3 and 4
	assert(p0==3 and p1==4, "fds not 3, 4 - any redirection?")
	assert(lio.write(p1, "HELLO"))
	local s = assert(lio.read(p0))
	assert(s == "HELLO")
	local pid = assert(proc.fork())
	if pid == 0 then -- child
		lio.write(p1, "HELLO from child")
		-- close child end of the pipe
		assert( lio.close(p0) and lio.close(p1), 
			"error closing pipe in child")
		os.exit()
	else -- parent
		s, eno = assert(lio.read(p0))
		assert(s == "HELLO from child")
		assert(lio.close(p0)) -- close parent end of the pipe
		assert(lio.close(p1)) -- id.
		assert(proc.waitpid())
	end
end--test_pipe


function test_dir()
	local function find1(t, s)
		-- search a string in a list
		for i,v in ipairs(t) do
			if v == s then return true end 
		end
		return false
	end
	local function find2(t, sa, sb)
		-- search a pair of strings in a list of pairs
		for i,v in ipairs(t) do
			if (v[1] == sa) and (v[2] == sb) then return true end
		end
		return false
	end
	--
	assert(os.execute[[
		rm -rf ./tzz
		mkdir -p  ./tzz/dd
		cd ./tzz
		touch fa fb
		ln -s fa fl
		mkfifo fi
	]])
	local d = assert(lio.ls("./tzz"))
	assert(find1(d, "fb"))
	assert(find1(d, "fl"))
	assert(find1(d, "dd"))
	--
	local d2 = assert(lio.ls2("./tzz"))
	assert(find2(d2, "dd", "d"))
	assert(find2(d2, "fl", "l"))
	assert(find2(d2, "fa", "r"))
	assert(find2(d2, "fi", "f"))
	assert(os.execute[[ rm -rf ./tzz ]])
		
end--test_dir

test_file()
test_pipe()
test_dir()
test_mkdir()

print("test_lio: ok.")

