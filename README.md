Simon Winter [winter@ems.press] 
2021-05-22

# How to install bibcheck (on Windows)

## Install bibcheck
* Create a new folder for bibcheck. The whole path must not contain any spaces!
* Copy the 4 lua files (bibcheck, config, dkjson, functions) into the bibcheck folder.

## Install Lua (version 5.1 or higher)
* Download 'LuaForWindows_v5.1.5-52.exe' here:
  https://github.com/rjpcomputing/luaforwindows/releases/tag/v5.1.5-52
* Run the exe file and always click "accept/next".

## Install WGet (version 1.14 or higher)
* Download from https://eternallybored.org/misc/wget/ the EXE file of Version 1.21 (32-bit or 64-bit).
* Copy wget.exe to e.g. C:\Program Files (x86)\wget-1.21.1-1-win64\ or any other folder.
* Add WGet to the PATH on Windows:
    * Open the Start Search, type in "env" and choose "Edit the system environment variables" ("Systemumgebungsvariablen bearbeiten").
    * Click the "Environment Variables" button ("Umgebungsvariablen").
    * Under "System Variables" find the row with "Path" in the first column and click edit.
    * Click "New" and type in the new path, e.g. C:\Program Files (x86)\wget-1.21.1-1-win64
    * Dismiss all of the dialogs by choosing OK. Your changes are saved.
* To check if the installation was successful, open a command terminal (by typing "cmd" in the search menu) and type:
```
wget --help
```
or
```
wget --no-check-certificate -qO- "https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref=J.H.C. Whitehead, On 2-spheres in 3-manifolds. Bull. Amer. Math. Soc. 64 (1958), 161--166"
```

# How to use bibcheck

## Case 1: The tex file contains \begin{thebibliography}
* Open the Command Terminal, go to the paper's directory and write
```
lua C:\...\bibcheck.lua FILENAME.tex BSTFILENAME
```
  You may add a path to the tex file (use backslahes; no leading backslash).
```
lua C:\tools\bibcheck\bibcheck.lua main.tex emsnumeric
lua C:\tools\bibcheck\bibcheck.lua folder\main.tex amsalpha
```
* Open the new file FILENAME_bibchecked.tex. It contains two kinds of \bibitem:
    * UNMATCHED ENTRY. 
    If no match in MathSciNet has been found, then manually format the original \bibitem
    and sort it in the bibliography according to the known criteria. 
    * MATCH.
    Most \bibitem's have a match in MathSciNet. Unfortunately, a few of them are incorrect. 
    So compare each 'match' with the original \bibitem (which is added as a comment).

* Note: To improve the result, you should first (i.e., before running 'bibcheck') replace all instances of \bysame (in the original tex file) by the respective authors.
* Note: You can skip the last argument (BSTFILENAME). Then the default style (defined in config.lua) is used.  
* Note: If you don't need zbMATH IDs ("Zentralblatt"), then open config.lua and set 
```
M.printZbl = false'
```
          
## Case 2: The tex file uses a bib file.
* Run bibtex and copy the bbl content into the tex file.
  Important: You must NOT use a \bibliographystyle which uses \bysame (such as 'amsplain').
* Proceed as in CASE 1.

## Use a BAT file (on Windows)
Instead of using the Command Terminal one can create and use a BAT file:
* Create, using any text editor, a file 'bibcheck.bat'.
* Paste the following 4 lines into the file:
```
@echo off
chcp 65001
lua "C:\...\bibcheck.lua" %~f1 emsnumeric
pause
```
  Here "C:\...\bibcheck.lua" is the full path of bibcheck.lua.
  'emsjems' is the name of the bst file. Could also be 'amsplain' etc.
* Create a desktop shortcut of that batch file.
* Now drag and drop the TEX file onto the desktop shortcut.
