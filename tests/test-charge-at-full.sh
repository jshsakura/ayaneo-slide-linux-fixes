#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

HELPER="$TEST_DIR/ayaneo-charge-at-full"
CAPACITY_FILE="$TEST_DIR/capacity"
BEHAVIOUR_FILE="$TEST_DIR/charge_behaviour"
HHDCTL="$TEST_DIR/hhdctl"
HHD_LOG="$TEST_DIR/hhd.log"

awk '/cat << '\''EOF'\'' > \/usr\/local\/sbin\/ayaneo-charge-at-full/ {
    copy=1
    next
}
copy && /^EOF$/ { exit }
copy { print }' "$REPO_DIR/install.sh" > "$HELPER"
chmod 755 "$HELPER"

cat > "$HHDCTL" <<'EOF'
#!/usr/bin/env bash
set -eu

[ "$1" = set ] || exit 2
target=${2#*=}
printf 'set %s\n' "$target" >> "$FAKE_HHD_LOG"
if [ "$target" = always ]; then
    printf 'auto [inhibit-charge]\n' > "$FAKE_BEHAVIOUR_FILE"
else
    printf '[auto] inhibit-charge\n' > "$FAKE_BEHAVIOUR_FILE"
fi
EOF
chmod 755 "$HHDCTL"

run_helper() {
    env HHDCTL="$HHDCTL" CAPACITY_FILE="$CAPACITY_FILE" \
        BEHAVIOUR_FILE="$BEHAVIOUR_FILE" FAKE_BEHAVIOUR_FILE="$BEHAVIOUR_FILE" \
        FAKE_HHD_LOG="$HHD_LOG" bash "$HELPER"
}

# At 100%, normal charging changes to bypass exactly once.
printf '100\n' > "$CAPACITY_FILE"
printf '[auto] inhibit-charge\n' > "$BEHAVIOUR_FILE"
: > "$HHD_LOG"
run_helper
run_helper
[ "$(cat "$BEHAVIOUR_FILE")" = 'auto [inhibit-charge]' ]
[ "$(wc -l < "$HHD_LOG")" -eq 1 ]

# The 96-99% hysteresis band preserves either existing state without HHD.
for behaviour in '[auto] inhibit-charge' 'auto [inhibit-charge]'; do
    printf '99\n' > "$CAPACITY_FILE"
    printf '%s\n' "$behaviour" > "$BEHAVIOUR_FILE"
    : > "$HHD_LOG"
    run_helper
    [ "$(cat "$BEHAVIOUR_FILE")" = "$behaviour" ]
    [ ! -s "$HHD_LOG" ]
done

# At 95%, bypass changes to normal charging exactly once.
printf '95\n' > "$CAPACITY_FILE"
printf 'auto [inhibit-charge]\n' > "$BEHAVIOUR_FILE"
: > "$HHD_LOG"
run_helper
run_helper
[ "$(cat "$BEHAVIOUR_FILE")" = '[auto] inhibit-charge' ]
[ "$(wc -l < "$HHD_LOG")" -eq 1 ]

# Reject an invalid window rather than applying an ambiguous state.
if env HHDCTL="$HHDCTL" CAPACITY_FILE="$CAPACITY_FILE" \
    BEHAVIOUR_FILE="$BEHAVIOUR_FILE" START_CAPACITY=100 STOP_CAPACITY=100 \
    bash "$HELPER"; then
    echo 'invalid threshold test unexpectedly succeeded' >&2
    exit 1
fi

echo 'automatic charge policy fixtures: pass'
