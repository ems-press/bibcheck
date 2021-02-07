--- Generic functions.

local G = {}

local pl_file = require 'pl.file'

G.sep = package.config:sub(1, 1)
-- TRUE if Windows, otherwise FALSE
local win = (G.sep == '\\')

--- Escape all magic characters in a string.
-- https://github.com/lua-nucleo/lua-nucleo/blob/v0.1.0/lua-nucleo/string.lua#L245-L267
-- @tparam string str input
-- @treturn string Lua-escaped
do
	local matches = {
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
	}
	G.escape_lua_pattern = function(str)
		return (str:gsub('.', matches))
	end
end

--- Create pipe and execute command.
-- @tparam string info
-- @tparam boolean log print output
-- @tparam {string,...} ... variable number of string parts
-- @treturn string output
function G.execute(info, log, ...)
	print(info .. ':\n')
	local t = G.var_string(...)
-- 	print(table.concat(t))
	local p = assert(io.popen(table.concat(t)))
	local out = p:read('*all')
	p:close()
	if log then
		print(out)
	end
	return out
end

--- Create (OS-dependent) path.
-- Concatenates all given parts with the path separator.
-- @tparam {string,...} ... variable number of string parts
-- @treturn string path
function G.path(...)
	local t = G.var_string(...)
	return table.concat(t, G.sep)
end

--- Create (OS-dependent) inner quotes.
-- @tparam string str
-- @treturn string enquoted string
function G.quote_inner(str)
	local inner = (win) and '\'' or "\""
	return inner .. str .. inner
end

--- Create (OS-dependent) outer quotes.
-- @tparam string str
-- @treturn string enquoted string
function G.quote_outer(str)
	local outer = (win) and '\"' or "\'"
	return outer .. str .. outer
end

--- Create table from variable number of arguments.
-- @tparam {string,...} ... variable number of string parts
-- @treturn table
function G.var_string(...)
	local t = {}
	for i = 1, select('#', ...) do
		t[i] = tostring((select(i, ...)))
	end
	return t
end

--- Remove all LaTeX comments (%).
-- @tparam string text
-- @treturn string
function G.remove_comments(text)
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
-- @tparam string file path
-- @tparam string str
function G.write_file(file, str)
	str = str:gsub('\r\n', '\n')
	pl_file.write(file, str)
end

return G

-- End of file.