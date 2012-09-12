#!/bin/bash

if [ -z "$1" -o -z "$2" ]; then
	echo "makeinclude needs two parameters!"
	echo "  makeinclude.sh listing_file output_file"
	exit 1
fi

#make backup if exist
if [ -f $2 ]; then
    mv $2 $2.$(date +%s)
fi

echo "; Include file generated from $1 dated $(date -r $1)" >$2
echo ".cseg" >>$2

for label in $(cat $1|egrep "^[[:blank:]]+[[:alnum:]_]+:"|tr -d "[:blank:]"|grep -v "reset:"); do
    echo "processing label: $label"
    address=$(cat $1|grep -A 5 "$label"|egrep "^C:"|head -n1|cut -f 2 -d ":"|cut -f 1 -d ' ')
    echo ".org	0x${address}" >>$2
    echo "$label" >>$2
    echo >>$2
done
