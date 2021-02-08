Simon Winter [winter@ems.press] 
2021-02-08

# How to install bibcheck on Windows

## Install bibcheck
* Create a new folder for bibcheck. The whole path must not contain any spaces!!!
* Copy the two files 'bibcheck.lua' and 'EMS_functions.lua' into the bibcheck folder.

## Create file 'bibcheck.bat'
* Create, using any text editor, a file 'bibcheck.bat' in the bibcheck folder.
* Paste the 3 lines given below into the file. 
  "C:\...\bibcheck.lua" is the full path of bibcheck.lua.
  'jems' is the name of the bst file. Could also be 'amsplain' etc.
* Create a desktop shortcut of that batch file.

@echo off
lua "C:\...\bibcheck.lua" %~f1 jems
pause

## Install Lua
* Download 'LuaForWindows_v5.1.5-52.exe' here:
  https://github.com/rjpcomputing/luaforwindows/releases/tag/v5.1.5-52
* Run the exe file and always click "accept/next".

## Install WGet
* Download 'wget-1.11.4-1-setup.exe' here:
  https://sourceforge.net/projects/gnuwin32/files/wget/1.11.4-1/
  (The file name must not contain "src"!)
* Run the exe file and always click "accept/next".
* Add WGet to the PATH on Windows:
  (1) Open the Start Search, type in "env" and choose "Edit the system environment variables" ("Systemumgebungsvariablen bearbeiten").
  (2) Click the "Environment Variables" button ("Umgebungsvariablen").
  (3) Under the "System Variables" section (the lower half), find the row with "Path" in the first column and click edit.
  (4) Click "New" and type in the new path, e.g. C:\Program Files (x86)\GnuWin32\bin
   (5) Dismiss all of the dialogs by choosing OK. Your changes are saved.
* You may use WGet in the Windows Command Shell:
  >> wget --no-check-certificate -O OUTPUTFILE 
  "https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref='BIBITEM'" 2>&1

# How to use bibcheck on Windows

## Case 1: The tex file contains \begin{thebibliography}
* Open the Windows Command Shell, go to the paper's directory and write
  >> lua C:\...\bibcheck.lua FILENAME.tex BSTFILENAME [alpha]
  
  Important: You must use a bst file that creates alphabetic labels! However, those
  alphabetic labels are replaced by numeric ones, unless you use the parameter 'alpha'.
  You may add a path to the tex file (use backslahes; no leading backslash).
  
  >> lua C:\tools\bibcheck\bibcheck.lua main.tex amsalpha
  >> lua C:\tools\bibcheck\bibcheck.lua folder\main.tex amsalpha alpha
    
  Alternatively, use bibcheck.bat: Drag and drop the tex file onto its desktop shortcut.
* Open one of the files FILENAME-REFERENCES.bbl or FILENAME-REFERENCES.tex. 
  It contains two kinds of \bibitem:
  (a) UNMATCHED ENTRY. 
      If there is no match in MathSciNet, format the original \bitem and 
      sort it in the bibliography according to the known criteria. 
  (b) MATCH.
      A few matches are unfortunately incorrect. So compare each 'match' with the original 
      \bibitem which is added in comments.
          
## Case 2: The tex file uses a bib file.
* Run bibtex and copy the bbl content into the tex file.
* Proceed as in CASE 1.
