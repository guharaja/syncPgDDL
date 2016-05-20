#!/bin/sh

mv -f $1 ${1}.orig;

rm -f $1;

export PGPASSWORD=password;

/usr/bin/pg_dump \
	--host 192.168.1.220 \
	--port 5432 \
	--username "sabyasachi" \
	--role "sabyasachi" \
	--no-password \
	--format plain \
	--schema-only \
	--create \
	--clean \
	--file $1 "sabyasachi";

# stat --printf="\tFile: %n\n\tSize: %s\n\tAt: %y\n" $1;

diff -sc3 -F'^-- Name: ' --tabsize=3 ${1}.orig $1;

# rm -f ${1}.orig;

#	diff 	-sc10 \ 
#			--tabsize=3 \
#			--suppress-blank-empty \
#			--show-function-line='^-- Name: ' \
#			--suppress-common-lines \
#			${1}.orig $1;

 
