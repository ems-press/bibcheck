-- Simon Winter [winter@ems.press]
-- 2021-02-02

******************************************
* How to install EMS-Bibcheck on Windows *
******************************************

*** Install Lua ***

-- Download the exe file LuaForWindows_v5.1.5-52.exe here:
   https://github.com/rjpcomputing/luaforwindows/releases/tag/v5.1.5-52
-- Run the exe file and always click "accept/next".

*** Install WGet ***

-- Download the exe file wget-1.11.4-1-setup.exe here:
   https://sourceforge.net/projects/gnuwin32/files/wget/1.11.4-1/
   (The file name must not contain "src"!)
-- Run the exe file and always click "accept/next".
-- Add WGet to the PATH on Windows:
   (1) Open the Start Search, type in "env" and choose "Edit the system environment variables" ("Systemumgebungsvariablen bearbeiten").
   (2) Click the "Environment Variables" button ("Umgebungsvariablen").
   (3) Under the "System Variables" section (the lower half), find the row with "Path" in the first column and click edit.
   (4) Click "New" and type in the new path, e.g. C:\Program Files (x86)\GnuWin32\bin
   (5) Dismiss all of the dialogs by choosing OK. Your changes are saved.

*** How to use WGet in the Windows Command Shell ***

>> wget --no-check-certificate -O OUTPUTFILE 
   "https://mathscinet.ams.org/mathscinet-mref?dataType=bibtex&ref='BIBITEM'" 2>&1

   
**************************************
* How to use EMS-Bibcheck on Windows *
**************************************

CASE 1: The tex file contains \begin{thebibliography}

(1) Open the Windows Command Shell, go to the paper's directory and write
    >> lua C:\...\EMS-Bibcheck.lua FILENAME.tex amsplain
     
(1*) Alternatively, specify the path of EMS-Bibcheck.lua in the batch file EMS-Bibcheck.bat.
     Create a desktop shortcut of that batch file.
     Now you can drag and drop the tex file onto this desktop shortcut.
    
(2) Open the new file FILENAME-REFERENCES.bbl. It contains three kind of \bibitem:
    (a) UNMATCHED ENTRY. 
        There was no match in MathSciNet.
        Format this entry and sort it in the bibliography according to the known criteria. 
    (b) CRITICAL MATCH.
        Compare the match with the original \bibitem which is added in %.
    (c) MATCH.
        With all other entries (hopefully the majority) there were no problems. 
    
CASE 2: The tex file uses a bib file.

(1) Run bibtex and copy the bbl content into the tex file.

(2) Proceed as in CASE 1.

NOTA BENE: EMS-Bibcheck removes optional aruments of \bibitem!
           I.e., \bibitem[Bredon 1972]{Bre} is replaced by \bibitem{Bre}.

