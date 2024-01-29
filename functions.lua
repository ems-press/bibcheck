--- Generic functions.

local M = {}

local pl_file = require 'pl.file'
local C = require 'config'
local json = require 'dkjson'

if C.checkArXiv then
  xml2lua = require("xml2lua")
end

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

-- Return some values of former JSON table from zbMATH as a comment
---- with relevance score (also \Zbl{} if score is below the threshold) in the prefix
-- Input: table tab
-- Output: string
function M.zbl_info(tab)
  if tab then
    local smallscore=' (score: '..tostring(tab.score)..')'
    local ret = {tab.authors, tab.title, tab.source}
    if (tab.score<C.ZblRelevanceScoreThreshold) then --<5.5
      smallscore = ' (\\Zbl{'..tab.zbl_id..'}, score: '..tostring(tab.score)..')'
    end
    return '\n%%__ zbMATH'..smallscore..':\n%% '..table.concat(ret, '; ')
  else
    return ''
  end
end

-- return MathSciNet TeX-type response as a comment
function M.mr_tex_info(s)
  if s~='' and s~=nil then
    s=s:gsub("\\cprime%s*","'")
    return '\n%%__ MathSciNet-TeX:\n%% '..s:gsub('%s+',' ')
  else
    return ''
  end
end

-- return .bib's NOTE value as a comment
function M.mr_note_info(s)
  if s~='' and s~=nil then
    s=s:gsub("\\cprime%s*","'")
    return '\n%%__ MathSciNet Bib NOTE:\n%% '..s:gsub('%s+',' ')
  else
    return ''
  end
end

--- Return some values of former JSON table from Crossref.
-- Input: table tab
-- Output: string
function M.crossref_info(tab)
  if tab then
    -- fix for Crossref not returning a title (or the title returned is empty)
    local title = ''
    if tab.title then
      title = tab.title[1]
    else
      title = '[No title returned by Crossref]'
    end
    title = title:gsub('\n', '')
    return '\n%%\n%% No DOI in MathSciNet. With a relevance score of '
    ..tab.score..' Crossref returned:\n%% '
    ..'https://doi.org/'..tab.DOI..'\n%% '..title
  else
    return ''
  end
end

--- Return ZBLNUMBER from former JSON table from zbMATH.
-- Input: table tab
-- Output: string
function M.zbl_ID(tab)
  -- if tab, AND relevance score is above the threshold then
  if tab and type(tab)=='table' and tab.zbl_id and tab.score>=C.ZblRelevanceScoreThreshold then -- >=5.5
  -- Formally, we need to check if tab.zbl_id is a string because
  -- string concatenation .. expects a string, or something that can be converted to one.
   if C.checkNumdam and not new_entry:find('NUMDAM%s+=') then 
    -- checking zbMATH page for NUMDAM entry, based on config setting
    -- ...and put it to the .bib entry as NUMDAM value
    local retwo
    retwo = M.execute('Checking Zbl for Numdam ('..tab.zbl_id..')', false,
      'wget -qO-', M.quote('https://zbmath.org/'..tab.zbl_id))
    local numdam_entry
    if retwo:find('numdam%.org%/item.id%=') then --\.org\/item\?id\=') then
      numdam_entry = retwo:match('numdam%.org%/item.id%=(.-)"') --\.org\/item\?id=(.-)"')
      print('found: '..numdam_entry);
      numdam_entry = '\nNUMDAM = {'..numdam_entry..'},'
    else
      print('not found');
      numdam_entry = ''
    end
    return numdam_entry..'\nZBLNUMBER = {'..tab.zbl_id..'},'
   else
    return '\nZBLNUMBER = {'..tab.zbl_id..'},'
   end
  else
    return ''
  end
end

--- Return DOI from former JSON table from Crossref.
-- Input: table tab
-- Output: string
function M.crossref_DOI(tab)
  -- if tab then
  if tab and type(tab)=='table' and tab.DOI then
    return '\nDOI = {'..tab.DOI..'},'
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

--- Remove some tex commands before \bibitem is sent to the zbMATH Citation Matcher
--- to increase the hit rate. See email by Fabian Müller (zbMATH) sent 23 Jan 2023.
-- Input: string str
-- Output: string
do
  -- Mind the order of entries in 'match'!
  local match = {
    {'\\"', ''},  -- Umlaut
    {"\\'", ''},  -- acute accent
    {"\\`", ''},  -- grave accent
    {"\\%^", ''}, -- circumflex
    {"\\~", ''},  -- tilde
    {"\\=", ''},  -- bar
    {"\\%.", ''}, -- dot
    {"\\!", ''},
    {"\\i(%A)", 'i%1'}, -- dotless i
    {'\\href{[^}]+}', ''}, -- remove \href links,...
    {'\\MR{[^}]+}', ''}, -- ...\MR{}s,...
    {'\\Zbl{[^}]+}', ''}, -- ...and \Zbl{}s from the query (for getting result more reliably)
    {'\\%a%s', ''},
    {'\\%a+(%A)', '%1'}, -- remove all latex commands, especially accents \H, \v, etc.
    {'~', ' '},
    {'{', ''},
    {'}', ''},
  }
  M.undress = function(str)
    --print('\nORIGINAL: '..str)
    for i = 1, #match do
      local s, r = table.unpack(match[i])
      str = str:gsub(s,r)
    end
    --print('\nNAKED: '..str..'\n')
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
---- if command is a plain wget and it produces no output,
---- re-execute it with --no-check-certificate option (assuming SSL error)
-- Input: string info, boolean log (print output), variable number of strings ...
-- Output: string
function M.execute(info, log, ...)
  if info then print(info) end
  local t = {}
  local z = {}
  local wgetwcert=false
  if select(1,...)=='wget -qO-' then wgetwcert=true end
  for i = 1, select('#', ...) do
    t[i] = tostring((select(i, ...)))
    if wgetwcert then
      if i==1 then
        z[i] = 'wget --no-check-certificate -qO-'
      else
        z[i] = tostring((select(i, ...)))
      end
    end
  end
  local p = assert(io.popen(table.concat(t, ' ')),
    '*** Cannot execute command. ***')
  local out = p:read('*all')
  p:close()
  if (out=='' or out==nil) and wgetwcert then
    return M.execute(nil, log, table.concat(z, ' '))
  else
    if log then print(out) end
    return out
  end
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

--- Send str to Crossref.
-- Input: string str
-- Output: table
function M.get_crossref(str)
  local ret = M.execute('  Trying to get DOI from Crossref', false,
    'wget -qO-', M.quote(C.crossref .. M.escapeUrl(str)))
  -- unpack the JSON ouput of Crossref:
  local function isTable(t) return t and type(t) == 'table' end
  ret = ret and json.decode(ret)
  ret = isTable(ret) and ret.message
  ret = isTable(ret) and ret.items
  ret = isTable(ret) and table.unpack(ret)
  return ret
end

-- function for print table values-keys recursively for debugging
function M.printTable(t,l)
 local nextlevel=l+1
 for k,v in pairs(t) do
  if type(v)=='table' then
   M.printTable(v,nextlevel)
  else
   print (l..'. '..k..': '..v)
  end
 end
end

-- function for trying to convert (arXiv API returned) titles properly case-preserving string by BibTeX
-- + converting greek letters and leq/geq chars in titles by their TeX commands
function M.ucaseTitle(t)
 local to=t:gsub('(%$[^%$]+%$)','{%1}')
 if (t:find('%s%l%l%l%l%l')) then -- there exists at least one at least 5 character long lowercase word
   to=to:gsub('(%u+)','{%1}')
 end
 local macros = {'alpha','beta','Gamma','gamma','Delta','delta','epsilon','varepsilon',
  'zeta','eta','Theta','theta','vartheta','iota','kappa','Lambda','lambda',
  'mu','nu','xi','Xi','Pi','pi','rho','varrho','Sigma','sigma','varsigma',
  'tau','Upsilon','upsilon','Phi','phi','varphi','chi','Psi','psi','Omega','omega',
  'leq','geq'}
 local chars = {'α','β','Γ','γ','Δ','δ','ϵ','ε',
  'ζ','η','Θ','θ','ϑ','ɩ','κ','Λ','λ',
  'μ','ν','ξ','Ξ','Π','π','ρ','ϱ','Σ','σ','ς',
  'τ','Υ','υ','Φ','φ','ϕ','χ','Ψ','ψ','Ω','ω',
  '≤','≥'}
 for i = 1, #macros do
  to=to:gsub(chars[i]..'%a','\\'..macros[i]..' ')
  to=to:gsub(chars[i],'\\'..macros[i])
 end
 to=to:gsub('%s+',' ')
 return to
end

--- query arXiv API for ID
-- Input: string str
-- Output: Atom XML -> table -> BibTeX data list
function M.get_arxiv(str,str_naked)
  local ret = ''
  local arxiv=''
  local axret=''
  local axentry
  local strlow = str:lower()
  -- trying to get arXiv ID from preprint \bibitem entries...
  if strlow:find('arxiv[:%.%(]?%s*p?r?e%-?print[:%.]?%s*[%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.]+%d') then
    arxiv = str:match('[aA][rR][Xx][iI][vV][:%.%(]?%s*[Pp]?r?[Ee]%-?print[:%.]?%s*([%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.]+%d)')
  elseif strlow:find('arxiv%.org%/abs%/[%a%d%/%.]+%d%/?') then
    arxiv = str:match('arxiv%.org%/abs%/([%a%d%/%.]+%d)%/?')
  elseif strlow:find('arxiv%s*[:%.%({]?%s*[%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.]+%d') then -- ') then
    arxiv = str:match('[aA][rR][Xx][iI][vV]%s*[:%.%({]?%s*([%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.]+%d)')
  elseif strlow:find('arxiv[:%.%s%(]*%s*[12][%d][%d][%d][:%.%,%)]*%s+[%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.]+%d') then
    arxiv = str:match('[aA][rR][Xx][iI][vV][:%.%s%(]*%s*[12][%d][%d][%d][:%.%,%)]*%s+([%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.][%a%d%/%.]+%d)')
  elseif strlow:find('\\eprint%s*%{%s*[^%s%}]+%d%s*%}') then
    arxiv = str:match('\\[eE][pP][rR][iI][nN][tT]%s*%{%s*([^%s%}]+%d)%s*%}')
  end
  if arxiv~='' or str_naked:match('[Pp]?[rR?][eE]%-?[pP][rR][iI][nN][tT]') or str_naked:match('[aA][rR][xX][iI][vV]') then -- or str_naked:match('[Pp][rR][eE][pP][aA][rR][aA][tT][iI][oO][nN]')
  -- if arXiv ID found OR the entry is a preprint or arXiv...
    local function isTable(t) return t and type(t) == 'table' end
    if arxiv~='' then
     -- arXiv number found, querying arXiv API for arXiv ID
     axret = M.execute('arXiv found: '..arxiv..', checking arXiv API... ' --..i..' of '..#bibitems
      , false,
      'wget -qO-', M.quote(C.arxivapi .. M.escapeUrl(arxiv)))
    else
     -- arXiv number NOT found, querying arXiv API for (naked) bibitem value for best match...
-- print (C.arxivapiq .. M.escapeUrl(str_naked:gsub("^%s*(.-)%s*$", "%1")))
     axret = M.execute('  querying arXiv for '..str_naked:gsub("^%s*(.-)%s*$", "%1"), --..i..' of '..#bibitems
      false,
      'wget -qO-', M.quote(C.arxivapiq .. M.escapeUrl(str_naked:gsub("^%s*(.-)%s*$", "%1"))))
    end
    local xmlhandler = require("xmlhtree")
    local axHandler = xmlhandler:new()
    local xmlparser = xml2lua.parser(axHandler)
--  print (axret)
    xmlparser:parse(axret)
    local axentry = axHandler and axHandler.root and type(axHandler.root)=='table' and axHandler.root.feed and type(axHandler.root.feed)=='table' and axHandler.root.feed.entry
--[[
If there is more than one person, then person is an array instead of a regular table.
This way, we need to iterate over the person array instead of the people table.
]]
-- if type(axentry)=='table' then M.printTable(axentry,1) end
    local axauthors=''
    if axentry and axentry.author then
      if type(axentry.author)=='table' then
        if axentry.author.name then
          axauthors=axentry.author.name
        else
         for axauk, axauv in ipairs(axentry.author) do
          if (axauk > 1) then axauthors=axauthors..' and ' end
            axauthors=axauthors..axauv.name
         end
        end
      else
        axauthors=axentry.author
      end
      -- print ('FOUND AX authors: '..axauthors)
      ret = ret..'      AUTHOR = {'..axauthors..'},\n';
      if string.sub(axentry.published,1,4)==string.sub(axentry.updated,1,4) then
        ret = ret..'      YEAR = {'..string.sub(axentry.published,1,4)..'},\n';
      else
        ret = ret..'      YEAR = {[v1]~'..string.sub(axentry.published,1,4)..', [v'..axentry.id:match('v(%d+)$')..']~'..string.sub(axentry.updated,1,4)..'},\n';
      end
      ret = ret..'      EPRINT = {'..axentry.id..'},\n';
      ret = ret..'      ARCHIVE = {'..axentry.id:match('arxiv%.org%/abs%/([%a%d%/%.]+)')..'},\n';
      -- print ('FOUND AX title: '..axentry.title)
      ret = ret..'      TITLE = {'..M.ucaseTitle(axentry.title)..'}';
    end
  end
  return ret
end

-- function to check whether the {name} path/files exists
function M.file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

return M

-- End of file.