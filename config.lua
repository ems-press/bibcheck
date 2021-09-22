--- Fixed configuration.

local M = {}

--- Default bibstyle.
M.bibstyle = 'emss'

--- Add zbMATH IDs?
M.printZbl = true

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

--- MathSciNet and zbMATH settings.
M.database = {
	-- N.B.: dataType=tex or dataType=bibtex (or mathscinet).
	mref = 'https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref=',
	-- zbl = 'https://zbmath.org/citationmatching/match?f=latex&q='
  zbl = 'https://zbmath.org/citationmatching/match?q='
}

return M

-- End of file.