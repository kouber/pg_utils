#!/bin/bash

OFFSET=0
FPC_THRESHOLD=40

while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    --table=*)
    TABLE="${key#*=}"
    ;;
    --skip-table=*)
    SKIP_TABLE="${key#*=}"
    ;;
    --raw-sql=*)
    RAW_SQL="${key#*=}"
    ;;
    --limit=*)
    LIMIT="${key#*=}"
    ;;
    --offset=*)
    OFFSET="${key#*=}"
    ;;
    --threshold=*)
    FPC_THRESHOLD="${key#*=}"
    ;;
    -h|--help)
    cat << EOHELP
Performs conditional reindexing.

Usage:
  $0 [OPTION] [database]

Options:
      --table=TABLE(s)       CSV list of tables to process (example: --table=public.player,audit.log)
      --skip-table=TABLE(s)  CSV list of tables to skip    (example: --skip-table=public.customer,internal.employee)
      --raw-sql=SQL          SQL code to add to the WHERE clause (example: --raw-sql="schemaname ~ 'public'")
      --limit=N              process the top N biggest tables only (default: no limit)
      --offset=N             offset the list (default: 0)
      --threshold=N          free percent threshold, as reported by pgstattuple (default: 40)

EOHELP
    exit 0
    shift
    ;;
    *)
    DB=$key
    shift
    ;;
  esac
  shift
done

if [ -z "$DB" ]; then
  DB=postgres
fi

timestamp() {
  echo -ne "`date '+%F %H:%M:%S'`\t"
}

slave=`psql -AXqtc "SELECT pg_is_in_recovery()::int" 2>/dev/null`
if [ "$slave" = "1" ]; then
  echo "`timestamp`Index doctor cannot run on a slave node."
  exit 3
fi

PG_VERSION=`psql -AXqtc "SHOW server_version_num" $DB`

declare -a exts=("pgstattuple")

if [ $PG_VERSION -lt 120000 ]; then
  exts+=("pg_repack")
fi

for ext in "${exts[@]}"; do
  ext_check=`psql -AXqtc "SELECT oid FROM pg_extension WHERE extname='$ext'" $DB`
  if [ -z "$ext_check" ]; then
    echo "Extension \"$ext\" is not installed."
    exit 2
  fi
done

if [ ! -z "$LIMIT" ]; then
  if [[ "$LIMIT" =~ [^0-9] ]]; then
    echo "Invalid limit argument."
    exit 3
  fi

  if [[ "$OFFSET" =~ [^0-9] ]]; then
    echo "Invalid offset argument."
    exit 3
  fi

  limit_sql="LIMIT $LIMIT OFFSET $OFFSET"
fi

if [[ "$FPC_THRESHOLD" =~ [^0-9] ]]; then
  echo "Invalid threshold argument."
  exit 3
fi

COLOR_GRAY='\033[1;30m'
COLOR_WHITE='\033[1;37m'
COLOR_GREEN='\033[1;32m'
COLOR_RED='\033[1;31m'
COLOR_NO='\033[0m'

echo -ne "`timestamp`\tIndex doctor start "

if [ ! -z "$limit_sql" ]; then
  echo -n "(top $LIMIT tables, $OFFSET offset)"
fi

echo ""

if [ ! -z "$TABLE" ]; then
  TABLE=`echo "'$TABLE'" | sed -e "s/,/', '/g"`
  tbl_sql="AND schemaname || '.' || relname IN ($TABLE)"
fi

if [ ! -z "$SKIP_TABLE" ]; then
  SKIP_TABLE=`echo "'$SKIP_TABLE'" | sed -e "s/,/', '/g"`
  skip_sql="AND schemaname || '.' || relname NOT IN ($SKIP_TABLE)"
fi

if [ ! -z "$RAW_SQL" ]; then
  raw_sql="AND $RAW_SQL"
fi

query="
  SELECT
    schemaname,
    relname,
    pg_size_pretty(pg_total_relation_size(relid::regclass))
  FROM
    pg_stat_user_tables
  WHERE
    schemaname !~ '^pg_temp' $tbl_sql $skip_sql $raw_sql
  ORDER BY
    pg_total_relation_size(relid::regclass) DESC
  $limit_sql"

i=1
psql -F ' ' -AXqtc "`echo $query`" "$DB" | while read schema table size; do
  echo -e "\n`timestamp`\t$COLOR_RED⌛$COLOR_WHITE $schema.$table$COLOR_NO ($size) processing ($i/$LIMIT) ..."

  indexes=`psql -AXqtc "WITH idx AS (SELECT indexrelid::regclass, (SELECT free_percent FROM pgstattuple(indexrelid::regclass)) AS fpc FROM pg_index WHERE indrelid = '\"$schema\".\"$table\"'::regclass AND indexrelid IN (SELECT oid FROM pg_class WHERE relam IN (SELECT oid FROM pg_am WHERE amname IN ('btree', 'hash', 'gist'))) ) SELECT STRING_AGG(indexrelid::regclass::text, ' ') FROM idx WHERE fpc > $FPC_THRESHOLD" "$DB"`

  for indexname in $indexes; do
    if [ $PG_VERSION -lt 120000 ]; then
      pg_repack --wait-timeout=3600 --no-kill-backend -i $indexname -d "$DB"
    else
      echo -ne "`timestamp`$COLOR_NO\tReindexing $indexname...\t"
      psql -AXqtc "REINDEX INDEX CONCURRENTLY $indexname" "$DB" > /dev/null
      echo "done."
    fi
  done
 
  new_size=`psql -AXqtc "SELECT pg_size_pretty(pg_total_relation_size('\"$schema\".\"$table\"'::regclass))" $DB`
  echo -e "`timestamp`\t$COLOR_GREEN✓$COLOR_WHITE $schema.$table$COLOR_NO ($new_size) done."
  ((i++))
done

echo -e "\n`timestamp`\tIndex doctor done.$COLOR_NO"
