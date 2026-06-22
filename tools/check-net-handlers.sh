#!/usr/bin/env bash
#
# Net-handler guard gate (ratchet).
#
# Fails if any raw net.Receive("LITERAL") site exists that is not listed in
# tools/net-handlers.allowlist (next to this script). The point: new client->server actions must
# go through ws.action.Register (SWEPs: ws.weapon.NetReceive) — those wrappers take a variable
# netstring, so they never appear as net.Receive("LITERAL") and never trip this gate. A genuinely-
# correct raw net.Receive (server->client receiver, pre-character, slot-op, ...) is added to the
# allowlist as a conscious, reviewable line. See the allowlist header for the policy.
#
# Lives in the windswept (framework) repo so CI can run it, but the gate covers the whole product:
# it scans this repo PLUS sibling windswept-colony/ and windswept-fire/ when they are checked out
# next to it (local dev). On the framework's CI runner only windswept/ is present, so CI gates the
# framework and the local pre-ship run gates the schema/addon too.
#
# Portable: Git Bash (local) and the Ubuntu CI runner. Exit 0 = clean, 1 = unlisted handler(s),
# 2 = setup error.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../windswept/tools
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"                          # .../windswept
PARENT="$(cd "$REPO/.." && pwd)"                              # workspace root (or CI workspace)
ALLOWLIST="$SCRIPT_DIR/net-handlers.allowlist"

if [ ! -f "$ALLOWLIST" ]; then
    echo "net-handler gate: missing allowlist at $ALLOWLIST" >&2
    exit 2
fi

# Always scan the framework repo we live in; add sibling dev trees when checked out alongside it.
SCAN=("$REPO")
colony_present=0
for sib in windswept-colony windswept-fire; do
    if [ -d "$PARENT/$sib" ]; then
        SCAN+=("$PARENT/$sib")
        [ "$sib" = "windswept-colony" ] && colony_present=1
    fi
done

# Allowed set: first whitespace-delimited token of each non-comment, non-blank line.
allowed="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" | awk '{print $1}' | sort -u)"

# Current set: every net.Receive("LITERAL") netstring across the scanned trees (thirdparty excluded).
current="$(grep -rhoE 'net\.Receive\("[A-Za-z0-9_]+"' "${SCAN[@]}" --include='*.lua' --exclude-dir=thirdparty 2>/dev/null \
    | sed -E 's/.*net\.Receive\("//; s/"$//' | sort -u)"

new="$(comm -23 <(printf '%s\n' "$current") <(printf '%s\n' "$allowed") | grep -vE '^$' || true)"
dead="$(comm -13 <(printf '%s\n' "$current") <(printf '%s\n' "$allowed") | grep -vE '^$' || true)"

status=0
if [ -n "$new" ]; then
    echo "net-handler gate: FAIL — raw net.Receive handler(s) not in tools/net-handlers.allowlist:" >&2
    printf '  %s\n' $new >&2
    echo "" >&2
    echo "Route client->server actions through ws.action.Register (SWEPs: ws.weapon.NetReceive)." >&2
    echo "If a raw net.Receive is genuinely correct as-is (server->client receiver, pre-character," >&2
    echo "slot-op, player-field session, ...), add its netstring to tools/net-handlers.allowlist." >&2
    status=1
fi

# Only flag stale allowlist entries on a full scan (both trees present); on a framework-only CI
# run the schema/addon entries are legitimately absent, so don't report them.
if [ "$colony_present" -eq 1 ] && [ -n "$dead" ]; then
    echo "net-handler gate: note — allowlist entries no longer present (safe to prune):" >&2
    printf '  %s\n' $dead >&2
fi

if [ "$status" -eq 0 ]; then
    echo "net-handler gate: OK ($(printf '%s\n' "$current" | grep -cE '.' ) raw net.Receive sites, all allowlisted)"
fi
exit $status
