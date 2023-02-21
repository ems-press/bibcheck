--- This is Bibcheck.
-- version 1.3 (2023-02-21)

-- authors:
-- Simon Winter [winter@ems.press]
-- Tobias Werner [werner@wissat-pc.de]

-- tested on
--  Windows 10 + Lua 5.1.5 + WGeT 1.21.1
--  Linux + Lua 5.4.4

-- See 'bibcheck-manual.pdf' on how to use this script.

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

-- TeX file input path.
local input_path = arg[1]
-- Bibliography style (for example, 'amsplain').
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

-- Name for all (temporary and final) files created by this script.
local output = input .. C.suffix

-- Content of the original TEX file.
local texcode = F.read_file(input .. '.tex')

-- Bibliography of the original TEX file.
local old_bibl = texcode:match('(\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')
assert(old_bibl, 'No bibliography found.')

local new_bibl = false
local bibitems = {}
local bibtex_entries = {}
local zbl_matches = {}
local crossref_matches = {}

-- All \bibitem labels.
local labels = {}
-- All \bibitem without optional argument.
local modifiedbibitems = {}
-- Table indicates if bibitems[i] is MathSciNet matched (true) or unmatched (false).
local MR_matched = {}
-- Table indicates if the label of bibitems[i] contains space characters (true) or not (false).
local Space_in_label = {}

--------------------------------------------------------------------------------
-- Main functions:

-- Create BIB file.
local function make_bib()
  -- Remove comments and collect all \bibitem in a table.
  bibitems = F.split_at_bibitem(F.remove_comments(old_bibl))
  local all_labels = {}
  -- Process each \bibitem, Part I.
  for i = 1, #bibitems do
    local bibitem = bibitems[i]
    -- Remove optional argument of \bibitem[.]{.} and spaces.
    bibitem = bibitem:gsub('\\bibitem[%%\n%s]*%b[][%%\n%s]*(%b{})', '\\bibitem%1')
    bibitem = bibitem:gsub('\\bibitem[%%\n%s]*(%b{})', '\\bibitem%1')
    modifiedbibitems[i] = bibitem
    -- Save the label.
    labels[i] = bibitem:match('\\bibitem%b{}')
    labels[i] = labels[i]:match('\\bibitem{(.-)}$')
    -- Check if two \bibitem have the same label (modulo capitalization).
    local label = labels[i]:lower() 
    assert(not all_labels[label], '\n\n%%%% ERROR: Label "'..label..'"'
      ..' (possibly with capital letters) appears twice. Fix it and run Bibcheck again.\n')
    all_labels[label] = i 
  end
  -- Process each \bibitem, Part II.
  for i = 1, #bibitems do
    local bibitem = modifiedbibitems[i]
    -- Replace space characters in the label by tilde.
    if labels[i]:find('%s')  then
      Space_in_label[i] = true
      labels[i] = labels[i]:gsub('%s', '')
    else
      Space_in_label[i] = false
    end
    -- Remove \bibitem{.}
    -- don't use labels[i] here because of 'magic characters' issue.
    bibitem = bibitem:gsub('\\bibitem%b{}', '')
    local original = bibitem:gsub('^[\n%s]+', '')
    bibitem = bibitem:gsub('\\newblock', ' ')
    bibitem = bibitem:gsub('[%s\t]+', ' ')
    -- Send entry to zbMATH.
    local ret
    local bibitem_naked = F.undress(bibitem)
    if C.checkzbMATH then
      ret = F.execute('Checking zbMATH for \\bibitem '..i..' of '..#bibitems, false,
        'wget -qO-', F.quote(C.zbmath .. F.escapeUrl(bibitem_naked)))
      -- unpack the JSON ouput of zbMATH:
      local function isTable(t) return t and type(t) == 'table' end
      ret = ret and json.decode(ret)
      ret = isTable(ret) and ret.results
      -- Most often, the zbMATH's syntax for "no match" is:
      -- "results": []
      ret = isTable(ret) and table.unpack(ret)
      -- But sometimes it's:
      -- "results": [ {} ]
      -- So we ensure next that 'ret' has an entry 'zbl_id'.
      if ret and not ret.zbl_id then ret = false end
    end
    zbl_matches[i] = ret
    -- Send entry to MathSciNet.
    ret = F.execute('Checking MathSciNet for \\bibitem '..i..' of '..#bibitems, false,
      'wget -qO-', F.quote(C.mathscinet .. F.escapeUrl(bibitem)))
    local new_entry
    local crossref
    -- IF MathSciNet match found
    if ret:find('%* Matched %*') then
      new_entry = ret:match('<pre>(.-)</pre>')
      -- Correct some 'mistakes' in the BibTeX entry.
      new_entry = F.normalizeTex(new_entry)
      -- Send entry to Crossref only if the BibTeX entry has no DOI value.
      if C.checkCrossref and not new_entry:find('DOI%s+=') then
        crossref = F.get_crossref(bibitem_naked)
      end
      --
      -- -- FAILED TEST [begin]
      -- -- Send the BibTeX entry from MathSciNet ('new_entry') to zbMATH. The goal is to get a
      -- -- higher hit rate at zbMATH. But their BibTeX interface doesn't work properly.
      -- -- Moreover, a disadvantage would be that we process mismatches from MathSciNet.
      -- if C.checkzbMATH then
      --   ret = F.execute('Checking zbMATH for \\bibitem '..i..' of '..#bibitems, false,
      --     'wget -qO-', F.quote('https://zbmath.org/citationmatching/match?bibtex&q='
      --     .. F.escapeUrl(new_entry)))
      -- unpack the JSON ouput of zbMATH:
      --   local function isTable(t) return t and type(t) == 'table' end
      --   ret = ret and json.decode(ret)
      --   ret = isTable(ret) and ret.results
      --   ret = isTable(ret) and table.unpack(ret)
      --   zbl_matches[i] = ret
      -- end
      -- -- FAILED TEST [end]
      --
      -- -- FAILED TEST [begin]
      -- -- Change label back to the original one, add ZBLNUMBER, and add Crossref-DOI.
      -- local t = {'{', labels[i], ',', F.zbl_ID(zbl_matches[i]), F.crossref_DOI(crossref)}
      -- -- FAILED TEST [end]
      --
      -- Change label back to the original one and add ZBLNUMBER.
      local t = {'{', labels[i], ',', F.zbl_ID(zbl_matches[i])}
      new_entry = new_entry:gsub('{MR%d+,', table.concat(t), 1)
      -- Save entry as 'matched'.
      MR_matched[i] = true
    -- IF no MathSciNet match found
    else
      -- Send entry to Crossref.
      if C.checkCrossref then
        crossref = F.get_crossref(bibitem_naked)
      end
      -- Remove leading spaces and empty lines from original entry.
      -- Note: Don't add Crossref's DOI to BibTeX entry, only as comment; see add_comments().
      local t = {'@misc {', labels[i], ',\n NOTE = {', original, '},', F.zbl_ID(zbl_matches[i]), '\n}'}
      new_entry = table.concat(t)
      -- Save entry as 'unmatched'.
      MR_matched[i] = false
    end
    crossref_matches[i] = crossref
    table.insert(bibtex_entries, new_entry)
  end
  F.write_file(output .. '.bib', table.concat(bibtex_entries, '\n\n'))
end

-- Create BBL file.
local function make_bbl()
  local t = {
    '\\documentclass{article}',
    '\\usepackage[utf8]{inputenc}',
    '\\usepackage{amssymb}',
    '\\newcommand\\MR[1]{MR~#1}',
    '\\newcommand\\Zbl[1]{Zbl~#1}',
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

-- Add to the BBL file for each \bibitem
-- either the original \bibitem (as a comment) if there was a MathSciNet match
-- or a warning that there was no MathSciNet match.
-- Also add the zbMATH ID and entry.
local function add_comments()
  -- Read content of the BBL file.
  new_bibl = F.read_file(output .. '.bbl')
  -- Does the BST file create alphabetic or numeric labels?
  local alphabetic = new_bibl:find('\\bibitem%b[]')
  -- Insert (another) blank line before each \bibitem
  -- and at the very end (i.e. before \end{thebibliography}).
  new_bibl = new_bibl:gsub('\\bibitem', '\n\\bibitem')
  new_bibl = new_bibl:gsub('\\end%s*{thebibliography}', '\n\\end{thebibliography}')
  for i = 1, #bibitems do
    local orig_bibitem = '%%'
    local s -- search
    local r -- replace
    if MR_matched[i] then
      local bibitem = bibitems[i] .. '\n'
      for line in bibitem:gmatch('(.-)\n') do
        if not line:find('^%c*$') then
          orig_bibitem = orig_bibitem..' '..line
        end
      end
      -- Paste original entry and zbMATH entry.
      if alphabetic then
        s = '\\bibitem(%b[]){'..F.escape_lua(labels[i])..'}(.-)\n\n'
        r = {'\\bibitem%1{', labels[i], '}%2 ',
             '\n%%__ Original:\n', F.escape_percent(orig_bibitem),
             F.zbl_info(zbl_matches[i]), F.crossref_info(crossref_matches[i]), '\n\n'}
      else
        s = '\\bibitem{'..F.escape_lua(labels[i])..'}(.-)\n\n'
        r = {'\\bibitem{', labels[i], '}%1 ',
             '\n%%__ Original:\n', F.escape_percent(orig_bibitem),
             F.zbl_info(zbl_matches[i]), F.crossref_info(crossref_matches[i]), '\n\n'}
      end
    else -- unmatched entry
      if alphabetic then
        s = '\\bibitem(%b[]){'..F.escape_lua(labels[i])..'}(.-)\n\n'
        r = {'%%%% EDIT AND SORT (!) UNMATCHED ENTRY:\n',
             '\\bibitem%1{'..labels[i]..'}%2 ',
             F.zbl_info(zbl_matches[i]), F.crossref_info(crossref_matches[i]), '\n\n'}
      else
        s = '\\bibitem{'..F.escape_lua(labels[i])..'}(.-)\n\n'
        r = {'%%%% EDIT AND SORT (!) UNMATCHED ENTRY:\n',
             '\\bibitem{'..labels[i]..'}%1 ',
             F.zbl_info(zbl_matches[i]), F.crossref_info(crossref_matches[i]), '\n\n'}
      end
    end
    new_bibl = new_bibl:gsub(s, F.space_warning(Space_in_label[i])..table.concat(r), 1)
  end
  new_bibl = new_bibl:gsub('\n\n\n', '\n\n')
  -- Overwrite BBL file.
  F.write_file(output .. '.bbl', new_bibl)
end

-- Create TEX file.
local function make_tex()
  -- Escape Lua patterns in search string.
  local s = F.escape_lua(old_bibl)
  -- Remove \providecommand{\bysame} etc. from replacement string.
  new_bibl = new_bibl:match('(\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')
  -- Escape percent character in replacement string.
  local r = F.escape_percent(new_bibl)
  -- Replace original bibliography with modified one.
  local out = texcode:gsub(s, r, 1)
  -- Overwrite TEX file.
  F.write_file(output .. '.tex', out)
end

-- Remove temporary files.
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
make_tex()

-- ******
-- STEP 5:
-- Remove all temporary files.
remove_temp()

lfs.chdir(cwd) -- change back to current working directory

-- End of file.