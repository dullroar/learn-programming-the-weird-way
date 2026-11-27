#!/usr/bin/env sh
# DEMO ONLY. Plumbing only: all computation and reporting live in SQL.
set -eu
cd "$(dirname "$0")"
sql=${SQLITE3:-sqlite3}
# A numeric version check avoids lexical ordering mistakes; JSON must work too.
cap=$("$sql" :memory: "WITH v AS (SELECT sqlite_version() s) SELECT
 (cast(substr(s,1,instr(s,'.')-1) AS INTEGER)>3 OR
 (cast(substr(s,1,instr(s,'.')-1) AS INTEGER)=3 AND
 cast(substr(s,instr(s,'.')+1) AS INTEGER)>=38)) AND json_valid('[0,1]') FROM v;")
[ "$cap" = 1 ] || { echo 'DEMO ONLY: SQLite 3.38+ with JSON required' >&2; exit 1; }
data=${XDG_DATA_HOME:-${TMPDIR:-/tmp}}
mkdir -p "$data/SQLiteWeird"
db=$data/SQLiteWeird/demo-timecards.db
version=$("$sql" "$db" 'PRAGMA user_version;')
case $version in
  0) "$sql" -bail "$db" < schema.sql ;;
  1) ;;
  *) echo 'DEMO ONLY: unsupported database schema version' >&2; exit 1 ;;
esac
# Optional reproducibility inputs are validated before becoming SQL literals.
seed=NULL
if [ -n "${SEED:-}" ]; then
  case $SEED in *[!0-9]*|'') echo 'DEMO ONLY: SEED must contain digits' >&2; exit 1 ;; esac
  seed=$SEED
fi
day=NULL
if [ -n "${RUN_DATE:-}" ]; then
  case $RUN_DATE in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) day="'$RUN_DATE'" ;;
    *) echo 'DEMO ONLY: RUN_DATE must be YYYY-MM-DD' >&2; exit 1 ;;
  esac
fi
# One connection keeps this report paired with this run even with other launchers.
{ printf 'BEGIN IMMEDIATE;\nINSERT INTO run_demo(seed,run_date) VALUES(%s,%s);\n' "$seed" "$day"
  cat report.sql
  printf 'COMMIT;\n'
} | "$sql" -bail -header -column "$db"
