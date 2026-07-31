#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# check-panel-attestation.sh — the server-side half of the panel gate.
#
# Answers one question: is there anything in this promotion that no panel has
# read? It reads `.panel/attestations.toml`, which is committed and therefore
# visible to CI, rather than `private/reviews/`, which is gitignored and never
# leaves the operator's machine.
#
# Runs on a pull request into a protected branch, where `pre-push` cannot: the
# merge is performed by the forge, so nothing is ever pushed from a machine that
# has hooks installed. See scripts/panel-attest.sh for why the split exists.
#
# Usage:
#   scripts/check-panel-attestation.sh <head-sha> [<base-branch>]
#
# On a GitHub pull_request event, pass `github.event.pull_request.head.sha`, NOT
# GITHUB_SHA: on that event GITHUB_SHA is the ephemeral merge commit, which does
# not exist in anyone's history and makes every rev-list here meaningless.
#
# REQUIRES A FULL CLONE. actions/checkout defaults to fetch-depth: 1, and this
# walks history, so the workflow must set fetch-depth: 0. A shallow clone is
# detected and refused rather than silently passing: a gate that cannot measure
# must say so, and for a hard gate saying so means failing.

set -uo pipefail

head_sha="${1:-}"
base_ref="${2:-main}"
ATTEST_FILE=".panel/attestations.toml"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=""; GRN=""; BOLD=""; RESET=""
fi

fail() { echo "${RED}${BOLD}FAILED${RESET}: $*"; }

[ -n "$head_sha" ] || { fail "no head sha given"; exit 1; }

# A shallow clone would make every count below wrong in the passing direction.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    fail "this is a shallow clone, so history cannot be measured."
    echo "  Set 'fetch-depth: 0' on the checkout step."
    exit 1
fi

if ! git cat-file -e "${head_sha}^{commit}" 2>/dev/null; then
    fail "${head_sha} is not a commit in this clone."
    echo "  On a pull_request event pass github.event.pull_request.head.sha,"
    echo "  not GITHUB_SHA (which is the ephemeral merge commit)."
    exit 1
fi

if [ ! -f "$ATTEST_FILE" ]; then
    fail "no panel attestation on record."
    echo
    echo "  This pull request promotes work to '${base_ref}', and the panel is"
    echo "  the gate on that promotion. ${ATTEST_FILE} does not exist."
    echo
    echo "  Fix, on the machine holding the review:"
    echo "    /panel                          # if it has not run over this cluster"
    echo "    scripts/panel-attest.sh         # writes the receipt"
    echo "    git add ${ATTEST_FILE} && git commit && git push"
    echo
    echo "  The review itself stays private. Only the receipt is published."
    exit 1
fi

# Every attested sha that exists in this clone. An entry naming a sha we cannot
# resolve (a rebase, a force-push, a typo) is reported and skipped rather than
# trusted: unresolvable coverage is not coverage.
best_base=""
best_unreviewed=""
unresolved=0
while read -r sha; do
    [ -n "$sha" ] || continue
    if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
        unresolved=$((unresolved + 1))
        continue
    fi
    # Only an ancestor of the head can have reviewed it. An attestation from a
    # divergent line of history says nothing about this pull request.
    git merge-base --is-ancestor "$sha" "$head_sha" 2>/dev/null || continue
    count=$(git rev-list --count "${sha}..${head_sha}" 2>/dev/null) || continue
    if [ -z "$best_unreviewed" ] || [ "$count" -lt "$best_unreviewed" ]; then
        best_unreviewed="$count"
        best_base="$sha"
    fi
done < <(grep -oP '^covers\s*=\s*"\K[0-9a-fA-F]{7,40}' "$ATTEST_FILE")

if [ -z "$best_base" ]; then
    fail "no attestation covers any ancestor of this pull request."
    [ "$unresolved" -gt 0 ] && echo "  (${unresolved} attested sha(s) do not exist in this clone)"
    echo
    echo "  Every recorded panel reviewed a commit that is not in this history,"
    echo "  so nothing here has been reviewed. Run the panel over this cluster"
    echo "  and attest it."
    exit 1
fi

if [ "$best_unreviewed" -gt 0 ]; then
    fail "${best_unreviewed} commit(s) in this pull request that no panel has read."
    echo
    echo "  reviewed up to: ${best_base:0:12}"
    echo "  promoting:      ${head_sha:0:12}"
    echo
    git log --oneline "${best_base}..${head_sha}" 2>/dev/null | head -15 | sed 's/^/    /'
    [ "$best_unreviewed" -gt 15 ] && echo "    ... and $(( best_unreviewed - 15 )) more"
    echo
    echo "  Fix, on the machine holding the review:"
    echo "    /panel over this cluster, record the synthesis with a line reading"
    echo "      covers: ${head_sha:0:12}"
    echo "    scripts/panel-attest.sh && git add ${ATTEST_FILE} && git commit && git push"
    exit 1
fi

echo "${GRN}ok${RESET}: panel coverage reaches ${head_sha:0:12} (attested at ${best_base:0:12})"
exit 0
