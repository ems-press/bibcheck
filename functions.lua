--- Generic functions.

local M = {}

local pl_file = require 'pl.file'

M.sep = package.config:sub(1, 1)
-- TRUE if Windows, otherwise FALSE
local win = (M.sep == '\\')

--- Correct some 'mistakes' in the BibTeX code.
-- Input: string entry
-- Output: string
do
  local mpattern = '{({\\%a+%s*%b{}})}'
  local apattern = '{({\\["\'.=%^`~Hbcdkruv]%b{}})}'
  -- escaped for string.format
  local accents = {
    '"', "'", '%%.', '=', '%%^', '`', '~',
    'H', 'b', 'c', 'd', 'k', 'r', 'u', 'v'
  }
  -- old AMS/TeX macros
  -- TODO if replacing \bf were safe, what about \it and \rm?
  local map = {
    bf = 'mathbf',
    bold = 'mathbf',
    Bbb = 'mathbb',
    scr = 'mathcal',
    germ = 'mathfrak'
  }
  local cbrace = {
    '(\\[ijlLoO])%s',
    '(\\ss)%s',
    '(\\aa)%s', '(\\AA)%s',
    '(\\ae)%s', '(\\AE)%s',
    '(\\oe)%s', '(\\OE)%s',
  }
  function M.normalizeTex(str)
    local function replace(s, r) str = str:gsub(s, r) end
    for o, n in pairs(map) do
      local s = string.format('\\%s(%%A)', o)
      local r = string.format('\\%s%%1', n)
      replace(s, r)
    end
    -- enclose some characters in braces
    for i = 1, #cbrace do replace(cbrace[i], '{%1}') end
    -- replace accents
    for i = 1, #accents do
      local accent = accents[i]
      local spaces = accent:match('%a') and '+' or '*'
      -- either (\\%a)%s+(%a)
      -- or (\\["'%.=%^`~])%s*(%a)
      local a = string.format('(\\%s)%%s%s(%%a)', accent, spaces)
      replace(a, '{%1{%2}}')
      -- (\\accent)%s*(%b{})
      local b = string.format('(\\%s)%%s*(%%b{})', accent)
      replace(b, '{%1%2}')
      -- remove too many braces?
--       local c = string.format('{({\\%s{%%a}})}', accent)
--       while str:match(c) do
--         replace(c, '%1')
--       end
    end
    while str:match(mpattern) do str = str:gsub(mpattern, '%1') end
    while str:match(apattern) do str = str:gsub(apattern, '%1') end
    -- Revert some character escapes of HTML.
    local matches = { ['&amp;'] = '&', ['&gt;'] = '>', ['&lt;'] = '<' }
    for s, r in pairs(matches) do
      replace(s, r)
    end

    return str
  end
end

--- Collect all \bibitem's from 'str' in a table.
-- Input: string str
-- Output: table
function M.split_at_bibitem(str)
  -- Remove all blank lines.
  str = str:gsub('\n[\n%s]*\n', '')
  -- Insert one blank line before each \bibitem
  -- and one at the very end (i.e. before \end{thebibliography}).
  str = str:gsub('\\bibitem', '\n\n\\bibitem')
  str = str .. '\n\n'
  local t = {}
  for field in string.gmatch(str, '(\\bibitem.-)\n\n') do
    table.insert(t, field)
  end
  return t
end

--- Return some values of former JSON table from zbMATH.
-- Input: table tab
-- Output: string
function M.zbl_info(tab)
  if tab then
    local ret = {tab.authors, tab.title, tab.source}
    return '\n%%__ zbMATH:\n%% '..table.concat(ret, '; ')
  else
    return ''
  end
end

--- Return Zbl entry for BIB file of former JSON table from zbMATH.
-- Input: table tab
-- Output: string
function M.zbl_ID(tab)
  -- if tab then
  if tab and type(tab)=='table' and tab.zbl_id then
  -- Formally, we need to check if tab.zbl_id is a string because
  -- string concatenation .. expects a string, or something that can be converted to one.
    return '\nZBLNUMBER = {'..tab.zbl_id..'},'
  else
    return ''
  end
end

--- Return warning if b is true.
-- Input: boolean
-- Output: string
function M.space_warning(b)
  if b then
    return '%%%% WARNING: Space character in the label was removed!\n'
  else
    return ''
  end
end

--- Remove some tex commands before \bibitem is sent to the zbMATH Citation Matcher.
--- It seems that this increases the hit rate. See the comment at M.database.
-- Input: string str
-- Output: string
do
  -- Mind the order of entries in 'match'!
  local match = {
    {'\\%a+(%A)', '%1'}, -- remove all latex commands
    {'~', ' '},
    {'{', ''},
    {'}', ''},
  }
  M.undress = function(str)
    for i = 1, #match do 
      local s, r = table.unpack(match[i])
      str = str:gsub(s,r)
    end
    return str
  end
end

--- Escape the % sign.
-- Input: string str
-- Output: string
function M.escape_percent(str)
  return str:gsub('%%', '%%%%')
end

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
  local t = {}
  for i = 1, select('#', ...) do
    t[i] = tostring((select(i, ...)))
  end
  return table.concat(t, M.sep)
end

-- function M.quote_inner(str)
--  if not win then
--    str = str:gsub("'", "'\\''")
--  end
--  local inner = (win) and '\'' or "\""
--  return inner .. str .. inner
-- end

-- function M.quote_outer(str)
--  if not win then
--    str = str:gsub('"', '\"')
--  end
--  local outer = (win) and '\"' or "\'"
--  return outer .. str .. outer
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