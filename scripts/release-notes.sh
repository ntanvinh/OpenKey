#!/bin/bash
# The release notes rule for scripts/release.sh (sourced; nothing runs when it is sourced). The same file is in every desktop project that publishes
# to GitHub (VMonitor AI has it as scripts/lib/notes.sh).
#
# A release is never published without the notes of ITS OWN version: marketing/releases/notes/<version>.md, with front matter (version: x.y.z), a
# "## en-US" and a "## vi" section, each a list of "- " bullets. Before this, a release whose notes file was missing (written for another number
# before the version moved) quietly got GitHub's own "Full Changelog" as its description, and the change log of the project is a raw git log.
# The file is also what VApp Manager puts into the description of the release afterwards, so the two always say the same.

RELEASE_NOTES_DIR="${RELEASE_NOTES_DIR:-$ROOT/marketing/releases/notes}"

# notes_problem <version>
# Prints why the notes of that version cannot be published and returns 1; prints nothing and returns 0 when they can.
notes_problem() {
    local version="$1" file="$RELEASE_NOTES_DIR/$1.md" front status=0
    if [ ! -f "$file" ]; then
        echo "there is no ${file#"$ROOT"/}"
        return 1
    fi
    front="$(awk 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on && /^version:/ { sub(/^version:[ \t]*/, ""); print; exit }' "$file")"
    if [ "$front" != "$version" ]; then
        echo "${file#"$ROOT"/} says 'version: ${front:-nothing}' in its front matter, not $version"
        return 1
    fi
    awk '
        NR == 1 && $0 == "---" { front = 1; next }
        front && $0 == "---" { front = 0; next }
        front { next }
        /^## en-US[ \t]*$/ { section = "en"; seen_en = 1; next }
        /^## vi[ \t]*$/    { section = "vi"; seen_vi = 1; next }
        /^## /             { bad = 1 }
        section && /^- /   { bullets[section]++ }
        section            { chars[section] += length($0) }
        END {
            if (bad) exit 3
            if (!seen_en || !seen_vi) exit 4
            if (bullets["en"] < 1) exit 5
            if (bullets["vi"] < 1) exit 6
            if (chars["en"] > 3900 || chars["vi"] > 3900) exit 7
        }' "$file" || status=$?
    case "$status" in
        0) return 0 ;;
        3) echo "${file#"$ROOT"/} has a heading other than '## en-US' and '## vi'" ;;
        4) echo "${file#"$ROOT"/} needs both a '## en-US' and a '## vi' section" ;;
        5) echo "${file#"$ROOT"/} has no '- ' bullet under '## en-US'" ;;
        6) echo "${file#"$ROOT"/} has no '- ' bullet under '## vi'" ;;
        7) echo "${file#"$ROOT"/} is longer than the 3900 characters a release description can carry" ;;
        *) echo "${file#"$ROOT"/} could not be read" ;;
    esac
    return 1
}

# notes_unreleased <repo> <tag prefix> <version to leave out>
# The versions that have a notes file, no release, and a number above the newest release: notes somebody wrote for a number that later moved.
notes_unreleased() {
    local repo="$1" prefix="$2" skip="$3" tags newest file v top
    tags="$(gh release list --repo "$repo" --limit 200 --json tagName --jq '.[].tagName' 2>/dev/null || true)"
    # Without the list of releases nothing can be said about which notes are still waiting (offline, no access), so no guess is offered.
    [ -n "$tags" ] || return 0
    newest="$(printf '%s\n' "$tags" | sed -n "s/^${prefix}\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\$/\1/p" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
    for file in "$RELEASE_NOTES_DIR"/*.md; do
        [ -f "$file" ] || continue
        v="$(basename "$file" .md)"
        [ "$v" != "$skip" ] || continue
        printf '%s\n' "$tags" | grep -Fxq "$prefix$v" && continue
        if [ -n "$newest" ]; then
            top="$(printf '%s\n%s\n' "$newest" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
            [ "$top" = "$v" ] || continue
        fi
        echo "$v"
    done
}

# require_release_notes <version> <repo> <tag prefix>
# Stops, before anything is changed or built, unless the notes of the version exist and have the shape the description needs. Names the gap and,
# when notes exist for a number that was never released, the file that was probably meant.
require_release_notes() {
    local version="$1" repo="$2" prefix="$3" why others hint=""
    if why="$(notes_problem "$version")"; then return 0; fi
    others="$(notes_unreleased "$repo" "$prefix" "$version" | tr '\n' ' ')"
    if [ -n "${others// /}" ]; then
        hint="
  Notes exist for a version that was never released: ${others% }. If they describe this release, rename the file and its 'version:' line to $version
  (VApp Manager: Release notes > Change version), or release that version as it is: scripts/release.sh current."
    fi
    die "no release notes for $version, so nothing was built or published: $why.
  Write marketing/releases/notes/$version.md (VApp Manager: Release notes, Run in agent) and commit it, then run this again.$hint"
}

# release_notes_body <version>
# The description of the GitHub release: the notes of the version, English then Vietnamese ("What's new" / "Có gì mới"), as VApp Manager writes it.
# Stops when the notes are not usable, so an empty description can never be handed to `gh release create`.
release_notes_body() {
    local version="$1" why body
    why="$(notes_problem "$version")" || die "the release notes of $version are not usable: $why"
    body="$(awk 'NR == 1 && $0 == "---" { front = 1; next } front && $0 == "---" { front = 0; next } front { next } { print }' "$RELEASE_NOTES_DIR/$version.md" \
        | sed -e "s/^## en-US\$/## What's new/" -e 's/^## vi$/## Có gì mới/')"
    [ -n "${body//[[:space:]]/}" ] || die "the release notes of $version came out empty"
    printf '%s\n' "$body"
}

# release_notes_section <version> <en-US|vi>
# The "- " bullets of one language of the notes, for the places that list them (the Sparkle update window of VIce Bartender).
release_notes_section() {
    awk -v want="$2" 'NR == 1 && $0 == "---" { front = 1; next } front && $0 == "---" { front = 0; next } front { next }
        /^## / { on = ($0 == "## " want); next } on && /^- / { print }' "$RELEASE_NOTES_DIR/$1.md"
}
