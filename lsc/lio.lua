-- Copyright (c) 2022  Phil Leblanc  -- see LICENSE file
-- ---------------------------------------------------------------------

--[[   

lsc.lio -- Linux I/O: files, directories and filesystems functions:

--- system calls

open, close, read, write
ftruncate
pipe2, dup2
ioctl
stat, lstat
mount, umount

- todo:

poll



--- utilities

dirmap      map a function over the content of a directory
            (a wrapper around the getdents64() system call)

+ various utilities to access content of a directory and stat results


caveats:
** this is implemented for and tested only on x86_64. **
** this doesn't support multi-threaded programs. **


]]

local lsc = require "lsc"
local nr = require "lsc.nr"

local gets, puts = lsc.getstr, lsc.putstr

local geti, puti = lsc.getuint, lsc.putuint
local syscall, errno = lsc.syscall, lsc.errno


local lio = {	 -- the lsc.lio module. 

	-- some useful constants 
	--
	-- open / fd flags -- from musl asm-generic/fcntl.h
	O_RDONLY = 0x00000000,
	O_WRONLY = 0x00000001,
	O_RDWR = 0x00000002,
	O_CREAT = 0x00000040,
	O_EXCL = 0x00000080,
	O_TRUNC = 0x00000200,
	O_APPEND = 0x00000400,
	O_NONBLOCK = 0x00000800,
	O_DIRECTORY = 0x00010000,
	O_CLOEXEC = 0x00080000,
	--	
	-- fcntl
	F_GETFD = 0x00000001,
	F_SETFD = 0x00000002,
	F_GETFL = 0x00000003,
	F_SETFL = 0x00000004,
	--
	} --lio constants
------------------------------------------------------------------------

function lio.fcntl()
	--see: man 2 fcntl
	return syscall(nr.fcntl, fd, cmd, arg)
end

-- two frequent use cases of fcntl are to set the CLOEXEC and NONBLOCK flags
-- they provided with their own functions below: 

function lio.set_cloexec(fd)
	local FD_CLOEXEC = 1
	return lio.fcntl(fd, lio.F_SETFD, FD_CLOEXEC)
end

function lio.set_nonblock(fd)
	return lio.fcntl(fd, lio.F_SETFL, lio.O_NONBLOCK)
end

function lio.open(pathname, flags, mode)
	puts(lsc.buf, pathname)
	local fd, eno = syscall(nr.open, lsc.buf, flags, mode)
	if not fd then return nil, eno end
	-- it appears that CLOEXEC is not set by the open syscall
	-- cf musl src open.c.  set it with fcntl
	if flags & lio.O_CLOEXEC ~= 0 then
		local FD_CLOEXEC = 1 -- from fcntl.h
		return syscall(nr.fcntl, fd, lio.F_SETFD, FD_CLOEXEC)
	end
	return fd
end

function lio.close(fd)
	return syscall(nr.close, fd)
end

function lio.read(fd, count)
	-- read at most `count` bytes from fd, using the lsc buffer
	-- return read bytes as a string, or nil, errno
	-- count defaults to lsc.buflen
	local b, blen = lsc.buf, lsc.buflen
	count = count or blen
	assert(count <= lsc.buflen)
	local r, eno = syscall(nr.read, fd, b, count)
	if not r then return nil, eno end
	local s = gets(b, r)
	return s
end

function lio.write(fd, s)
	-- write string s to fd, using lsc buffer
	-- returns the number of written bytes, or nil, errno
	local buf, buflen = lsc.buf, lsc.buflen
	assert(#s <= buflen, "string too large for buffer")
	puts(buf, s)
	return syscall(nr.write, fd, buf, #s)
end 

function lio.ftruncate(fd, len)
	-- truncate file to length `len`. If the file was shorter, 
	-- it is extended with null bytes.
	-- return 0 or nil, errno
	--
	-- note: arch=64bits (len is uint64, is passed as one arg)
	--
	return syscall(nr.ftruncate, fd, len)
end

function lio.lseek(fd, offset, whence)
	-- reposition the read/write file offset of open file fd
	-- whence = 0 (SET) file offset is set to `offset`
	-- whence = 1 (CUR) file offset is set to current position + `offset`
	-- whence = 2 (END) file offset is set to end of file + `offset`
	--                  (allow to create "holes" in file)
	-- offset defaults to 0
	-- whence defaults to 0 (SET)
	-- return the new offset location, or nil, errno
	--
	-- note: arch=64bits (offset is uint64, is passed as one arg)
	--
	-- (syscall args default to 0)
	return syscall(nr.lseek, fd, offset, whence)
end

function lio.unlink(pathname)
	local buf = puts(lsc.buf, pathname)
	return syscall(nr.unlink, lsc.buf)
end

function lio.symlink(target, linkpath)
	local btarget = lsc.buf
	local blinkpath = btarget + #target + 1
	assert(blinkpath + #linkpath + 1 < lsc.buf + lsc.buflen)
	return syscall(nr.symlink, btarget, blinkpath)
end

function lio.dup2(oldfd, newfd)
	-- return newfd, or nil, errno
	local r, eno
	r, eno = syscall(nr.dup2, oldfd, newfd)
	-- [ may should enclose in a busy loop:
	-- while eno ~= EBUSY do syscall(...) end
	-- becuse of a race condition with open()
	-- See musl src/unistd/dup2.c
	return r, eno
end

function lio.pipe2(flags)
	local buf = lsc.buf
	local r, eno = syscall(nr.pipe2, buf, flags)
	if not r then return nil, eno end
	local intsz = 4 -- sizeof(int)
	local p0, p1 = geti(buf, intsz), geti(buf+intsz, intsz)
	return p0, p1
end

function lio.ioctl(fd, cmd, arg)
	-- `fd`, `cmd`, `arg` are lua integers. 
	-- arg can be an integer argument or the address of a buffer.
	return syscall(nr.ioctl, fd, cmd, arg)
end

function lio.mount(source, target, fstype, flags, data)
	-- see `man 2 mount`
	-- data is an optional, filesystem-specific argument
	local buf, buflen = lsc.buf, lsc.buflen
	data = data or ""
	flags = flags or 0
	-- 
	-- copy string args to buffer
	local bsource = buf   -- buffer addresses for arguments
	local btarget = bsource + #source + 1
	local bfstype = btarget + #target + 1
	local bdata = bsource + #source + 1
	assert(bdata + #data +1 < buflen, "buffer not large enough")
	puts(bsource, source)
	puts(btarget, target)
	puts(bfstype, fstype)
	puts(bdata, data)
	--
	return syscall(nr.mount, bsource, btarget, bfstype, flags, bdata)
end


function lio.umount(target, flags)
	-- wraps umount2 (same as umount + flags)
	-- see man 2 umount
	--
	local buf, buflen = lsc.buf, lsc.buflen
	assert(#target + 1 < buflen, "buffer not large enough")
	puts(buf, target)
	flags = flags or 0 
	-- with flags=0, umount2 is the same as umount
	return syscall(nr.umount2, buf, flags)
end



------------------------------------------------------------------------
-- directory functions

local typetbl = { -- directory entry type as a one-char string
	[1] = "f", 	-- fifo
	[2] = "c",	-- char device
	[4] = "d",	-- directory
	[6] = "b",	-- block device
	[8] = "r",	-- regular file
	[10] = "l",	-- symlink
	[12] = "s",	-- socket
	-- [14] = "w",  -- whiteout (only bsd? and/or codafs? => ignore it)
}

local function getdent(a)
	-- parse a directory entry (returned by getdents64) at address a 
	-- return 
	--	the address of the next entry
	--	entry name, type (as one char), and inode
	local eino = geti(a, 8) -- inode 
	--local offset = geti(a+8, 8) -- what is offset? ignore it.
	local reclen = geti(a+16, 2) -- entry record length
	local etype = geti(a+18, 1)
	etype = typetbl[etype] or "u" --(unknown)
	local ename = gets(a+19)
	return a + reclen, ename, etype, eino
end

function lio.dirmap(dirpath, f, t)
	-- map function f over all the directory entries
	-- f signature:  f(t, ename, etype, eino)
	-- t is intended to be a table to collect results (defaults to {})
	--
	t = t or {}
	local buf, buflen = lsc.buf, lsc.buflen
	local fd, r, eno
	fd, eno = lio.open(dirpath, lio.O_RDONLY | lio.O_DIRECTORY)
	if not fd then 
		print(nil, eno, "opendir", '['..dirpath..']')
		return nil, eno, "opendir" 
	end
	while true do
		r, eno = syscall(nr.getdents64, fd, buf, buflen)
		if not r then 
			return nil, eno, "getdents64" 
		end
--~ 		print("read", r)
		eoe = buf + r
		if r == 0 then break end
		a = buf
		local eino, ename, etype -- dir entry values
		while (a < eoe) do
			a, ename, etype, eino = getdent(a)
			f(t, ename, etype, eino)
		end
	end
	lio.close(fd)
	return t
end

-- utility functions for dirmap
local function append_name_type(t, ename, etype, eino)
	if ename ~= "." and ename ~= ".." then
		table.insert(t, {ename, etype})
	end
	return t
end

local function append_name(t, ename, etype, eino)
	if ename ~= "." and ename ~= ".." then
		table.insert(t, ename)
	end
	return t
end

-- convenience functions to return the content of a directory

function lio.ls(dirpath)
	-- return a list of the names of entries in the directory
	-- ('.' and '..' are not included)
	return lio.dirmap(dirpath, append_name)
end

function lio.ls2(dirpath)
	-- return a list of pairs: {{"name1", "type1"}, {"name2", "type2"}...}
	-- types are one-letter strings, as described above.
	return lio.dirmap(dirpath, append_name_type)
end

------------------------------------------------------------------------
-- stat() functions  -- (for 64-bit arch)

local stat_off = { --field offset in struct stat
	dev = 0,
	ino = 8,
	nlink = 16,
	mode = 24,
	uid = 28,
	gid = 32,
	rdev = 40,
	size = 48,
	blksize = 56,
	blocks = 64,
	atime = 72,
	atime_ns = 80,
	mtime = 88,
	mtime_ns = 96,
	ctime = 104,
	ctime_ns = 112,
}

local stat_len = { --field length in struct stat
	dev = 8,
	ino = 8,
	nlink = 8,
	mode = 4,
	uid = 4,
	gid = 4,
	rdev = 8,
	size = 8,
	blksize = 8,
	blocks = 8,
	atime = 8,
	atime_ns = 8,
	mtime = 8,
	mtime_ns = 8,
	ctime = 8,
	ctime_ns = 8,
}

local stat_names = {
	"dev", "ino", "nlink", "mode", "uid", "gid", "rdev", "size", "blksize",
	"blocks", "atime", "atime_ns", "mtime", "mtime_ns", "ctime", "ctime_ns",
}

function lio.statbuf(pathname)
	-- call the system call stat. The struct stat returned by 
	-- the system call is placed in lsc.buf
	local buf, buflen = lsc.buf, lsc.buflen
	puts(buf + 256, pathname)
	return syscall(nr.stat, buf+256, buf)
end

function lio.lstatbuf(pathname)
	-- call the system call lstat. The struct stat returned by 
	-- the system call is placed in lsc.buf
	local buf, buflen = lsc.buf, lsc.buflen
	puts(buf + 256, pathname)
	return syscall(nr.lstat, buf+256, buf)
end

function lio.stat_get(name)
	-- return a field of struct stat after a call to lio.statbuf() 
	-- or lio.lstatbuf()
	local buf, buflen = lsc.buf, lsc.buflen
	return geti(buf + stat_off[name], stat_len[name])
end

function lio.stat(pathname, t)
	-- convenience function. stat is called, the result is returned 
	-- as a Lua table
	t = t or {}
	local buf, buflen = lsc.buf, lsc.buflen
	local r, eno = lio.statbuf(pathname, buf)
	if not r then return nil, eno end
	for i, name in ipairs(stat_names) do
		t[name] = geti(buf + stat_off[name], stat_len[name])
	end
	-- extract type and permissions from `mode` and add them as attributes
	t.type = lio.modetype(t.mode)
	t.perm = lio.modeperm(t.mode)
	return t
end

function lio.lstat(pathname, t)
	-- convenience function. lstat is called, the result is returned 
	-- as a Lua table
	t = t or {}
	local buf, buflen = lsc.buf, lsc.buflen
	local r, eno = lio.lstatbuf(pathname, buf)
	if not r then return nil, eno end
	for i, name in ipairs(stat_names) do
		t[name] = geti(buf + stat_off[name], stat_len[name])
	end
	return t
end

-- access to the content of the stat/lstat `mode` attribute

function lio.modetype(mode)
	-- return the file type of a file given its 'mode' attribute
	-- as a one letter string
	return typetbl[(mode >> 12) & 0x1f] or "u"
end

function lio.modeperm(mode) 
	-- get the access permissions of a file given its 'mode' attribute
	return mode & 0x0fff
end

function lio.mkdir(pathname, mode)
	local buf = lsc.buf
	puts(buf, pathname)
	return syscall(nr.mkdir, buf, mode)
end

function lio.rmdir(pathname)
	local buf = lsc.buf
	puts(buf, pathname)
	return syscall(nr.rmdir, buf)
end



------------------------------------------------------------------------
return lio

