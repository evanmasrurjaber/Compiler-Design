#!/bin/bash

YACC="/mnt/c/Flex Windows/bison/bin/yacc.exe"
FLEX="/mnt/c/Flex Windows/Lex/bin/flex.exe"
GPP="/mnt/c/mingw64/bin/g++.exe"

"$YACC" -d -y --debug --verbose 24341140+24341217.y
echo 'Generated the parser C file as well the header file'
"$GPP" -w -c -o y.o y.tab.c
echo 'Generated the parser object file'
"$FLEX" 24341140+24341217.l
echo 'Generated the scanner C file'
"$GPP" -fpermissive -w -c -o l.o lex.yy.c
echo 'Generated the scanner object file'
"$GPP" y.o l.o -o a.exe
echo 'All ready, running'
./a.exe input.txt