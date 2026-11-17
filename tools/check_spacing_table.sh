#!/bin/sh
# Regenerates the spacing table from a C3 standard library and reports how it differs from
# src/c3f/spacing_table.c3. Usage: tools/check_spacing_table.sh <c3c>/lib/std
# It does not change the committed table: a regeneration can differ in a few cells, and
# the formatter's output changes with them (see the note in the table's header).
set -e
lib="$1"
[ -d "$lib" ] || { echo "usage: $0 <c3c>/lib/std" >&2; exit 2; }
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
build/gen-spacing $(find "$lib" -name '*.c3') > "$tmp"
# only the rows of the table are compared: the header and the module lines are not generated the same way
grep '^	{' src/c3f/spacing_table.c3 > "$tmp.committed"
grep '^	{' "$tmp" > "$tmp.regenerated"
total=$(diff "$tmp.committed" "$tmp.regenerated" | grep -c '^[<>]' || true)
echo "table rows differing from the regeneration: $total (of $(wc -l < "$tmp.committed"))"
diff "$tmp.committed" "$tmp.regenerated" | head -20 || true
rm -f "$tmp.committed" "$tmp.regenerated"
