# Runs a walkthrough and checks/dismisses Android's native share sheets.
param([string]$Target = 'integration_test/progress_data_walkthrough_test.dart')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$backend = ([uri](Get-Content .env.mobile.json -Raw | ConvertFrom-Json).SUPABASE_URL).Host
$ready = $false
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    try { $lookup = & $adb -s emulator-5554 shell ping -c 1 -W 1 $backend 2>&1 }
    catch { $lookup = '' } # adb can report an offline device while Android boots.
    # ICMP may be blocked; the resolved address, not a ping reply, proves DNS.
    if ("$lookup" -match 'PING .+\([0-9a-fA-F:.]+\)') { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) { throw "Android cannot resolve $backend. Check emulator DNS before running the walkthrough." }
$log = Join-Path (Get-Location) '.ticket13-walkthrough.log'
$errLog = Join-Path (Get-Location) '.ticket13-walkthrough-error.log'
$flutter = (Get-Command flutter).Source
$run = Start-Process -FilePath $flutter -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $errLog -ArgumentList @(
    'test', $Target, '-d', 'emulator-5554',
    '--dart-define-from-file=.env.mobile.json', '--dart-define-from-file=.env.test.json'
)
$null = $run.Handle
$handled = @{}
$deadline = (Get-Date).AddMinutes(30)
while (-not $run.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    $output = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    foreach ($marker in @('TICKET13_CARD_SHARE_OPEN', 'TICKET13_EXPORT_SHARE_OPEN')) {
        if ($output -match $marker -and -not $handled.ContainsKey($marker)) {
            Start-Sleep -Seconds 1
            $activity = & $adb -s emulator-5554 shell dumpsys activity activities
            if (-not ($activity -match '(mResumedActivity|topResumedActivity).*ChooserActivity')) {
                throw "Native Android share sheet was not visible: $marker"
            }
            Write-Output "$marker : Android ChooserActivity verified"
            if ($marker -eq 'TICKET13_CARD_SHARE_OPEN') {
                & $adb -s emulator-5554 shell pm grant com.example.smart_scrolling android.permission.POST_NOTIFICATIONS
            }
            & $adb -s emulator-5554 shell input keyevent 4
            $handled[$marker] = $true
        }
    }
    $run.Refresh()
}
Get-Content -LiteralPath $log -Tail 35
Get-Content -LiteralPath $errLog -Tail 20
if (-not $run.HasExited) { throw 'Walkthrough timed out; inspect Flutter and emulator before retrying.' }
$run.WaitForExit()
$output = Get-Content -LiteralPath $log -Raw
if (($null -ne $run.ExitCode -and $run.ExitCode -ne 0) -or $handled.Count -ne 2 -or
    -not ($output -match 'TICKET13_COMPLETE') -or -not ($output -match 'All tests passed!')) {
    throw "Walkthrough failed: $Target"
}
