# Restart the separate local OpenJarvis installation (no installation needed).
$ErrorActionPreference = 'Stop'
if (-not $env:OPENJARVIS_VOICE_PORT) { $env:OPENJARVIS_VOICE_PORT = '4711' }
$voiceUrl = "http://127.0.0.1:$([int]$env:OPENJARVIS_VOICE_PORT)"
$root = Join-Path $env:LOCALAPPDATA 'OpenJarvis-Offline'
$src = Join-Path $root 'src'
$voiceDir = Join-Path $src 'jarvis_voice_setup'
$python = Join-Path $env:USERPROFILE '.openjarvis\offline-voice-venv\Scripts\python.exe'
$voice = Join-Path $voiceDir 'voice_server.py'
$jarvis = Join-Path $src '.venv\Scripts\jarvis.exe'
foreach ($path in @($python,$voice,$jarvis)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'OpenJarvis is not installed yet. Run START_OFFLINE_JARVIS_WINDOWS.bat first.'
    }
}
$env:OPENJARVIS_HOME = $root
$env:OPENJARVIS_CONFIG = Join-Path $root 'config.toml'
if (-not $env:OPENJARVIS_MIC_RMS) { $env:OPENJARVIS_MIC_RMS = '140' }
$env:HF_HUB_OFFLINE = '1'
try { $null = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 }
catch {
    $bin = Get-Command ollama.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $bin) { $bin = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe' }
    if (-not (Test-Path -LiteralPath $bin)) { throw 'Local Ollama is unavailable. Open the installed Ollama app and retry.' }
    Start-Process $bin -ArgumentList 'serve' -WindowStyle Hidden
    $online = $false
    for ($i=0; $i -lt 30; $i++) {
        try { $null = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2; $online=$true; break } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $online) { throw 'Installed Ollama did not start on port 11434.' }
}
$ready = $false
try {
    $status = Invoke-RestMethod -Uri "$voiceUrl/health" -TimeoutSec 2
    $ready = ($status.ready -eq $true)
} catch { }
if (-not $ready) {
    Start-Process -FilePath $python -ArgumentList ('"' + $voice + '"') -WindowStyle Hidden -WorkingDirectory $voiceDir | Out-Null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        try {
            $status = Invoke-RestMethod -Uri "$voiceUrl/health" -TimeoutSec 2
            if ($status.ready -eq $true) { $ready = $true; break }
        } catch { }
    }
}
if (-not $ready) {
    throw 'Local voice service did not start. Use 02_Start_Offline_Voice.bat to view the error.'
}
Push-Location $src
try {
    & $jarvis chat --voice --engine ollama --skip-runtime-panel
} finally {
    Pop-Location
}
