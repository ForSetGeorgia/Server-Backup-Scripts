#!/bin/bash
# $1 = user
# $2 = password
# $3 = folder path to save files to

query="select datname from pg_database where not datistemplate and datallowconn;"
for line in `PGPASSWORD="$2" psql -U "$1" -At -c "$query" postgres`
do
    PGPASSWORD="$2" pg_dump -U "$1" "$line" > "$3"/"$line".sql
done
