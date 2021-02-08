--- Fixed configuration.

local M = {}

--- Default bibstyle.
M.bibstyle = 'amsplain'

--- Output file suffix.
M.suffix = '_bibchecked'

--- MRef settings.
M.mref = {
	response = 'mref.html',
	-- N.B.: dataType=tex or dataType=bibtex (or mathscinet).
	url = 'https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref='
}

return M

-- End of file.
