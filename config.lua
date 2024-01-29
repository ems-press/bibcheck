--- Fixed configuration.

local M = {}

--- Default bibstyle.
M.bibstyle = 'ems'

--- Query zbMATH?
M.checkzbMATH = true

--- Threshold for zbMATH relevance score: \Zbl will be inserted into \bibitems only above this score,
--- otherwise it will only be included in the comment for the zbMATH entry
M.ZblRelevanceScoreThreshold = 5.9

--- Query Crossref?
M.checkCrossref = true
-- false -- true

--- Query arXiv?
M.checkArXiv = true
-- false -- true

--- Query Zbl fro Numdam?
M.checkNumdam = false
-- false -- true

--- Query MathSciNet for TeX (as comment)?
M.checkMRTeX = true

--- Whether save NOTEs from MathSciNet matches as a comment
M.saveMRNote = true

--- Whether check MathSciNet with naked bibitem
M.checkMRnaked = true

--- Whether (ProQuest) Theses should be proper phdthesis .bib entries (w/o publisher and url)
--- [or just include the original note (containing thesis info and school) as (fake) series]
M.bookThesisAsPhDThesis = true

--- Contact for Crossref (optional)
M.mailto = false
--M.mailto = 'XXX@example.com'

--- Output file suffix.
M.suffix = '_bibchecked'

M.remove_files = {
  '.bib',
  '.bbl',
  '.aux',
  '.log',
  '.dvi',
  '.blg',
}

--- MathSciNet settings.
--- N.B.: dataType=tex or dataType=bibtex (or mathscinet).
M.mathscinet = 'https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref='
M.mmathscinet = 'https://mathscinet.ams.org/mathscinet-mref?dataType=tex&ref='

--- zbMATH settings.
--- Removing "f=latex" increases the hit rate; see email by Fabian Müller (zbMATH)
--- sent 20 Sep 2021.
M.zbmath = 'https://zbmath.org/citationmatching/match?q='
--zbmath = 'https://zbmath.org/citationmatching/match?f=latex&q='

--- Crossref settings
--- See https://github.com/CrossRef/rest-api-doc
if M.mailto then
  M.crossref = 'https://api.crossref.org/works?rows=1&sort=score&order=desc&mailto='
    ..M.mailto..'&query.bibliographic='
else
  M.crossref = 'https://api.crossref.org/works?rows=1&sort=score&order=desc&query.bibliographic='
end

M.arxivapi = 'http://export.arxiv.org/api/query?id_list='

--M.arxivapiq = 'http://export.arxiv.org/api/query?search_query='
M.arxivapiq = 'http://export.arxiv.org/api/query?sortBy=relevance&start=0&max_results=1&search_query='

M.MRefsCSV = 'journal_abbreviations_mathematics.csv' -- annserb.csv, annser.csv
M.MRefsCSVURL = 'https://abbrv.jabref.org/journals/journal_abbreviations_mathematics.csv' -- annserb.csv, annser.csv

return M

-- End of file.