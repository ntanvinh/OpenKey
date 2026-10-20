#!/usr/bin/env python3
"""The fake releases of app_update_test.m, one folder per scenario, for mock_github_server.py.

usage: app_update_fixtures.py <output folder>

The "disk image" of every release is a zip (except "realdmg", made when VOK_TEST_REAL_DMG=1) (the tests open it with ditto instead of hdiutil, see TestUpdater in app_update_test.m), whose
content is laid out like the real dmg: the app at the top, next to a link named Applications. The apps are real bundles signed only ad hoc,
which is all the tests need: the requirement they are checked against is the one of the identifier (the production requirement, with the
Developer ID of the team, is tried against them too, and must refuse them).
"""
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

OUT = sys.argv[1]
VERSION = "9.9.9"
TAG = "v" + VERSION
IDENTIFIER = "vn.io.lssoft.vopenkey.test"
APP = "VOpenKey AI.app"
FILE = "VOpenKey-%s.dmg" % VERSION

work = tempfile.mkdtemp(prefix="update-fixtures-")
main_c = os.path.join(work, "main.c")
with open(main_c, "w") as handle:
    handle.write("int main(void) { return 0; }\n")
subprocess.check_call(["clang", main_c, "-o", os.path.join(work, "main")])


def run(*args):
    subprocess.check_call(list(args), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def make_app(folder, version=VERSION, identifier=IDENTIFIER, sign=True, minimum_os=None, name=APP):
    """A bundle <folder>/<name> with an executable, optionally signed ad hoc."""
    app = os.path.join(folder, name)
    os.makedirs(os.path.join(app, "Contents", "MacOS"))
    os.makedirs(os.path.join(app, "Contents", "Resources"))
    shutil.copy(os.path.join(work, "main"), os.path.join(app, "Contents", "MacOS", "VOpenKey AI"))
    with open(os.path.join(app, "Contents", "Resources", "data.txt"), "w") as handle:
        handle.write("resource of %s\n" % version)
    plist = {
        "CFBundleIdentifier": identifier, "CFBundleExecutable": "VOpenKey AI", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version, "CFBundleVersion": "1", "CFBundleName": "VOpenKey AI",
    }
    if minimum_os:
        plist["LSMinimumSystemVersion"] = minimum_os
    with open(os.path.join(app, "Contents", "Info.plist"), "wb") as handle:
        plistlib.dump(plist, handle)
    if sign:
        run("codesign", "--force", "--deep", "-s", "-", app)
    return app


def zip_folder(folder, destination):
    run("ditto", "-c", "-k", folder, destination)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


disks = []


def disk_with(builder):
    """A zip laid out like the dmg; `builder(folder)` puts the app(s) in it."""
    folder = tempfile.mkdtemp(dir=work)
    builder(folder)
    os.symlink("/Applications", os.path.join(folder, "Applications"))
    disks.append(folder)
    destination = os.path.join(work, "disk-%d.zip" % len(disks))
    zip_folder(folder, destination)
    return destination


def scenario(name, disk, tag=TAG, digest=True, size=None, checksum_file=True, checksum_text=None, api_status=None, draft=False,
             prerelease=False, evil_url=False, latest=None, extra_assets=True, digest_value=None, asset_name=None, state_files=None):
    """Writes a scenario folder: the API answer, the files, and the special behaviours (state_files: {file: content})."""
    folder = os.path.join(OUT, name)
    os.makedirs(os.path.join(folder, "files"))
    version = tag[1:]
    file_name = asset_name or "VOpenKey-%s.dmg" % version
    shutil.copy(disk, os.path.join(folder, "files", file_name))
    actual = sha256(disk)
    base = "__BASE__/releases/download/%s" % tag
    if checksum_file:
        text = checksum_text if checksum_text is not None else "%s  %s\n" % (actual, file_name)
        with open(os.path.join(folder, "files", file_name + ".sha256"), "w") as handle:
            handle.write(text)
    asset = {"name": file_name, "size": size if size is not None else os.path.getsize(disk),
             "browser_download_url": ("https://evil.example/%s" % file_name) if evil_url else "%s/%s" % (base, file_name)}
    if digest:
        asset["digest"] = "sha256:%s" % (digest_value if digest_value is not None else actual)
    assets = [asset]
    if checksum_file:
        assets.append({"name": file_name + ".sha256", "size": 100, "browser_download_url": "%s/%s.sha256" % (base, file_name)})
    if extra_assets:
        # the fixed-name copy that the website links to, and the Windows build: neither is what the updater downloads
        assets.append({"name": "VOpenKey.dmg", "size": 1, "browser_download_url": "%s/VOpenKey.dmg" % base})
        assets.append({"name": "VOpenKey-%s-Windows.zip" % version, "size": 1, "browser_download_url": "%s/VOpenKey-%s-Windows.zip" % (base, version)})
    api = {"tag_name": tag, "draft": draft, "prerelease": prerelease, "html_url": "__BASE__/releases/tag/%s" % tag, "assets": assets}
    with open(os.path.join(folder, "api.json"), "w") as handle:
        json.dump(api, handle)
    if api_status is not None:
        with open(os.path.join(folder, "api.status"), "w") as handle:
            handle.write(str(api_status))
    if latest is not None:
        with open(os.path.join(folder, "latest.txt"), "w") as handle:
            handle.write(latest)
    for relative, content in (state_files or {}).items():
        with open(os.path.join(folder, "files", relative), "w") as handle:
            handle.write(content)
    return folder


def good_disk():
    return disk_with(lambda folder: make_app(folder))


good = good_disk()
scenario("ok", good)
scenario("nodigest", good, digest=False)                                         # the hash comes from the .sha256 file
scenario("nodigest-nosum", good, digest=False, checksum_file=False)              # nothing published: the signature decides
scenario("nodigest-badsum", good, digest=False, checksum_text="%s  x\n" % ("0" * 64))
scenario("badhash", good, digest_value="1" * 64)
scenario("badsize", good, size=os.path.getsize(good) + 7)
scenario("baddigest", good, digest_value="not-a-hash")
scenario("status500", good, state_files={FILE + ".status": "500"})
scenario("truncated", good, state_files={FILE + ".cut": "700"})
scenario("toobig", good, digest=False, checksum_file=False, state_files={FILE + ".claim": str(400 * 1000 * 1000)})
scenario("stall", good, digest=False, checksum_file=False, state_files={FILE + ".claim": "50000"})   # the server stalls: to be cancelled
scenario("evilurl", good, evil_url=True)
scenario("prerelease", good, prerelease=True)
scenario("draft", good, draft=True)
scenario("badtag", good, tag="release-9.9.9", asset_name="VOpenKey-9.9.9.dmg")
scenario("nodmg", good, asset_name="OtherName.dmg")
scenario("same", good_disk(), tag="v1.0.0")                                      # the version of the tests' app
scenario("older", good_disk(), tag="v0.9.0")
scenario("tenth", disk_with(lambda folder: make_app(folder, version="9.9.10")), tag="v9.9.10")   # 9.9.10 is newer than 9.9.9
scenario("norelease", good, api_status=404)
scenario("ratelimited", good, digest=False, api_status=403, latest=TAG)          # the page of the latest release answers
scenario("ratelimited-nofallback", good, api_status=403)
scenario("unavailable", good, api_status=500)
scenario("noapp", disk_with(lambda folder: None))                                # a disk without the app
with open(os.path.join(work, "garbage.zip"), "wb") as handle:
    handle.write(os.urandom(3000))
scenario("garbage", os.path.join(work, "garbage.zip"))

scenario("unsigned", disk_with(lambda folder: make_app(folder, sign=False)))
scenario("wrongid", disk_with(lambda folder: make_app(folder, identifier="com.evil.vopenkey")))
scenario("wrongversion", disk_with(lambda folder: make_app(folder, version="9.9.8")))
scenario("minos", disk_with(lambda folder: make_app(folder, minimum_os="99.0")))


def tampered(folder):
    app = make_app(folder)
    with open(os.path.join(app, "Contents", "Resources", "data.txt"), "a") as handle:
        handle.write("changed after signing\n")


scenario("tampered", disk_with(tampered))


def two_apps(folder):
    make_app(folder)
    make_app(folder, name="Other.app")


scenario("twoapps", disk_with(two_apps))


def app_is_a_link(folder):
    elsewhere = tempfile.mkdtemp(dir=work)
    make_app(elsewhere)
    os.symlink(os.path.join(elsewhere, APP), os.path.join(folder, APP))


scenario("linkedapp", disk_with(app_is_a_link))

# for the install tests: a ready app of the new version, and the old one that it replaces
ready = os.path.join(OUT, "_apps")
os.makedirs(os.path.join(ready, "new"))
os.makedirs(os.path.join(ready, "old"))
os.makedirs(os.path.join(ready, "wrongid"))
make_app(os.path.join(ready, "wrongid"), identifier="com.evil.vopenkey")
make_app(os.path.join(ready, "new"), version=VERSION)
make_app(os.path.join(ready, "old"), version="1.0.0")
shutil.copy(good, os.path.join(OUT, "_good.zip"))

# a real disk image, for the one test that opens it with hdiutil like the app does. Only when asked (VOK_TEST_REAL_DMG=1): it needs the
# disk image service of macOS, which a sandboxed shell does not have
if os.environ.get("VOK_TEST_REAL_DMG") == "1":
    dmg = os.path.join(work, "real.dmg")
    try:
        subprocess.check_call(["hdiutil", "create", "-volname", "VOpenKey AI 9.9.9", "-srcfolder", os.path.join(ready, "new"), "-ov", "-format", "UDZO",
                               "-fs", "HFS+", dmg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        scenario("realdmg", dmg)
    except (OSError, subprocess.CalledProcessError):
        print("hdiutil could not make a disk image: the test of the real one is skipped")
shutil.rmtree(work)
print("fixtures in", OUT)
