--- This is bibcheck.
--
-- @author Simon Winter [winter@ems.press]
-- @author Tobias Werner [werner@wissat-pc.de]
--
-- @release 0.8.4 (2021-02-05)

-- tested on
--   Windows 10 + Lua 5.1.5
--   Linux + Lua 5.4.2
--
-- >> lua bibcheck.lua FILENAME.tex BSTFILENAME

local lfs = require 'lfs'
local pl_file = require 'pl.file'

-- Add path of main file to package path.
local path = arg[0]
-- TODO path is used in CERMINE settings if jar is in the same folder!
path = path:gsub('(.-)bibcheck.lua$', '%1')
package.path = path .. '?.lua;' .. package.path
local G = require 'EMS_functions'

--- CERMINE settings.
local cermine = {
	on = true,
  --on = false,
	jar = path .. 'cermine-impl-1.13-jar-with-dependencies.jar',
	com = 'pl.edu.icm.cermine',
	ref = 'bibref.CRFBibReferenceParser -format bibtex -reference '
}

--- TeX file input path.
local input_path = arg[1]
--- Bibliography style (for example, "amsplain").
local bst = arg[2] or 'amsplain'

local folder, input
local texpattern = '(.-)%.tex$'
-- Check if input_path is a full path (with separator)
-- or a file name (no separator).
if input_path:find(G.sep) then
	folder, input = input_path:match(G.path('(.+)', texpattern))
else
	folder = lfs.currentdir()
	input = input_path:match(texpattern)
end
assert(input, 'File name not recognized.')

--- MRef settings.
local mref = {
	path = G.path(folder, 'MRef_response.html'),
	-- N.B.: dataType=tex or dataType=bibtex (or mathscinet).
	url = 'https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref='
}

--- Name for all (temporary and final) files created by this script.
local output = input .. '-REFERENCES'
--- Output path.
local output_path = G.path(folder, output)

-- TODO global? (cannot be modified)
--- Content of the original TeX file.
local texcode = pl_file.read(input_path)
--- Complete bibliography string of the original TeX file.
local bibcode = false

-- SIMON: Ich würde diese Unterscheidung gerne weiterhin haben und habe sie daher eingebaut (s.u.).
--- All critical  and all unmatched entries.
local critical_entries = {}
local unmatched_entries = {}

--------------------------------------------------------------------------------

-- Functions:

--- Check entry with MathSciNet.
-- @tparam string entry
-- @treturn string bibtex entry
local function check_mref(entry)
	G.execute('Checking MathSciNet', true,
		'wget', ' --no-check-certificate', ' -O ', mref.path,
		' ', G.quote_outer(mref.url .. G.quote_inner(entry)),
		' 2>&1'
	)
	-- Read HTML code (if any)
	local response = pl_file.read(mref.path)
	if response:find('%* Matched %*') then
		local bibtex = response:match('<pre>(.-)</pre>')
		if bibtex then
			return bibtex
		end
	end
	return false
end

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
	local p = '\\begin%s*{thebibliography}(.-)\\end%s*{thebibliography}'
	local bib = tex:match(p)
	assert(bib, 'No bibliography found.')
	return bib
end

--- Collect all \bibitem in a table.
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

--- Try to structure unmatched entry.
-- @tparam string entry
-- @treturn string bibtex entry
local function structure_unmatched(entry)
	if cermine.on then
-- 		print('Raw entry: ' .. entry)
		-- TODO delete all braces for valid TeX code?
		entry = entry:gsub('[{}]', '')
		local r = G.execute('CERMINE', true,
			'java -cp ', cermine.jar, ' ',
			cermine.com, '.', cermine.ref, G.quote_outer(entry),
			' 2>&1'
		)
-- 		print('CERMINE output: ' .. r)
		return r
	end
	return false
end

--------------------------------------------------------------------------------

-- Main functions:

--- Check all \bibitem against the AMS MRef database.
local function mref_bibliography()
	-- Select the bibliography.
	bibcode = select_bibliography(texcode)
	-- Remove comments.
	local bib = G.remove_comments(bibcode)
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
		local label = bibitem:match('\\bibitem%b{}')
		-- don't use label here because of 'magic characters' issue.
		replace('\\bibitem%b{}', '')
		label = label:match('\\bibitem{(.-)}$')
		-- Save original entry; delete leading spaces and empty lines.
		local original = bibitem:gsub('^[\n%s]+', '')
		-- Replace \newblock with space and spaces with "%20"
		replace('\\newblock', ' ')
		replace('[%s\t]+', '%%20')
		-- Check entry with www.ams.org/mathscinet-mref.
		local match = check_mref(bibitem)
		if match then
			-- Matched entry:
			-- Correct some 'mistakes' in the BibTeX entry.
			local new = correct_bibtex(match)
			-- Change label back to the original one.
			tab[i] = new:gsub('{MR%d+', '{' .. label, 1)
			-- Check whether the entry is a critical case.
			if critical_entry(original, new) then
        local s = '\\bibitem{' .. label .. '}\n' .. original
				table.insert(critical_entries, s)
			end
		else -- unmatched entry
			local structured = structure_unmatched(original)
			if structured then
				-- Correct some 'mistakes' in the BibTeX entry.
				local new = correct_bibtex(structured)
				-- Normalize entry type to @article,
				-- and change label back to the original one.
				tab[i] = new:gsub('^(@%a+){[^,]+', '@article{' .. label, 1)
			else -- = no Cermine = no alphabetical order
				-- Unmatched and unstructured entry:
				tab[i] = '@misc {' .. label .. ',\n'
					.. ' NOTE = {' .. original .. '},\n}'
			end
      local s = '\\bibitem{' .. label .. '}\n' .. original
      table.insert(unmatched_entries, s)
		end
		-- Remove mref.path.
		os.remove(mref.path)
	end
	G.write_file(output_path .. '.bib', table.concat(tab, '\n\n'))
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
-- 	print(folder)
	G.write_file(tex_path, table.concat(t, '\n'))
	-- Compile it.
	G.execute('LaTeX', true,
		'latex',
		' -interaction=nonstopmode',
		' -halt-on-error',
		' -output-directory=', folder,
		' ', tex_path,
		' 2>&1'
	)
	-- Save current working directory.
	local cwd = lfs.currentdir()
	-- Run bibtex.
	lfs.chdir(folder)
	G.execute('BibTeX', true, 'bibtex ', output)
	-- Change back to current working directory.
	lfs.chdir(cwd)
end


local function add_comments(bib, tab, text)
  for i = 1, #tab do
		-- Add % at the beginning of each line.
		tab[i] = tab[i] .. '\n'
		local new = {}
		table.insert(new, text)
		for line in tab[i]:gmatch('(.-)\n') do
			if not line:find('^%c*$') then
				table.insert(new, '%%' .. line)
			end
		end
		-- Extract label.
		local label = tab[i]:match('\\bibitem%b{}')
		local escaped_label = G.escape_lua_pattern(label)
		-- Paste original entry.
		table.insert(new, '\n' .. label)
		bib = bib:gsub(escaped_label, table.concat(new, '\n'))
  end
	return bib
end  

--- For each critical or unmatched case, add the original \bibitem to the bbl file.
local function add_original_bibitem()
	local bbl_path = output_path .. '.bbl'
	-- Read content of the bbl file.
	local bib = pl_file.read(bbl_path)
	assert(bib, 'No BibTeX output (bbl) file found.')
  -- SIMON: Diesen Block habe ich geändert, um zwischen "critial" und "unmatched" zu unterscheiden!
  bib = add_comments(bib, critical_entries, '%%%% Double-check critical case.\n%%%% Original entry:')
  bib = add_comments(bib, unmatched_entries, '%%%% Edit unmatched entry.\n%%%% Original entry:')  
	-- Overwrite bbl file.
	G.write_file(bbl_path, bib)
end

--- Create output tex file.
local function create_tex_output()
	-- TODO global variable or return value + argument ...
	-- instead of opening file again? ...
	-- definitions (\providecommand) should be no problem
	-- Read content of the modified bbl file.
	local bib = pl_file.read(output_path .. '.bbl')
	assert(bib, 'No BibTeX output (bbl) file found.')
	local bbl = select_bibliography(bib)
	-- Escape Lua patterns in search string.
	local s = G.escape_lua_pattern(bibcode)
-- 	print('SEARCH:' .. s)
	-- Escape percent character in replacement string.
	local r = bbl:gsub('%%', '%%%%')
-- 	print('REPLACE: ' .. r)
	-- Replace original bibliography with modified one.
	local out = texcode:gsub(s, r, 1)
	-- Overwrite tex file.
	G.write_file(output_path .. '.tex', out)
end


-- ******
-- STEP 1:
-- Check all \bibitem against the AMS MRef database.
-- For each \bibitem there is either
-- (a) a match,
-- (b) no match or
-- (c) a match but there is a suspicion that
-- the match is incorrect ("critical case").
-- Collect all entries in a bib file.

mref_bibliography()

-- ******
-- STEP 2:
-- (a) Create a temporary tex file with not much more than
-- \nocite{*} and \bibliography{BIB FILE}.
-- (b) Run latex and bibtex to create a bbl file.
-- (c) For each critical or unmatched case, add the original \bibitem to the bbl file.
-- (d) Replace the bibliography in the original tex file by the new bibliography.

create_bbl_output()
add_original_bibitem()
create_tex_output()

-- ******
-- STEP 3:
-- Remove all temporary files.

local rm_ext = {
	'.aux',
-- 	'.bbl',
	'.bib',
	'.blg',
	'.dvi',
	'.log',
-- 	'.tex'
}
for i = 1, #rm_ext do
	os.remove(output_path .. rm_ext[i])
end

-- End of file.
