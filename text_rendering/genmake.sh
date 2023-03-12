#!/bin/sh

genobj() {
	#echo "$1" | sed -e 's/^/obj\//' -e 's/\.c/\.o/'
	echo "$1" | sed -e 's/\.c/\.o/'
}

genrule() {
	#gcc -MM "$1" | sed 's/^/obj\//'
	gcc -MM "$1"
}


rm -f objlist

cat > Makefile << EOF
CC      = gcc
LDFLAGS = -lm -lgrapheme -lSDL2 -lGLEW -lGL
CFLAGS  = -ggdb3 -Wall -Wextra -pedantic -std=c11 \
-Wno-unused-function -fno-omit-frame-pointer

.PHONY: clean all
all: test

EOF

for f in *.c; do
	genrule $f >> Makefile
	genobj $f >> objlist
done

mainrule='test: '
linkcmd='	${CC} ${LDFLAGS} -o test '
cleanrule='clean:
	rm -f test '
while IFS="" read -r line; do
	mainrule="$mainrule $line"
	linkcmd="$linkcmd $line"
	cleanrule="$cleanrule $line"
done < objlist

echo "$mainrule"  >> Makefile
echo "$linkcmd"   >> Makefile
echo "$cleanrule" >> Makefile