#!/bin/bash

yacc -d -y 24341140+24341217.y
echo 'Generated the parser C file and header file'
g++ -w -c -o y.o y.tab.c
echo 'Generated the parser object file'
flex 24341140+24341217.l
echo 'Generated the scanner C file'
g++ -fpermissive -w -c -o l.o lex.yy.c
echo 'Generated the scanner object file'
g++ y.o l.o -o compiler
echo 'All ready, running the compiler...'

./compiler input.c
echo 'Compilation completed.'

echo '------------ Log output ------------'
cat log.txt
echo '------------ Error output ------------'
cat error.txt
echo '------------ Three Address Code ------------'
cat code.txt
