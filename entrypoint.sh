#!/bin/bash

set -Eeuo pipefail

TARGET_DIR="/usr/lib64/mysql/plugin"
PLUGIN="/plugin/lib/libsys_eval.so"

if [[ ! -f "$PLUGIN" ]]; then
    echo "ERROR: UDF library not found: $PLUGIN" >&2
    exit 1
fi

install -o mysql -g mysql -m 0755 "$PLUGIN" "$TARGET_DIR/libsys_eval.so"

if [[ -z "${MYSQL_ROOT_PASSWORD:-}" ]]; then
    echo "ERROR: MYSQL_ROOT_PASSWORD is not set." >&2
    exit 1
fi

/usr/local/bin/docker-entrypoint.sh "$@" &
MYSQL_PID=$!

echo "--> Waiting for MySQL to start..."
ready=0
for ((i = 0; i < 120; i++)); do
    if mysqladmin --user=root ping --silent >/dev/null 2>&1; then
        ready=1
        break
    fi

    if ! kill -0 "$MYSQL_PID" 2>/dev/null; then
        echo "ERROR: MySQL exited before becoming ready." >&2
        wait "$MYSQL_PID" || true
        exit 1
    fi

    sleep 1
done

if (( ! ready )); then
    echo "ERROR: Timed out waiting for MySQL." >&2
    kill -TERM "$MYSQL_PID" 2>/dev/null || true
    wait "$MYSQL_PID" || true
    exit 1
fi

echo "Registering sys_eval ; )"
mysql --user=root -S /var/lib/mysql/mysql.sock --execute="
    DROP FUNCTION IF EXISTS sys_eval;
    CREATE FUNCTION sys_eval RETURNS STRING SONAME 'libsys_eval.so';
"

echo "Results: "
mysql --user=root --binary-as-hex=0 --table --execute="
    SELECT CONVERT(sys_eval('id') USING utf8mb4) AS udf_result;
"

echo "done..."
mysqladmin --user=root shutdown

wait "$MYSQL_PID"
