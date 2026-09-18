#!/bin/sh
# Run every regression suite. Exits non-zero if any fails, so it can gate a build.
#
#   sh tools/t_all.sh          one line per suite
#   V=1 sh tools/t_all.sh      every assertion
#
# Needs only perl + DBD::SQLite. No LMS install, no server — see tools/t_stubs.pl.
cd "$(dirname "$0")/.." || exit 2
status=0
for t in tools/t_*.pl; do
    case "$t" in tools/t_stubs.pl) continue ;; esac
    out=$(perl "$t" 2>&1)
    if [ $? -eq 0 ]; then
        printf '%-16s %s\n' "$(basename "$t")" "$(printf '%s' "$out" | tail -1)"
    else
        status=1
        printf '%-16s FAILED\n' "$(basename "$t")"
        printf '%s\n' "$out" | grep -E -A2 '^FAIL|died|Can.t|line [0-9]' | head -30
    fi
done
[ $status -eq 0 ] && printf '\nall suites passed\n' || printf '\nFAILURES — see above\n'
exit $status
