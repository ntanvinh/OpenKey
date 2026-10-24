<#
 Smoke test of the real Windows program, driven by keyboard input like a user. For the CI (windows-build.yml) and for a
 Windows machine or virtual machine that an agent reaches over SSH. It needs an interactive desktop (a logged in session).

   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows-ui-test.ps1 -Exe path\to\OpenKey64.exe [-Out shots]

 What it does: sets the program's settings in the registry (the user's own are saved and put back), starts it, opens a window with a
 text box, types Vietnamese in Telex through SendInput and checks the text; checks that the windows of the features open and
 close with their shortcuts; saves a screenshot after every step. Exit code 0 when everything passed, 1 otherwise.
 Nothing here proves more than what it prints: a step that could not run is "SKIP", not "PASS".
#>
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string]$Out = "ui-test-shots"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class VokInput {
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTUNION u; }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public static void Key(ushort vk, bool down) {
        INPUT[] i = new INPUT[1];
        i[0].type = 1; i[0].u.ki.wVk = vk; i[0].u.ki.dwFlags = down ? 0u : 2u;
        if (vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28) i[0].u.ki.dwFlags |= 1u;
        SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@

$results = New-Object System.Collections.ArrayList
$script:shot = 0
function Report($name, $state, $detail) {
    [void]$results.Add([pscustomobject]@{ Step = $name; Result = $state; Detail = $detail })
    Write-Host ("{0,-5} {1}  {2}" -f $state, $name, $detail)
}
function Pump($ms) {
    $end = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
}
function Shot($name) {
    try {
        New-Item -ItemType Directory -Force -Path $Out | Out-Null
        $script:shot++
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save((Join-Path $Out ("{0:00}-{1}.png" -f $script:shot, $name)))
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Host "no screenshot: $_" }
}
$VK = @{ Shift = 0x10; Ctrl = 0x11; Alt = 0x12; Enter = 0x0D; Esc = 0x1B; Tab = 0x09; Space = 0x20; Down = 0x28; Back = 0x08 }
function Press($vk, [string[]]$mods = @()) {
    foreach ($m in $mods) { [VokInput]::Key([uint16]$VK[$m], $true) }
    [VokInput]::Key([uint16]$vk, $true); [VokInput]::Key([uint16]$vk, $false)
    foreach ($m in ($mods | Sort-Object -Descending)) { [VokInput]::Key([uint16]$VK[$m], $false) }
    Pump 60
}
function TypeText([string]$text) {
    foreach ($c in $text.ToCharArray()) {
        $u = [char]::ToUpper($c)
        if ($c -eq ' ') { Press 0x20; continue }
        $isUpper = [char]::IsUpper($c)
        Press ([int][char]$u) $(if ($isUpper) { @("Shift") } else { @() })
    }
    Pump 200
}
function WindowOpen($class) {
    $h = [VokInput]::FindWindow($class, $null)
    return ($h -ne [IntPtr]::Zero -and [VokInput]::IsWindowVisible($h))
}
function WaitWindow($class, $open, $ms = 3000) {
    $end = [DateTime]::Now.AddMilliseconds($ms)
    while ([DateTime]::Now -lt $end) { if ((WindowOpen $class) -eq $open) { return $true }; Pump 100 }
    return ((WindowOpen $class) -eq $open)
}

# --- settings: saved, set for the test, put back at the end
$key = "HKCU:\SOFTWARE\TuyenMai\OpenKey"
$saved = $null
if (Test-Path $key) { $saved = Get-ItemProperty $key }
New-Item -Force -Path $key | Out-Null
$test = @{ vLanguage = 1; vInputType = 0; vCodeTable = 0; vShowOnStartUp = 0; vRunWithWindows = 0; vCheckNewVersion = 0; vRunAsAdmin = 0;
           vCheckSpelling = 1; vSuggestEnabled = 1; vSnippetsEnabled = 1; vUseMacro = 0; vUseSmartSwitchKey = 0; vRememberCode = 0 }
foreach ($k in $test.Keys) { Set-ItemProperty -Path $key -Name $k -Value $test[$k] -Type DWord }

$app = $null
$form = $null
try {
    $app = Start-Process -FilePath $Exe -PassThru
    Pump 2500
    if ($app.HasExited) { Report "program starts" "FAIL" "exited with code $($app.ExitCode)"; throw "stopped" }
    Report "program starts" "PASS" "pid $($app.Id)"

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "vok-ui-test"; $form.Width = 700; $form.Height = 300; $form.TopMost = $true; $form.StartPosition = "CenterScreen"
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true; $box.Dock = "Fill"; $box.Font = New-Object System.Drawing.Font("Segoe UI", 16)
    $form.Controls.Add($box)
    $form.Show(); $form.Activate(); $box.Focus() | Out-Null
    [void][VokInput]::SetForegroundWindow($form.Handle)
    Pump 600
    if ([VokInput]::GetForegroundWindow() -ne $form.Handle) {
        Report "test window has the keyboard" "SKIP" "no interactive desktop: the keyboard steps below are not valid"
        throw "stopped"
    }

    # 1. typing Vietnamese (Telex)
    TypeText "Vieetj Nam"
    Shot "telex"
    $want = "Vi$([char]0x1EC7)t Nam"
    if ($box.Text -eq $want) { Report "Telex: Vieetj Nam" "PASS" $box.Text } else { Report "Telex: Vieetj Nam" "FAIL" ("got '{0}'" -f $box.Text) }

    # 2. the suggestion bar shows while a word is typed
    $box.Clear(); Pump 100
    TypeText "xin "
    TypeText "ch"
    Pump 500
    Shot "suggestion-bar"
    if (WindowOpen "VOpenKeyAISuggestionBar") { Report "suggestion bar shows" "PASS" "" } else { Report "suggestion bar shows" "FAIL" "no bar after 'xin ch'" }
    Press $VK.Esc
    if (WaitWindow "VOpenKeyAISuggestionBar" $false 1500) { Report "Esc hides the bar" "PASS" "" } else { Report "Esc hides the bar" "FAIL" "bar still visible" }

    # 3. snippets: Ctrl+Alt+S opens, Esc closes
    [void][VokInput]::SetForegroundWindow($form.Handle); Pump 300
    Press 0x53 @("Ctrl", "Alt")
    if (WaitWindow "VOpenKeyAISnippetPalette" $true) { Report "snippet window opens" "PASS" "" } else { Report "snippet window opens" "FAIL" "" }
    Shot "snippets"
    Press $VK.Esc
    if (WaitWindow "VOpenKeyAISnippetPalette" $false) { Report "snippet window closes" "PASS" "" } else { Report "snippet window closes" "FAIL" "" }

    # 4. case list: select the text, Ctrl+Alt+C, choose the first row (upper case)
    [void][VokInput]::SetForegroundWindow($form.Handle); Pump 300
    $box.Text = "xin chao the gioi"; $box.SelectAll(); Pump 200
    Press 0x43 @("Ctrl", "Alt")
    if (WaitWindow "VOpenKeyAICaseBar" $true 4000) {
        Shot "case-list"
        Press $VK.Enter
        Pump 1200
        if ($box.Text -ceq "XIN CHAO THE GIOI") { Report "case list changes the selection" "PASS" $box.Text } else { Report "case list changes the selection" "FAIL" ("got '{0}'" -f $box.Text) }
    } else { Report "case list opens" "FAIL" "" }

    # 5. the AI assistant opens (no request is made)
    [void][VokInput]::SetForegroundWindow($form.Handle); Pump 300
    Press 0x41 @("Ctrl", "Alt")
    if (WaitWindow "VOpenKeyAIAssistant" $true 4000) { Report "AI window opens" "PASS" "" ; Shot "ai"; Press $VK.Esc } else { Report "AI window opens" "FAIL" "" }
}
catch { if ($_.ToString() -ne "stopped") { Report "unexpected error" "FAIL" $_.ToString() } }
finally {
    Shot "end"
    if ($form) { $form.Close() }
    if ($app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force }
    if ($saved) { foreach ($k in $test.Keys) { if ($saved.PSObject.Properties.Name -contains $k) { Set-ItemProperty -Path $key -Name $k -Value $saved.$k -Type DWord } else { Remove-ItemProperty -Path $key -Name $k -ErrorAction SilentlyContinue } } }
    else { Remove-Item -Recurse -Force $key -ErrorAction SilentlyContinue }
}

$failed = @($results | Where-Object { $_.Result -eq "FAIL" }).Count
$skipped = @($results | Where-Object { $_.Result -eq "SKIP" }).Count
Write-Host ""
Write-Host ("{0} passed, {1} failed, {2} skipped" -f @($results | Where-Object { $_.Result -eq "PASS" }).Count, $failed, $skipped)
$results | ConvertTo-Json | Set-Content -Path (Join-Path $Out "result.json") -ErrorAction SilentlyContinue
if ($failed -gt 0 -or $skipped -gt 0) { exit 1 }
exit 0
