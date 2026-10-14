#!/bin/bash
# The version of VOpenKey: show it, raise it, announce it. release.sh uses this, it can be used on its own.
#
#   scripts/version.sh                       show the version in every file that has one and whether they agree
#   scripts/version.sh next <bump>           print the next version ("3.0.1 51") without changing anything
#   scripts/version.sh bump <bump>           raise the version in the Xcode project, the Windows resources and the change log
#   scripts/version.sh notes                 print the change log entry of the current version (the release notes)
#   scripts/version.sh announce [--no-windows]
#                                            write the current version to version.json, which the apps read from the master
#                                            branch to tell the user that a new version is out: do it last, when the files
#                                            to download are online
#
# <bump> is patch, minor, major, an explicit version such as 3.1.0, or "current" (no change, for a version that was
# raised by hand and is not released yet).
#
# One version number for every platform: x.y.z. The build number (macOS CFBundleVersion, the fourth number of the
# Windows resources) goes up by one each time. The Windows update check compares x.y.z only, and wants versionCode in
# version.json as x + y*256 + z*65536.
source "$(dirname "$0")/common.sh"

PBX="$PROJECT/project.pbxproj"
RC="$ROOT/Sources/OpenKey/win32/OpenKey/OpenKey/OpenKey.rc"
JSON="$ROOT/version.json"
CHANGELOG="$ROOT/CHANGELOG.md"

[ -f "$PBX" ] && [ -f "$RC" ] && [ -f "$JSON" ] && [ -f "$CHANGELOG" ] || die "version.sh: files of the project are missing (run it from a full checkout)"

# --- reading --------------------------------------------------------------------------------------------------------
# the Xcode project has the version twice (Debug and Release), both must say the same
pbx_values() { grep -o "$1 = [^;]*;" "$PBX" | sed -E "s/$1 = (.*);/\1/" | sort -u; }
project_version() { local v; v="$(pbx_values MARKETING_VERSION)"; [ "$(echo "$v" | wc -l | tr -d ' ')" = 1 ] || die "MARKETING_VERSION differs between the configurations of the Xcode project"; echo "$v"; }
project_build()   { local v; v="$(pbx_values CURRENT_PROJECT_VERSION)"; [ "$(echo "$v" | wc -l | tr -d ' ')" = 1 ] || die "CURRENT_PROJECT_VERSION differs between the configurations of the Xcode project"; echo "$v"; }
rc_version()      { sed -n 's/^ FILEVERSION \([0-9]*\),\([0-9]*\),\([0-9]*\),\([0-9]*\).*/\1.\2.\3 \4/p' "$RC" | head -1; }
json_field()      { /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[sys.argv[2]][sys.argv[3]])' "$JSON" "$1" "$2"; }

valid_version() { echo "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }
win_code() { local IFS=.; set -- $1; echo $(( $1 + $2 * 256 + $3 * 65536 )); }

# a.b.c > d.e.f ?  (0 when the first is newer, 1 otherwise; equal is "not newer")
newer() {
    local IFS=.; local a=($1) b=($2) i
    for i in 0 1 2; do
        [ "${a[$i]}" -gt "${b[$i]}" ] && return 0
        [ "${a[$i]}" -lt "${b[$i]}" ] && return 1
    done
    return 1
}

next_version() {
    local bump="$1" current; current="$(project_version)"
    local IFS=.; local p=($current)
    case "$bump" in
        patch)   echo "${p[0]}.${p[1]}.$((p[2] + 1))" ;;
        minor)   echo "${p[0]}.$((p[1] + 1)).0" ;;
        major)   echo "$((p[0] + 1)).0.0" ;;
        current) echo "$current" ;;
        *) valid_version "$bump" || die "'$bump' is not patch, minor, major, current or a version like 3.1.0"
           if [ "$bump" != "$current" ] && ! newer "$bump" "$current"; then die "$bump is not newer than the current version $current"; fi
           echo "$bump" ;;
    esac
}

# --- writing --------------------------------------------------------------------------------------------------------
set_project_version() { # <version> <build>
    local v="$1" b="$2" old_v old_b
    old_v="$(project_version)"; old_b="$(project_build)"
    sed -i '' -e "s/MARKETING_VERSION = $old_v;/MARKETING_VERSION = $v;/" -e "s/CURRENT_PROJECT_VERSION = $old_b;/CURRENT_PROJECT_VERSION = $b;/" "$PBX"
    [ "$(project_version)" = "$v" ] && [ "$(project_build)" = "$b" ] || die "could not write the version into the Xcode project"
}

set_rc_version() { # <version> <build>
    local v="$1" b="$2" IFS=.; local p=($1)
    sed -i '' -E \
        -e "s/^( FILEVERSION ).*/\\1${p[0]},${p[1]},${p[2]},$b/" \
        -e "s/^( PRODUCTVERSION ).*/\\1${p[0]},${p[1]},${p[2]},$b/" \
        -e "s/(VALUE \"FileVersion\", \")[^\"]*/\\1$v.$b/" \
        -e "s/(VALUE \"ProductVersion\", \")[^\"]*/\\1$v.$b/" "$RC"
    [ "$(rc_version)" = "$v $b" ] || die "could not write the version into the Windows resources"
}

# adds an entry for the version at the top of the change log, from the commit messages since the last release, unless
# there is one already (written by hand before releasing)
add_changelog_entry() { # <version> <build>
    local v="$1" b="$2"
    if grep -q "^##### VOpenKey $v " "$CHANGELOG"; then
        say "The change log already has an entry for $v, keeping it"
        return
    fi
    local last notes
    last="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
    if [ -n "$last" ]; then
        notes="$(git -C "$ROOT" log "$last"..HEAD --no-merges --pretty='- %s' | grep -v '^- release:' || true)"
    fi
    [ -n "${notes:-}" ] || notes="- Cập nhật phiên bản."
    local entry; entry="$(printf '##### VOpenKey %s (build %s): (%s)\n%s\n' "$v" "$b" "$(date +%d/%m/%Y)" "$notes")"
    # after the title line and the blank line under it
    /usr/bin/python3 - "$CHANGELOG" "$entry" <<'EOF'
import sys
path, entry = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8').read()
head, sep, rest = text.partition('\n\n')
open(path, 'w', encoding='utf-8').write(head + sep + entry + '\n\n' + rest)
EOF
}

changelog_notes() { # the entry of the current version, without its heading
    local v; v="$(project_version)"
    awk -v h="##### VOpenKey $v " 'index($0, h) == 1 { on = 1; next } on && /^##### / { exit } on { print }' "$CHANGELOG" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

announce() { # [--no-windows]
    local windows=1; [ "${1:-}" = "--no-windows" ] && windows=0
    local v b; v="$(project_version)"; b="$(project_build)"
    /usr/bin/python3 - "$JSON" "$v" "$b" "$windows" "$(win_code "$v")" <<'EOF'
import json, sys
path, v, b, windows, wcode = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == '1', int(sys.argv[5])
data = json.load(open(path))
data['latestVersion'] = {'versionName': v, 'versionCode': b}
if windows:
    data['latestWinVersion'] = {'versionName': v, 'versionCode': wcode}
open(path, 'w').write(json.dumps(data, indent='\t') + '\n')
EOF
}

# --- commands -------------------------------------------------------------------------------------------------------
cmd="${1:-show}"
case "$cmd" in
    show)
        v="$(project_version)"; b="$(project_build)"
        rv="$(rc_version)"
        printf '  %-28s %s (build %s)\n' "Xcode project (macOS)" "$v" "$b"
        printf '  %-28s %s (build %s)\n' "OpenKey.rc (Windows)" "${rv% *}" "${rv#* }"
        printf '  %-28s %s (code %s)\n' "version.json, macOS" "$(json_field latestVersion versionName)" "$(json_field latestVersion versionCode)"
        printf '  %-28s %s (code %s)\n' "version.json, Windows" "$(json_field latestWinVersion versionName)" "$(json_field latestWinVersion versionCode)"
        [ "${rv% *}" = "$v" ] && [ "${rv#* }" = "$b" ] || warn "the Windows resources do not match the Xcode project: scripts/version.sh bump current"
        ;;
    next)
        [ -n "${2:-}" ] || die "usage: version.sh next <patch|minor|major|x.y.z|current>"
        new="$(next_version "$2")"; build="$(project_build)"
        [ "$new" = "$(project_version)" ] || build=$((build + 1))
        echo "$new $build"
        ;;
    bump)
        [ -n "${2:-}" ] || die "usage: version.sh bump <patch|minor|major|x.y.z|current>"
        new="$(next_version "$2")"; old="$(project_version)"; build="$(project_build)"
        if [ "$new" != "$old" ]; then build=$((build + 1)); fi
        set_project_version "$new" "$build"
        set_rc_version "$new" "$build"
        add_changelog_entry "$new" "$build"
        say "Version is now $new (build $build)"
        ;;
    notes)    changelog_notes ;;
    announce) shift; announce "$@"; say "version.json now says $(project_version) (build $(project_build))" ;;
    -h|--help|help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command: $cmd (see --help)" ;;
esac
