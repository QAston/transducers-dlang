@echo off
set expanded_list=
for /f "tokens=*" %%F in ('dir /b /a:-d "source\transduced\*.d"') do call set expanded_list=%%expanded_list%% "source\transduced\%%F"

echo expanded_list is: 
echo %expanded_list%
dub run dfmt -- --inplace --end_of_line=crlf %expanded_list%