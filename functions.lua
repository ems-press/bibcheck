--- Generic functions.

local M = {}

local pl_file = require 'pl.file'

M.sep = package.config:sub(1, 1)
-- TRUE if Windows, otherwise FALSE
local win = (M.sep == '\\')

--- Escape all magic characters in a string.
-- https://github.com/lua-nucleo/lua-nucleo/blob/v0.1.0/lua-nucleo/string.lua#L245-L267
-- Input: string str
-- Output: string Lua-escaped
do
	local match = {
		['^'] = '%^';
		['$'] = '%$';
		['('] = '%(';
		[')'] = '%)';
		['%'] = '%%';
		['.'] = '%.';
		['['] = '%[';
		[']'] = '%]';
		['*'] = '%*';
		['+'] = '%+';
		['-'] = '%-';
		['?'] = '%?';
    ['\0'] = '%z';
	}
	M.escape_lua = function(str)
		return (str:gsub('.', match))
	end
end

--- Escape all magic characters in a URL.
-- Input: string str
-- Output: string URL-escaped
do
	local matches = {
		-- RFC 3986 section 2.2 Reserved Characters (January 2005)
		['!'] = '%21',
		['#'] = '%23',
		['$'] = '%24',
		['&'] = '%26',
		['\''] = '%27',
		['('] = '%28',
		[')'] = '%29',
		['*'] = '%2A',
		['+'] = '%2B',
		[','] = '%2C',
		['/'] = '%2F',
		[':'] = '%3A',
		[';'] = '%3B',
		['='] = '%3D',
		['?'] = '%3F',
		['@'] = '%40',
		['['] = '%5B',
		[']'] = '%5D',
		-- RFC 3986 section 2.3 Unreserved Characters (January 2005)
		-- [A-Za-z0-9\-_.~] URI producers are discouraged
		-- from percent-encoding unreserved characters.
		-- Other characters in a URI must be percent encoded
		-- (which is probably done mostly by wget).
		[' '] = '+',
		['"'] = '%22'
	}
	M.escapeUrl = function(str)
		return (str:gsub('.', matches))
	end
end

--- Create pipe and execute command.
-- Input: string info, boolean log (print output), variable number of strings ...
-- Output: string
function M.execute(info, log, ...)
	if info then print(info) end
	local t = {}
	for i = 1, select('#', ...) do
		t[i] = tostring((select(i, ...)))
	end
	local p = assert(io.popen(table.concat(t, ' ')),
		'*** Cannot execute command. ***')
	local out = p:read('*all')
	p:close()
	if log then print(out) end
	return out
end

--- Create (OS-dependent) path.
-- Concatenates all given parts with the path separator.
-- Input: variable number of strings ...
-- Output: string
function M.path(...)
	local t = M.var_string(...)
	return table.concat(t, M.sep)
end

-- function M.quote_inner(str)
--  if not win then
--    str = str:gsub("'", "'\\''")
--  end
--	local inner = (win) and '\'' or "\""
--	return inner .. str .. inner
-- end

-- function M.quote_outer(str)
--  if not win then
--    str = str:gsub('"', '\"')
--  end
--	local outer = (win) and '\"' or "\'"
--	return outer .. str .. outer
-- end

--- Create string literal (OS-dependent).
-- Input: string str
-- Output: enquoted string
function M.quote(str)
	if not win then
		-- escape special characters in semi-literal quote
		str = str:gsub('(["\\$`])', '\\%1')
	end
	-- string literal in Windows not available?
	return table.concat({ '"', str, '"' })
end

--- Create table from variable number of arguments.
-- Input: variable number of strings ...
-- Output: table
function M.var_string(...)
	local t = {}
	for i = 1, select('#', ...) do
		t[i] = tostring((select(i, ...)))
	end
	return t
end

--- Remove all LaTeX comments (%).
-- Input: string text
-- Output: string
function M.remove_comments(text)
	-- N.B.: Don't delete the percent sign \%.
	-- Since gsub('([^\\])%%.-\n', '%1\n') doesn't work with sequenced %-lines,
	-- we first delete all lines starting (!) with %
	-- and in a second step delete all remaining %.
	local t = {}
	for line in text:gmatch('(.-)\n') do
		if not line:match('^%s-%%') then
			table.insert(t, line)
		end
	end
	local r = table.concat(t, '\n')
	r = r:gsub('([^\\])%%.-\n', '%1\n')
	return r
end

--- Write a string to a file.
-- Input: string file (path), string str
function M.write_file(file, str)
	str = str:gsub('\r\n', '\n')
	pl_file.write(file, str)
end

function M.read_file(file)
	local str = pl_file.read(file)
	assert(str, 'Cannot read file ' .. file)
	return str
end

return M

-- End of file.