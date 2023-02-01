--- Fixed configuration.

local M = {}

--- Default bibstyle.
M.bibstyle = 'emss'

--- Query zbMATH?
M.checkzbMATH = true

--- Query Crossref?
M.checkCrossref = false

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

return M

-- End of file.