#!/bin/zsh
# Builds the classes for "AI on this Mac" and runs their tests: the list of models, the reading of the Mac, the advisor, the
# validation of the list (engine/tests/validate_local_models.py), and the talk with Ollama against the fake server
# mock_ollama_server.py, which it starts and stops, and the installation of Ollama (checks of the download and of the signature)
# against the same server playing GitHub. Nothing is downloaded from the internet, nothing is installed outside a temporary folder.
#
#   Sources/OpenKey/macOS/tests/run-ai-local-test.sh
#   VOK_OLLAMA_ZIP=/path/to/Ollama-darwin.zip Sources/OpenKey/macOS/tests/run-ai-local-test.sh   # also with the official download
#
# The official download (https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip, 200 MB) is not in the
# repository; with it the tests prove that the real signature passes and that a changed copy does not. Without it they say SKIPPED.
#
# Everything is built in a temporary folder that is removed afterwards.
set -e
HERE=${0:A:h}
MAC=${HERE:h}/ModernKey
ENGINE=${HERE:h:h}/engine
WORK=$(mktemp -d)
SERVER=""
cleanup() {
    [ -n "$SERVER" ] && kill $SERVER 2>/dev/null
    pkill -f "$WORK/" 2>/dev/null     # a server of the tests that a failed test left running (they live in this folder)
    rm -rf "$WORK"
}
trap cleanup EXIT
cd "$WORK"

python3 -I "$ENGINE/tests/validate_local_models.py" "$ENGINE/ai/local-models.json"

for f in AIHardware AILocalModels AIModelAdvisor AIOllama AIOllamaInstaller AIOllamaRuntime AILocalSetup AIClient AIProvider AISettings AIKeychain AIAgentCLI AIAgentProcess AIAgentRunner VOKUI AILocalSetupController AILocalControl; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$MAC/$f.m" -o $f.o
done
for t in ai_local_advisor_test ai_ollama_test ai_local_install_test ai_local_runtime_test ai_local_setup_test ai_local_ui_test ai_local_control_test; do
    clang -fobjc-arc -Wall -g -I"$MAC" -c "$HERE/$t.m" -o $t.o
done
clang -framework Cocoa -framework IOKit AIHardware.o AILocalModels.o AIModelAdvisor.o ai_local_advisor_test.o -o ai_local_advisor_test
clang -framework Cocoa AIOllama.o ai_ollama_test.o -o ai_ollama_test
clang -framework Cocoa -framework Security AIOllama.o AIOllamaInstaller.o ai_local_install_test.o -o ai_local_install_test
clang -framework Cocoa -framework Security AIOllama.o AIOllamaInstaller.o AIOllamaRuntime.o ai_local_runtime_test.o -o ai_local_runtime_test
clang -framework Cocoa -framework Security -framework IOKit AIHardware.o AILocalModels.o AIOllama.o AIOllamaInstaller.o AIOllamaRuntime.o AILocalSetup.o \
    AIClient.o AIAgentCLI.o AIAgentProcess.o AIAgentRunner.o AIProvider.o AISettings.o AIKeychain.o ai_local_setup_test.o -o ai_local_setup_test
clang -framework Cocoa -framework Security -framework IOKit AIHardware.o AIOllama.o AIOllamaInstaller.o AIOllamaRuntime.o AILocalControl.o ai_local_control_test.o -o ai_local_control_test
clang -framework Cocoa -framework Security -framework IOKit AIHardware.o AILocalModels.o AIModelAdvisor.o AIOllama.o AIOllamaInstaller.o AIOllamaRuntime.o AILocalSetup.o \
    AILocalSetupController.o VOKUI.o AIClient.o AIAgentCLI.o AIAgentProcess.o AIAgentRunner.o AIProvider.o AISettings.o AIKeychain.o ai_local_ui_test.o -o ai_local_ui_test
cp "$ENGINE/ai/local-models.json" fixtures/local-models.json 2>/dev/null || { mkdir -p fixtures && cp "$ENGINE/ai/local-models.json" fixtures/local-models.json; }

# The fixtures of the installation tests. The "fake" Ollama has the right name and the right layout, and is signed, but only ad hoc:
# what an attacker can make.
mkdir -p fixtures fake/Ollama.app/Contents/MacOS fake/Ollama.app/Contents/Resources
cat > fake/main.c <<'CEND'
int main(void) { return 0; }
CEND
clang fake/main.c -o fake/Ollama.app/Contents/MacOS/Ollama
cp fake/Ollama.app/Contents/MacOS/Ollama fake/Ollama.app/Contents/Resources/ollama
cat > fake/Ollama.app/Contents/Info.plist <<'PEND'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.electron.ollama</string>
<key>CFBundleExecutable</key><string>Ollama</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PEND
codesign --force --deep -s - fake/Ollama.app 2>/dev/null
ditto -c -k --keepParent fake/Ollama.app fixtures/fake.zip
mkdir extra wrongname
cp -R fake/Ollama.app extra/Ollama.app; echo "evil" > extra/evil.txt
cp -R fake/Ollama.app wrongname/Other.app
ditto -c -k extra fixtures/extra.zip
ditto -c -k wrongname fixtures/wrongname.zip
head -c 3000 /dev/urandom > fixtures/notzip.zip
mkdir big && cp -R fake/Ollama.app big/Ollama.app && head -c 4000000 /dev/urandom > big/Ollama.app/Contents/Resources/padding.bin
ditto -c -k --keepParent big/Ollama.app fixtures/big.zip
# A stand-in for Ollama that really starts and answers (fake_ollama.py), in the layout of the application, for the tests of the
# whole installation. "bigollama" has 4 MB of padding so that its download takes time and can be cancelled.
mkdir -p fakeollama && cp -R fake/Ollama.app fakeollama/Ollama.app
cp "$HERE/fake_ollama.py" fakeollama/Ollama.app/Contents/Resources/ollama && chmod +x fakeollama/Ollama.app/Contents/Resources/ollama
ditto -c -k --keepParent fakeollama/Ollama.app fixtures/fakeollama.zip
cp -R fakeollama/Ollama.app bigollama.app && mkdir bigollama && mv bigollama.app bigollama/Ollama.app
head -c 4000000 /dev/urandom > bigollama/Ollama.app/Contents/Resources/padding.bin
ditto -c -k --keepParent bigollama/Ollama.app fixtures/bigollama.zip
if [ -n "$VOK_OLLAMA_ZIP" ] && [ -f "$VOK_OLLAMA_ZIP" ]; then
    cp "$VOK_OLLAMA_ZIP" fixtures/real.zip
    mkdir tamper && ditto -x -k fixtures/real.zip tamper
    echo "<!-- changed -->" >> tamper/Ollama.app/Contents/Info.plist
    ditto -c -k --keepParent tamper/Ollama.app fixtures/tampered.zip
fi

perl -e 'alarm 120; exec @ARGV' ./ai_local_advisor_test "$ENGINE/ai/local-models.json"

python3 -I "$HERE/mock_ollama_server.py" --zip fixtures/fake.zip > port.txt &
SERVER=$!
for i in {1..50}; do [ -s port.txt ] && break; sleep 0.1; done
PORT=$(head -1 port.txt)
[ -n "$PORT" ] || { echo "the fake server did not start"; exit 2; }
DEAD=$(python3 -I -c "import socket; s = socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
perl -e 'alarm 180; exec @ARGV' ./ai_ollama_test "$PORT" "$DEAD"
perl -e 'alarm 600; exec @ARGV' ./ai_local_install_test "$PORT" "$DEAD" "$WORK/fixtures"

# the server of the runtime and setup tests listens on a port of its own
FREE=$(python3 -I -c "import socket; s = socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
mkdir -p run-folder
export FAKE_OLLAMA_LOG="$WORK/run-folder/starts.log"
perl -e 'alarm 300; exec @ARGV' ./ai_local_runtime_test "$HERE/fake_ollama.py" "$FREE" "$PORT" "$WORK/run-folder"
mkdir -p control-folder
perl -e 'alarm 300; exec @ARGV' ./ai_local_control_test "$HERE/fake_ollama.py" "$FREE" "$WORK/control-folder"
mkdir -p setup-folder
perl -e 'alarm 600; exec @ARGV' ./ai_local_setup_test "$WORK/fixtures" "$PORT" "$FREE" "$HERE/fake_ollama.py" "$WORK/setup-folder"
mkdir -p ui-folder
# the window needs a screen; without one (no login session) these tests are skipped and say so
if [ -n "$VOK_NO_UI" ]; then
    echo "SKIPPED: ai_local_ui_test (VOK_NO_UI is set)"
else
    perl -e 'alarm 600; exec @ARGV' ./ai_local_ui_test "$WORK/fixtures" "$PORT" "$FREE" "$HERE/fake_ollama.py" "$WORK/ui-folder" ${VOK_SHOTS:-}
fi
STATUS=$?
rm -f "$HOME/Library/Preferences/ai_local_setup_test.plist" "$HOME/Library/Preferences/ai_local_ui_test.plist"
exit $STATUS
