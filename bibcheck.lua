--- This is bibcheck.
-- version 0.9.8 (2021-05-22)

-- authors: 
-- Simon Winter [winter@ems.press]
-- Tobias Werner [werner@wissat-pc.de]

-- tested on
--  Windows 10 + Lua 5.1.5 + WGeT 1.21.1
--  Linux + Lua 5.4.2

-- See file 'install-windows.md' on how to use this script.

local lfs = require 'lfs'

-- Add path of main file to package path.
local path = arg[0]
path = path:gsub('(.-)bibcheck.lua$', '%1')
package.path = path .. '?.lua;' .. package.path

local F = require 'functions'
local C = require 'config'
local json = require 'dkjson'

table.unpack = table.unpack or unpack
-- in order to be available in both Lua 5.1 and Lua 5.2+
-- http://lua-users.org/lists/lua-l/2013-10/msg00534.html

--- TeX file input path.
local input_path = arg[1]
--- Bibliography style (for example, 'amsplain').
local bst = arg[2] or C.bibstyle

local folder, input
local texpattern = '(.-)%.tex$'
-- Check if input_path is a full path (with separator)
-- or a file name (no separator).
if input_path:find(F.sep) then
	folder, input = input_path:match(F.path('(.+)', texpattern))
else
	folder = lfs.currentdir()
	input = input_path:match(texpattern)
end
assert(input, 'File name not recognized.')
-- Save current working directory.
local cwd = lfs.currentdir()
-- Change to folder of input file.
lfs.chdir(folder)

--- Name for all (temporary and final) files created by this script.
local output = input .. C.suffix

--- Content of the original TEX file.
local texcode = F.read_file(input .. '.tex')

--- Bibliography of the original TEX file.
local bibliography = texcode:match('(\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')
assert(bibliography, 'No bibliography found.')

local new_bibliography = false
local bibitems = {}
local bibtex_entries = {}
local zbl_matches = {}

--- All \bibitem labels.
local labels = {}
-- Table indicates if bibitems[i] is MathSciNet matched (true) or unmatched (false).
local MR_matched = {}

--------------------------------------------------------------------------------
-- Functions:

--- Correct some 'mistakes' in the BibTeX code.
-- Input: string entry
-- Output: string
local function correct_bibtex(entry)
	local function replace(s, r) entry = entry:gsub(s, r) end
	replace('\\bf(%A)', '\\mathbf%1')
	replace('\\bold(%A)', '\\mathbf%1')
	replace('\\Bbb(%A)', '\\mathbb%1')
	-- Enclose 'dotless i' in curly brackets.
	replace('\\i%s', '{\\i}')
  -- The following replacements are necessary to get proper alphabetic labels, e.g.
  -- when using amsalpha.bst.
  -- See https://tex.stackexchange.com/questions/134116/accents-in-bibtex
  -- Replace \" LETTER by \"{LETTER}.
  replace('\\\"%s(%a)', '\\\"{%1}')
  -- Replace \"{LETTER} by {\"{LETTER}}.
  replace('\\\"{(%a)}', '{\\\"{%1}}')
	-- Similar replacement with accents.
	local accents = { 'c', 'H', 'k', 'r', 'u', 'v' }
	for i = 1, #accents do
		local s
    -- Replace \H LETTER by \H{LETTER}.
		s = string.format('(\\%s) (%%a)', accents[i]) -- s is of the form (\H) (%a)
		replace(s, '%1{%2}')
    -- Replace \H{LETTER} by {\H{LETTER}}.
		s = string.format('(\\%s){(%%a)}', accents[i]) -- s is of the form (\H){(%a)}
		replace(s, '{%1{%2}}')
	end
	return entry
end

--- Collect all \bibitem's from 'str' in a table.
-- Input: string str
-- Output: table
local function split_at_bibitem(str)
	-- Insert blank line before each \bibitem
	-- and at the very end (i.e. before \end{thebibliography}).
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
local function print_zbl(tab)
  if tab then
    --local ret = {}
    --for key, value in pairs(tab) do
    --  if key ~= 'score' and key ~= 'zbl_id' then
    --    table.insert(ret, value) 
    --  end  
    --end
    -- return '\n%%%% zbMATH:\n%% '..table.concat(ret, ' | ')
    local ret = {tab.authors, tab.title, tab.source}
    return '\n%%__ zbMATH:\n%% '..table.concat(ret, '; ')
  else
    return ''
  end 
end

--------------------------------------------------------------------------------
--- Main functions:

--- Create BIB file.
local function make_bib()
	-- Remove comments and collect all \bibitem in a table.
  bibitems = split_at_bibitem(F.remove_comments(bibliography))
  -- Process each \bibitem.
	for i = 1, #bibitems do
    local bibitem = bibitems[i]
		local function replace(s, r) bibitem = bibitem:gsub(s, r) end
		-- Remove optional argument of \bibitem[.]{.} and spaces.
		replace('\\bibitem[%%\n%s]*%b[][%%\n%s]*(%b{})', '\\bibitem%1')
		replace('\\bibitem[%%\n%s]*(%b{})', '\\bibitem%1')
		-- Remove \bibitem{.} and save the label.
		labels[i] = bibitem:match('\\bibitem%b{}')
    labels[i] = labels[i]:match('\\bibitem{(.-)}$')
    -- don't use labels[i] here because of 'magic characters' issue.
		replace('\\bibitem%b{}', '')
    local original = bibitem:gsub('^[\n%s]+', '')
		replace('\\newblock', ' ')
    replace('[%s\t]+', ' ')
		-- ******
    -- Send entry to MathSciNet.
		local returnA = F.execute('Checking MathSciNet for \\bibitem '..i, false,
    	'wget -qO-', F.quote(C.database.mref .. F.escapeUrl(bibitem)))
		local new_entry
    if returnA:find('%* Matched %*') then
			-- match found
			new_entry = returnA:match('<pre>(.-)</pre>')
			-- Correct some 'mistakes' in the BibTeX entry.
			new_entry = correct_bibtex(new_entry)
			-- Change label back to the original one.
			new_entry = new_entry:gsub('{MR%d+', '{' .. labels[i], 1)
      -- Save entry as 'matched'.
      MR_matched[i] = true
		else -- no match found
			-- Remove leading spaces and empty lines from original entry
      local t = {'@misc {', labels[i], ',\n NOTE = {', original, '},\n}'}
      new_entry = table.concat(t, '')      
      -- Save entry as 'unmatched'.
      MR_matched[i] = false
    end
    table.insert(bibtex_entries, new_entry)    
 		-- ******
    -- Send entry to zbMATH.
    local returnB
    if C.printZbl then
      returnB = F.execute('Checking zbMATH for \\bibitem '..i, false,
        'wget -qO-', F.quote(C.database.zbl .. F.escapeUrl(bibitem)))
      -- unpack the JSON ouput of zbMATH:
      local function isTable(t) return t and type(t) == 'table' end
      returnB = returnB and json.decode(returnB)
      returnB = isTable(returnB) and returnB.results
      returnB = isTable(returnB) and table.unpack(returnB)
    end
    zbl_matches[i] = returnB
  end
	F.write_file(output .. '.bib', table.concat(bibtex_entries, '\n\n'))
end

--- Create BBL file.
local function make_bbl()
	local t = {
		'\\documentclass{article}',
		'\\usepackage[utf8]{inputenc}',
		'\\usepackage{amssymb}',
		'\\newcommand\\MR[1]{MR~#1}',
    '\\begin{document}',
		'\\nocite{*}',
		'\\bibliographystyle{' .. bst .. '}',
		'\\bibliography{' .. output .. '}',
		'\\end{document}'
	}
	-- Write new TEX file.
	local texname = output .. '.tex'
  F.write_file(texname, table.concat(t, '\n'))
  -- Compile it.
	F.execute('\nRunning LaTeX', false, 'latex -interaction=nonstopmode -halt-on-error', texname, ' 2>&1')
	-- Run bibtex.
	F.execute('\nRunning BibTeX', true, 'bibtex', output)
end



--- Add to the BBL file for each \bibitem
--- either the original \bibitem (as a comment) if there was a MathSciNet match
--- or a warning that there was no MathSciNet match.
local function add_comments()
	-- Read content of the BBL file.
	new_bibliography = F.read_file(output .. '.bbl')
	-- Does the BST file create alphabetic or numeric labels?
  local alphabetic = new_bibliography:find('\\bibitem%b[]')
  
  
  -- Insert blank line before each \bibitem
	-- and at the very end (i.e. before \end{thebibliography}).
	new_bibliography = new_bibliography:gsub('\\bibitem', '\n\n\\bibitem')
  new_bibliography = new_bibliography:gsub('\\end%s*{thebibliography}', '\n\n\\\\end{thebibliography}')
    
  
  for i = 1, #bibitems do
	  if MR_matched[i] then		
      -- Add % at the beginning of each line.
		  local bibitem = bibitems[i] .. '\n'
		  local original = {}
		  for line in bibitem:gmatch('(.-)\n') do
  			if not line:find('^%c*$') then
	  			table.insert(original, '%% ' .. line)
			  end
		  end
      -- Paste original entry.
      if alphabetic then
		    new_bibliography = new_bibliography:gsub(
        '\\bibitem(%b[]){'..F.escape_lua(labels[i])..'}', 
        '%%__ Original:\n'..table.concat(original, '\n')
        ..'\n%%__ MathSciNet:\n\\bibitem%1{'..labels[i]..'}')
      else
		    new_bibliography = new_bibliography:gsub(
        '\\bibitem{'..F.escape_lua(labels[i])..'}', 
        '%%__ Original:\n'..table.concat(original, '\n')
        ..print_zbl(zbl_matches[i])
        ..'\n%%__ MathSciNet:\n\\bibitem{'..labels[i]..'}')
      end
    else -- unmatched entry
      if alphabetic then
        new_bibliography = new_bibliography:gsub(
          '\\bibitem(%b[]){'..F.escape_lua(labels[i])..'}',
          '%%%% EDIT AND SORT (!) UNMATCHED ENTRY:\n'
          ..'\\bibitem%1{'..labels[i]..'}')
      else  
        new_bibliography = new_bibliography:gsub(
          '\\bibitem{'..F.escape_lua(labels[i])..'}',
          '%%%% EDIT AND SORT (!) UNMATCHED ENTRY:\n'
          ..'\\bibitem{'..labels[i]..'}')
      end
    end
  end
  -- Overwrite BBL file.
	F.write_file(output .. '.bbl', new_bibliography)
end


--- Create TEX file.
local function make_tex()
	-- Escape Lua patterns in search string.
	local s = F.escape_lua(bibliography)
	-- Remove \providecommand{\bysame} etc. from replacement string.
  new_bibliography = new_bibliography:match('(\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')
  -- Escape percent character in replacement string.
  local r = new_bibliography:gsub('%%', '%%%%')
	-- Replace original bibliography with modified one.
	local out = texcode:gsub(s, r, 1)
	-- Overwrite TEX file.
	F.write_file(output .. '.tex', out)
end

--- Remove temporary files.
local function remove_temp()
  for i = 1, #C.remove_files do
	  os.remove(output .. C.remove_files[i])
  end
end

--------------------------------------------------------------------------------

-- ******
-- STEP 1:
-- Check each \bibitem against MathSciNet.
-- If there is a match, add the match to a BIB file.
-- If there is no match, add the original \bibitem to the BIB file.
-- Check each \bibitem against zbMATH.
make_bib()

-- ******
-- STEP 2:
-- Create a temporary TEX file with nothing more than \nocite{*} and \bibliography{BIB file}.
-- Run latex and bibtex to create a BBL file.
make_bbl()

-- ******
-- STEP 3:
-- For each match, add the original \bibitem to the BBL file (as a comment).
-- For each \bibitem, add the zbMATH ID if there has been a match.
add_comments()

-- ******
-- STEP 4:
-- Replace the bibliography in the original TEX file by the new bibliography.
-- Remove all temporary files.
make_tex()
remove_temp()

-- ******
-- STEP 5:
-- Change back to current working directory.
lfs.chdir(cwd)

-- End of file.