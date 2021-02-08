--- This is bibcheck.
--
-- @author Simon Winter [winter@ems.press]
-- @author Tobias Werner [werner@wissat-pc.de]
--
-- @release 0.9.1 (2021-02-08)

-- tested on
--   Windows 10 + Lua 5.1.5
--   Linux + Lua 5.4.2
--
-- >> lua bibcheck.lua FILENAME.tex BSTFILENAME

local path = arg[0]
path = path:gsub('(.-)bibcheck.lua$', '%1')
package.path = path .. '?.lua;' .. package.path

local lfs = require 'lfs'
local pl_file = require 'pl.file'
local F = require 'functions'
local C = require 'config'

--- TeX file input path.
local input_path = arg[1]
--- Bibliography style (for example, "amsplain").
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

--- Name for all (temporary and final) files created by this script.
local output = input .. C.suffix

--- Output path.
local output_path = F.path(folder, output)

--- Content of the original tex file.
local texcode = pl_file.read(input_path)
--- All \bibitem labels.
local labels = {}
--- All critical cases.
local critical_entries = {}
--- All unmatched cases.
local unmatched_labels = {}

--------------------------------------------------------------------------------

-- Functions:

--- Correct some 'mistakes' in the BibTeX code.
-- @tparam string entry
-- @treturn string
local function correct_bibtex(entry)
	local function replace(s, r) entry = entry:gsub(s, r) end
	replace('\\bf(%A)', '\\mathbf%1')
	replace('\\bold(%A)', '\\mathbf%1')
	replace('\\Bbb(%A)', '\\mathbb%1')
	-- Enclose 'dotless i' in curly brackets.
	replace('\\i%s', '{\\i}')
	-- Replace accents.
	local accents = { 'c', 'H', 'k', 'r', 'u', 'v' }
	for i = 1, #accents do
		-- s is of the form (\c) (%a)
		local s = string.format('(\\%s) (%%a)', accents[i])
		-- Replace '\c LETTER' by '\c{LETTER}'
		replace(s, '%1{%2}')
	end
	return entry
end

--- Check if the entry is a critical case.
-- @tparam string orig original entry
-- @tparam string match matched entry
-- @treturn boolean
local function critical_entry(orig, match)
	local o, m, patterns
	--- Find pattern after making string lowercase.
	-- @tparam string s
	-- @tparam string p
	-- @treturn boolean if match is found
	local function lfind(s, p)
		if string.find(s:lower(), p) then
			return true
		end
		return false
	end
	--- Find one of multiple patterns.
	-- @tparam string s
	-- @tparam table p multiple strings
	-- @treturn boolean if one match is found
	local function pfind(s, p)
		for i = 1, #p do
			if s:find(p[i]) then
				return true
			end
		end
		return false
	end
	-- check if both original and match have a number range
	o = orig:find('%d+%s*%-%-?%s*%d+')
	m = lfind(match, 'pages%s*=%s*{%d+%-%-?%d+}')
	if (o and not m) or (not o and m) then
		return true
	end
	-- check if original contains one of the following words:
	patterns = {
		'appear', 'submitted',
		'[Aa]ppendix', '[Aa]ddendum', '[Cc]orrigendum', '[Ee]rratum'
	}
	if (pfind(orig, patterns)) then
		return true
	end
	-- critical if one of 'orig' or 'match' contains an edition
	o = pfind(orig, { '%A[Ee]d%A', '%A[Ee]dn%A', '%A[Ee]dition%A' })
	m = lfind(match, 'edition%s*=')
	if (o or m) then
		return true
	end
	-- critical if one of 'orig' or 'match' contains one of:
	patterns = { '[Tt]ranslation', '[Tt]ransl%.', '[Tt]ranslated', '[Rr]ussian' }
	if (pfind(orig, patterns) or pfind(match, patterns)) then
		return true
	end
	-- critical if one of 'orig' or 'match' contains one of:
	patterns = { '[Pp]art%A', '%AI%A', '%AII%A', '%AIII%A' }
	if (pfind(orig, patterns) or pfind(match, patterns)) then
		return true
	end
	-- default case: no critical entry
	return false
end

--- Select the bibliography and remove LaTeX comments.
-- @tparam string tex TeX code of the bibliography
-- @treturn string bib bibliography
local function select_bibliography(tex)
	-- return s (= original bibliography string if tex is not modified)
	local s = '\\begin%s*{thebibliography}(.-)\\end%s*{thebibliography}'
	local bib = tex:match(s)
	assert(bib, 'No bibliography found.')
	-- Remove comments.
	bib = F.remove_comments(bib)
	-- Save the argument of \begin{thebibliography}, usually "{9}" or "{99}".
	return bib
end

--- Collect all \bibitem from 'input' in a table.
-- @tparam string str
-- @treturn table
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

--------------------------------------------------------------------------------

-- Main functions:

--- Check all \bibitem against the AMS MRef database.
local function mref_bibliography()
	-- Select the bibliography.
	local bib = select_bibliography(texcode)
	-- Collect all \bibitem in a table.
	local tab = split_at_bibitem(bib)
	-- Process each \bibitem.
	for i = 1, #tab do
		local bibitem = tab[i]
		local function replace(s, r) bibitem = bibitem:gsub(s, r) end
		-- Remove optional argument of \bibitem[.]{.} and spaces.
		replace('\\bibitem[%%\n%s]*%b[][%%\n%s]*(%b{})', '\\bibitem%1')
		replace('\\bibitem[%%\n%s]*(%b{})', '\\bibitem%1')
		-- Remove \bibitem{.} and save the label.
		labels[i] = bibitem:match('\\bibitem%b{}')
		-- don't use labels[i] here because of 'magic characters' issue.
		replace('\\bibitem%b{}', '')
		labels[i] = labels[i]:match('\\bibitem{(.-)}$')
		-- Save original entry; delete leading spaces and empty lines.
		local original = bibitem:gsub('^[\n%s]+', '')
		-- Escape \newblock with space and spaces with "%20"
		replace('\\newblock', ' ')
		replace('[%s\t]+', '%%20')
		-- Send entry to www.ams.org/mathscinet-mref.
		local MRef_response_path = F.path(folder, C.mref.response)
		F.execute('Check MathSciNet ' .. i, true,
			'wget', ' --no-check-certificate', ' -O ', MRef_response_path,
			' ', F.quote_outer(C.mref.url .. F.quote_inner(bibitem)), ' 2>&1'
		)
		-- Read TEX code (if any) from MRef_response_path.
		local MRef_response = pl_file.read(MRef_response_path)
    os.remove(MRef_response_path)
		if MRef_response:find('%* Matched %*') then
			-- match found
			local new_entry = MRef_response:match('<pre>(.-)</pre>')
			-- Correct some 'mistakes' in the BibTeX entry.
			new_entry = correct_bibtex(new_entry)
			-- Change label back to the original one.
			tab[i] = new_entry:gsub('{MR%d+', '{' .. labels[i], 1)
			-- Check whether the entry is a critical case.
			if critical_entry(original, new_entry) then
				local s = '\\bibitem{' .. labels[i] .. '}\n' .. original
				table.insert(critical_entries, s)
			end
		else
			-- no match found
			tab[i] = '@misc {' .. labels[i] .. ',\n'
				.. ' NOTE = {' .. original .. '},\n}'
		  table.insert(unmatched_labels, labels[i])
    end
	end
	F.write_file(output_path .. '.bib', table.concat(tab, '\n\n'))
end

--- Create output bbl file.
local function create_bbl_output()
	local t = {
		'\\documentclass{article}',
		'\\usepackage[utf8]{inputenc}',
		'\\usepackage{amssymb}',
		'\\begin{document}',
		'\\nocite{*}',
		'\\bibliographystyle{' .. bst .. '}',
		'\\bibliography{' .. output .. '}',
		'\\end{document}'
	}
	-- Write new tex file.
	local tex_path = output_path .. '.tex'
	print(folder)
  F.write_file(tex_path, table.concat(t, '\n'))
	-- Compile it.
	F.execute('LaTeX', true,
		'latex',
		' -interaction=nonstopmode',
		' -halt-on-error',
    ' -output-directory=', folder,
    ' ', tex_path,
		' 2>&1'
	)
	-- Run bibtex.
	lfs.chdir(folder)
	F.execute('BibTeX', true, 'bibtex ', output)
end

--- For each critical case, add the original \bibitem
-- to the bbl file (as a comment).
local function add_critical_entries()
	local bbl_path = output_path .. '.bbl'
	-- Read content of the bbl file.
	local bib = pl_file.read(bbl_path)
	-- Paste each critical \bibitem into the new bibliography.
	for i = 1, #critical_entries do
		-- Add % at the beginning of each line.
		critical_entries[i] = critical_entries[i] .. '\n'
		local new = {}
		table.insert(new, '%%%% COMPARE MATCH WITH ORIGINAL \\bibitem:')
		for line in critical_entries[i]:gmatch('(.-)\n') do
			if not line:find('^%c*$') then
				table.insert(new, '%%' .. line)
			end
		end
		-- Extract label.
		local label = critical_entries[i]:match('\\bibitem%b{}')
		local escaped_label = F.escape_lua_pattern(label)
		-- Paste original entry.
		table.insert(new, '\n' .. label)
		bib = bib:gsub(escaped_label, table.concat(new, '\n'))
	end
  -- Mark each unmatched \bibitem.
  for i = 1, #unmatched_labels do
    local old = {
      '\\bibitem[%%\n%s]*{',
      F.escape_lua_pattern(unmatched_labels[i]),
      '}'    
    }
    local new = {
      '%%%% EDIT AND SORT (!) UNMATCHED ENTRY:\n',
      '\\bibitem{', unmatched_labels[i], '}'      
    }
    bib = bib:gsub(table.concat(old), table.concat(new))
  end
	-- Overwrite bbl file.
	F.write_file(bbl_path, bib)
end

-- ******
-- STEP 1:
-- Check all \bibitem against the AMS MRef database.
-- For each \bibitem there is either
-- (a) a match,
-- (b) no match or
-- (c) a match but there is a suspicion that the match is incorrect
-- ("critical case").
-- Collect all entries in a bib file.

mref_bibliography()

-- ******
-- STEP 2:
-- (a) Create a temporary tex file with nothing more than
-- \nocite{*} and \bibliography{BIB FILE}.
-- (b) Run latex and bibtex to create a bbl file.
-- (c) For each critical case, add the original \bibitem to the bbl file (as a comment).

create_bbl_output()
add_critical_entries()

-- ******
-- STEP 3:
-- Remove all temporary files.

local rm_ext = {
 	'.bib',
	'.aux',
	'.blg',
	'.dvi',
	'.log',
	'.tex'
}
for i = 1, #rm_ext do
	os.remove(output_path .. rm_ext[i])
end

-- End of file.
