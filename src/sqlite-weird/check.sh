#!/usr/bin/env bash
# Node is a test oracle only; the entry runs on the sqlite3-only runtime base.
set -euo pipefail
cd "$(dirname "$0")"
node check.mjs
data=$(mktemp -d)
trap 'rm -rf "$data"' EXIT
export XDG_DATA_HOME=$data SEED=12345 RUN_DATE=2021-01-01
sh run.sh > "$data/first.txt"
sh run.sh > "$data/second.txt"
# Run IDs differ; the ledger and circuit rows must be identical.
diff <(tail -n +4 "$data/first.txt") <(tail -n +4 "$data/second.txt")
sqlite3 "$data/SQLiteWeird/demo-timecards.db" 'INSERT INTO run_demo DEFAULT VALUES;'
[[ $(sqlite3 "$data/SQLiteWeird/demo-timecards.db" "SELECT count(*) FROM runs WHERE status='complete'") == 3 ]]
[[ $(sqlite3 "$data/SQLiteWeird/demo-timecards.db" "SELECT count(DISTINCT run_id) FROM ledger") == 3 ]]
if SEED='1); DELETE FROM runs; --' sh run.sh >/dev/null 2>&1; then
    echo 'FAIL: launcher accepted malformed seed'; exit 1
fi
if RUN_DATE='2021-02-30' sh run.sh >/dev/null 2>&1; then
    echo 'FAIL: launcher accepted invalid date'; exit 1
fi
[[ $(sqlite3 "$data/SQLiteWeird/demo-timecards.db" 'SELECT count(*) FROM runs') == 3 ]]
echo 'OK: DEMO ONLY launcher, SQL reports and fresh sqlite3 procedure invocation'
