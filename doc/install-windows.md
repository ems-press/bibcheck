Simon Winter [winter@ems.press] 
2021-02-05

# How to install bibcheck on Windows

## Install bibcheck
* Create a new folder for bibcheck. The whole path must not contain any spaces!!!
* Copy the two files 'bibcheck.lua' and 'EMS_functions.lua' into the bibcheck folder.

## Create file 'bibcheck.bat'
* Create, using any text editor, a file 'bibcheck.bat' in the bibcheck folder.
* Paste the 3 lines geiven below into the file. "C:\...\bibcheck.lua" is the full path of bibcheck.lua.
* Create a desktop shortcut of that batch file.

@echo off
lua "C:\...\bibcheck.lua" %~f1
pause

## Install Lua
* Download 'LuaForWindows_v5.1.5-52.exe' here:
  https://github.com/rjpcomputing/luaforwindows/releases/tag/v5.1.5-52
* Run the exe file and always click "accept/next".

## Install Java
* Download 'jdk-15.0.2_windows-x64_bin.exe' here:
  https://www.oracle.com/java/technologies/javase-jdk15-downloads.html
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
   
## Install CERMINE
* Download the 37 MB jar file from
https://maven.ceon.pl/artifactory/kdd-releases/pl/edu/icm/cermine/cermine-impl/1.13/cermine-impl-1.13-jar-with-dependencies.jar
* Copy the file into the bibcheck folder.

# How to use bibcheck on Windows

## Case 1: The tex file contains \begin{thebibliography}
* Open the Windows Command Shell, go to the paper's directory and write
    >> lua C:\...\bibcheck.lua FILENAME.tex BSTFILENAME
    e.g.
    >> lua C:\tools\bibcheck\bibcheck.lua main.tex amsplain
    
  Alternatively, use bibcheck.bat: Drag and drop the tex file onto its desktop shortcut.
* Open one of the files FILENAME-REFERENCES.bbl or FILENAME-REFERENCES.tex. 
  It contains three kind of \bibitem:
  (a) UNMATCHED ENTRY. 
      There was no match in MathSciNet.
      Format this entry and sort it in the bibliography according to the known criteria. 
  (b) CRITICAL MATCH.
      Compare the match with the original \bibitem which is added in %.
  (c) MATCH.
      With all other entries (hopefully the majority) there were no problems. 
    
## Case 2: The tex file uses a bib file.
* Run bibtex and copy the bbl content into the tex file.
* Proceed as in CASE 1.

NOTA BENE: bibcheck removes optional aruments of \bibitem!
I.e., \bibitem[Bredon 1972]{Bre} is replaced by \bibitem{Bre}.
