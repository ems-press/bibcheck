--- This is Bibcheck.
-- version 1.4 (2024-01-18)

-- authors:
-- Simon Winter [winter@ems.press]
-- Tobias Werner [werner@wissat-pc.de]
-- Tamas Bori [bori@services.ems.press]

-- tested on
--  Windows 7 + Lua 5.1.5 + Wget 1.21.3
--  Windows 10 + Lua 5.1.5 + WGeT 1.21.1
--  Linux + Lua 5.4.4
--  Mac + Lua 5.4

-- See 'bibcheck-manual.pdf' on how to use this script.

local lfs = require 'lfs'

-- Add path of main file to package path.
local path = arg[0]
path = path:gsub('(.-)bibcheck.lua$', '%1')
package.path = path .. '?.lua;' .. package.path

local F = require 'functions'
local C = require 'config'
local json = require 'dkjson'
local ftcsv = require 'ftcsv'

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
local output = input:gsub('%s+','_') .. C.suffix

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
local MR_matched_TeX = {}
local MR_note = {}
-- Table indicates if the label of bibitems[i] contains space characters (true) or not (false).
local Space_in_label = {}

--------------------------------------------------------------------------------
-- Main functions:

-- Create BIB file.
local function make_bib()
  -- Remove comments and collect all \bibitem in a table.
  bibitems = F.split_at_bibitem(F.remove_comments(old_bibl))
  local all_labels = {}
  local new_entry_TeX
  local MR_number
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
  -- processing abbreviated titles CSV
  local MRefsAbbr = {}
  local UnabbrSeries, UnabbrSeries_naked
  local CSVstring = ''
  local MRefsAbbrevs, MRefsAbbrevsHeaders
  ---- if CSV doesn't exists or older than 180 days, trying to download it...
  if (not F.file_exists(path..C.MRefsCSV)) or lfs.attributes(path..C.MRefsCSV, 'modification')+15552000 < os.time() then
    CSVstring = F.execute('Downloading abbrev. db...', false,
      'wget -qO-', F.quote(C.MRefsCSVURL))
    if CSVstring~='' and CSVstring~=nil then
      local csvFileToSave,pcallError = io.open(path..C.MRefsCSV, "wb")
      if csvFileToSave==nil then
        print("! Couldn't write "..C.MRefsCSV..":")
        print(pcallError)
      else
        local csvFileTiSaveWrite = csvFileToSave:write(CSVstring)
        csvFileToSave:close()
      end
    end
    if CSVstring~='' and CSVstring~=nil then
      MRefsAbbrevs, MRefsAbbrevsHeaders = ftcsv.parse(CSVstring, ",", {headers=false,loadFromString=true});
    elseif F.file_exists(path..C.MRefsCSV) then
      print('...unsuccessful, using old csv')
      MRefsAbbrevs, MRefsAbbrevsHeaders = ftcsv.parse(path..C.MRefsCSV, ",", {headers=false})
    else
      print("...unsuccessful, won't abbrev. unabbreviated series titles")
    end
  else --if CSV file exists...
    MRefsAbbrevs, MRefsAbbrevsHeaders = ftcsv.parse(path..C.MRefsCSV, ",", {headers=false})
  end
  if type(MRefsAbbrevs)=='table' and #MRefsAbbrevs then
    for _, MRefsRow in pairs(MRefsAbbrevs) do
      MRefsAbbr[string.lower(MRefsRow[1])]=MRefsRow[2]
    end
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
    local ret_TeX
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
    MR_matched_TeX[i] = ''
    MR_note[i] = ''
    ret = F.execute('Checking MathSciNet for \\bibitem '..i..' of '..#bibitems, false,
      'wget -qO-', F.quote(C.mathscinet .. F.escapeUrl(C.checkMRnaked and bibitem_naked or bibitem)))
--    new_entry
    local crossref
    -- IF MathSciNet match found
    if ret:find('%* Matched %*') then
      new_entry = ret:match('<pre>(.-)</pre>')
      -- Correct some 'mistakes' in the BibTeX entry.
      new_entry = F.normalizeTex(new_entry)
      if C.saveMRNote then
        MR_note[i] = new_entry:match('[Nn][Oo][Tt][Ee]%s*%=%s*{(.-)}%,?')
      end
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
      if C.checkMRTeX then
       ret_TeX = F.execute('Saving MathSciNet TeX as comment for \\bibitem '..i..' of '..#bibitems, false,
       'wget -qO-', F.quote(C.mmathscinet .. F.escapeUrl(C.checkMRnaked and bibitem_naked or bibitem)))
       if ret_TeX:find('%* Matched %*') then
        new_entry_TeX = ret_TeX:match('<tr><td align%=%"left%">([%a%{\\%$].-)</td></tr>')
        -- Correct some 'mistakes' in the (Bib)TeX entry.
        if new_entry_TeX~='' and new_entry_TeX~=nil then
          MR_matched_TeX[i] = new_entry_TeX:gsub('\n',' ') -- F.normalizeTex(new_entry_TeX)
        end
       end
      end
    -- IF no MathSciNet match found
    else
-- check if entry has arXiv no.
      if C.checkArXiv then
        arxiv = F.get_arxiv(bibitem,bibitem_naked) -- bibitem_naked
      end
      -- Send entry to Crossref.
      if C.checkCrossref then
        crossref = F.get_crossref(bibitem_naked)
      end
      -- Remove leading spaces and empty lines from original entry.
      -- Note: Don't add Crossref's DOI to BibTeX entry, only as comment; see add_comments().
      local t = {}
      if arxiv ~= '' then
        MR_matched[i] = true
        t = {'@misc {', labels[i], ',\n',arxiv, ',', F.zbl_ID(zbl_matches[i]),'}'}
      else
        -- Save entry as 'unmatched'.
        MR_matched[i] = false
        t = {'@misc {', labels[i], ',\n NOTE = {', original, '},', F.zbl_ID(zbl_matches[i]), '\n','}'}
      end
      new_entry = table.concat(t)
    end
    crossref_matches[i] = crossref
    new_entry=new_entry:gsub('([Pp][Uu][Bb][Ll][Ii][Ss][Hh][Ee][Rr]%s*%=*%s*{[^}]+a?}?}?[nNuU][gGsS][eE][rR])[%s%-]+[Vv][eE][rR][lL][aA][gG]','%1')
    new_entry=new_entry:gsub('([Pp][Aa][Gg][Ee][Ss]%s*%=*%s*[^}]+)[AaPp][rRaA][tTpP][%.ieE]?[cCrR]?[lL]?[eE]?[%s%~]*[nN]?[oOuU]?[mM%.]?[bB]?[eE]?[rR]?[%s%~]*([%a%d%.%-]+)[%s%.]*%,?[%a%d%s%.%~%+%,]*}','%1article no.~%2}')
    new_entry=new_entry:gsub('([Pp][Uu][Bb][Ll][Ii][Ss][Hh][Ee][Rr]%s*%=*%s*{[^}%]]+)%[([^%]]+)%]','%1%2')
    new_entry=new_entry:gsub('([Yy][Ee][Aa][Rr]%s*%=*%s*{[^}%]]*)%[[^%]]+%]%s*\\copyright%s*(%d+)','%1%2')
    new_entry=new_entry:gsub('([Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{[^\n%[]+)[^%S\n]+%[[^%]]+%]','%1') -- {[^}%]]+)%s+%[[^%]]+%]
    UnabbrSeries=''
    UnabbrSeries_naked=''
    if new_entry:match('[Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{%s*([^\n]-)[% \t%.%,]*[Nn]?[oO]?%.?[^%S\n]*%d+[^%S\n]*}') then
      if not new_entry:match('[Vv][Oo][Ll][Uu][Mm][Ee]%s*%=%s*{') then
        new_entry=new_entry:gsub('([Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{%s*[^\n]-)[% \t%.%,]*[Nn]?[oO]?%.?[^%S\n]*(%d+)[^%S\n]*}','%1},\nVOLUME = {%2}')
      else
        UnabbrSeries=new_entry:gsub('^.*[Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{%s*([^\n]-)[% \t%.%,]*[Nn]?[oO]?%.?[^%S\n]*%d+[^%S\n]*}[% \t%,]*\n.*$','%1') -- ([^}%]%.]+)
      end
    end
    if (UnabbrSeries=='' or UnabbrSeries==nil) and new_entry:match('[Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{%s*([^\n]-)[% \t%.]*}') then -- ([^}%]%.]+)
      UnabbrSeries=new_entry:gsub('^.*[Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{%s*([^\n]-)[% \t%.]*}[% \t%,]*\n.*$','%1') -- ([^}%]%.]+)
    end
    if UnabbrSeries~='' and UnabbrSeries~=nil then
-- print(UnabbrSeries) -- matched (unabbreviated?) series title...
      UnabbrSeries_naked=F.undress(UnabbrSeries)
      if MRefsAbbr[string.lower(UnabbrSeries_naked)]~='' and MRefsAbbr[string.lower(UnabbrSeries_naked)]~=nil then
--        new_entry=new_entry:gsub('([Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{)%s*([^\n]-)[% \t%.]*(}[% \t%,]*\n)','%1'..MRefsAbbr[UnabbrSeries]..'%3') -- ([^}%]%.]+)
        new_entry=new_entry:gsub('([Ss][Ee][Rr][Ii][Ee][Ss]%s*%=*%s*{)%s*('..F.escape_lua(UnabbrSeries)..')','%1'..MRefsAbbr[string.lower(UnabbrSeries_naked)]) -- ([^}%]%.]+)
      end
    end
    -- complete MR numbers with leading zeros
    MR_number=new_entry:gsub('^.*[Mm][Rr][Nn][Uu][Mm][Bb][Ee][Rr]%s*%=%s*{%s*(%d+)%s*}.*$','%1')
    if MR_number~='' and MR_number~=nil and MR_number:len()<7 then
      for j = 1, 7-MR_number:len() do
        new_entry=new_entry:gsub('([Mm][Rr][Nn][Uu][Mm][Bb][Ee][Rr]%s*%=%s*{)%s*(%d+)%s*(})','%10%2%3')
      end
    end
    if new_entry:match('[Nn][Oo][Tt][Ee]%s*%=%s*{[^\n{]*[Tt][{}]?[hH][eE][sS][iI][sS][^}]*%-') and (new_entry:match('^%s*%@book%s*{') or new_entry:match('[Pp][rR][oO][Qq][uU][eE][sS][tT]')) then  -- {[^}%]]+)%s+%[[^%]]+%]
-- '([SsMmNn][EeRrOo][RrCcTt][IiLlEe][EeAa]?[Ss]?[Ss]?%s*%=%s*{[^\n{]*[Tt][{}]?[hH][eE][sS][iI][sS])'
      if C.bookThesisAsPhDThesis then
        new_entry=new_entry:gsub("^(%s*%@)%a+(%s*{)","%1phdthesis%2")
        new_entry=new_entry:gsub("([Nn][Oo][Tt][Ee]%s*%=%s*{[^\n{]*[Tt][{}]?[hH][eE][sS][iI][sS][^}]*[^%-])%-%-?%-?%s*([^%s%-][^}]+)}",'SCHOOL = {%2}')
        new_entry=new_entry:gsub("([Uu][Rr][Ll]%s*%=%s*%b{}%,?\n?",'')
      elseif not new_entry:match('[Se][Ee][Rr][Ii][Ee][Ss]%s*%=%s*{') then
        new_entry=new_entry:gsub("[Nn][Oo][Tt][Ee](%s*%=%s*%b{})",'SERIES%1')
      end
    end
    if new_entry:match("[Jj][Oo][Uu][Rr][Nn][Aa][Ll]%s*%=%s*{[Aa][sS][tT]{?\\%'%s*{?[eE]}?%s*}?[rR][iI][sS][qQ][uU][eE]%s*}") and new_entry:match('^%s*%@incollection%s*{') then
      new_entry=new_entry:gsub('^(%s*%@)incollection(%s*{)','%1article%2')
    end
    new_entry=new_entry:gsub("{%s*\\([rb][mf])%s+","\\math%1{")
    new_entry=new_entry:gsub("{%s*\\it%s+","\\mathit{")
    new_entry=new_entry:gsub("{%s*\\[fg][re][ar][km]%s+","\\mathfrak{")
    new_entry=new_entry:gsub("{%s*\\Bbb%s+","\\mathbb{")
    new_entry=new_entry:gsub("{%s*\\[Cc]al%s+","\\mathcal{")
    new_entry=new_entry:gsub("\\([rb][mf][%s{])","\\math%1")
    new_entry=new_entry:gsub("\\it([%s{])","\\mathit%1")
    new_entry=new_entry:gsub("\\[fg][re][ar][km]([%s{])","\\mathfrak%1")
    new_entry=new_entry:gsub("\\Bbb([%s{])","\\mathbb%1")
    new_entry=new_entry:gsub("\\[Cc]al([%s{])","\\mathcal%1")
    new_entry=new_entry:gsub("([VvNn][OoUu][LlMm][UuBb][MmEe][EeRr]%s*%=*%s*{)%s*[Nn][oO]%.%s*","%1")
    new_entry=new_entry:gsub("\\cprime%s*","'")
    new_entry=new_entry:gsub("\\polhk","\\k")
    new_entry=new_entry:gsub('([Jj][Oo][Uu][Rr][Nn][Aa][Ll]%s*%=*%s*{%s*%a.?)%s+','%1~')
    new_entry=new_entry:gsub('([Jj][Oo][Uu][Rr][Nn][Aa][Ll]%s*%=*%s*{[^}]+)%s+(%a.?)%s*}','%1~%2}')
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
      orig_bibitem = orig_bibitem:gsub('%s+',' ')
      -- Paste original entry and zbMATH entry.
      if alphabetic then
        s = '\\bibitem(%b[]){'..F.escape_lua(labels[i])..'}(.-)\n\n'
        r = {'\\bibitem%1{', labels[i], '}%2 ',
             '\n%%__ Original:\n', F.escape_percent(orig_bibitem),
             F.mr_note_info(MR_note[i]),
             F.mr_tex_info(MR_matched_TeX[i]),
             F.zbl_info(zbl_matches[i]), F.crossref_info(crossref_matches[i]), '\n\n'}
      else
        s = '\\bibitem{'..F.escape_lua(labels[i])..'}(.-)\n\n'
        r = {'\\bibitem{', labels[i], '}%1 ',
             '\n%%__ Original:\n', F.escape_percent(orig_bibitem),
             F.mr_note_info(MR_note[i]),
             F.mr_tex_info(MR_matched_TeX[i]),
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
  local new_bibl_two = new_bibl:match('(\\newcommand{\\etalchar}%[1%]{%$%^{%#1}%$}%s*\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')
  if new_bibl_two~="" and new_bibl_two~=nil then
    new_bibl=new_bibl_two
  else
    new_bibl = new_bibl:match('(\\begin%s*{thebibliography}.-\\end%s*{thebibliography})')
  end
  -- Escape percent character in replacement string.
  local r = F.escape_percent(new_bibl)
  local eprintfind = '\\providecommand%s*{\\eprint}[^\n]+\n'
----  local eprintreplacement = '\\providecommand{\\eprint}%[2%]%[%]{\\url{#2}}\n\\renewcommand{\\eprint}%[2%]%[%]{\\expandafter\\if#1\\relax\\url{#2}\\else\\arXiv{#1}\\fi}\n'
--  local eprintreplacement = '\\providecommand{\\eprint}[2][]{\\url{#2}}\n\\renewcommand{\\eprint}[2][]{\\expandafter\\if#1\\relax\\url{#2}\\else\\arXiv{#1}\\fi}\n'
  local eprintreplacement = '\\providecommand*\\arxiv{}\n\\makeatletter\n\\renewcommand\\arxiv[1]{\\expandafter\\ifx\\csname ems@maybebreak\\endcsname\\relax arXiv:\\allowbreak\\href{https://arxiv.org/abs/#1}{#1}\\else\\ems@maybebreak[\\fontdimen2\\font]{arXiv:\\href{https://arxiv.org/abs/#1}{#1}}\\fi}\n\\makeatother\n\\providecommand*\\arXiv{}\n\\renewcommand*\\arXiv[1]{\\arxiv{#1}}\n'
  if r:find(eprintfind) then r=r:gsub('('..eprintfind..')','%1'..eprintreplacement) else r=r:gsub('\\bibitem',eprintreplacement..'\n\\bibitem',1) end
  r=r:gsub('\\eprint%[([^%]]+)%]{https?%:%/%/arxiv%.org%/abs%/[^}]+}','\\arXiv{%1}')
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