# Setup the user's separate local OpenJarvis, including an offline voice.
# The existing Jarvis application and its files are not touched.
$ErrorActionPreference = 'Stop'
if (-not $env:OPENJARVIS_VOICE_PORT) { $env:OPENJARVIS_VOICE_PORT = '4711' }
$voiceUrl = "http://127.0.0.1:$([int]$env:OPENJARVIS_VOICE_PORT)"
$repo = 'https://github.com/itsHALE101/OpenJarvis.git'
$root = Join-Path $env:LOCALAPPDATA 'OpenJarvis-Offline'
$src = Join-Path $root 'src'
$jarvisVoiceHome = Join-Path $env:USERPROFILE '.openjarvis'
$folder = Split-Path -Parent $MyInvocation.MyCommand.Path
$parent = (Resolve-Path (Join-Path $folder '..')).Path
$upstream = Join-Path $parent 'deploy\windows\install.ps1'
if (-not (Test-Path $upstream)) {
    throw "Installer missing: $upstream. Extract the whole ZIP, then retry."
}

Write-Host '=== OFFLINE JARVIS for Windows ===' -ForegroundColor Cyan
Write-Host "Your separate installation: $root"
Write-Host 'This uses local Ollama, local Whisper, and local Piper speech.'
Write-Host 'Initial downloads require internet. No paid voice API is enabled.'
Write-Host 'Existing Jarvis application files will not be overwritten.'
Write-Host ''

$oldConfig = $env:OPENJARVIS_CONFIG
$oldMic = $env:OPENJARVIS_MIC_RMS
$oldRepo = $env:OPENJARVIS_REPO_URL
$oldRoot = $env:OPENJARVIS_HOME
$oldSkip = $env:OPENJARVIS_SKIP_SERVICE
try {
    if (Test-Path (Join-Path $src '.git')) {
        $git = (Get-Command git -ErrorAction SilentlyContinue).Source
        if (-not $git) { throw 'Git is missing. Run the native installer first.' }
        $origin = & $git -C $src remote get-url origin
        if (($LASTEXITCODE -ne 0) -or ($origin -notmatch 'itsHALE101/OpenJarvis(\.git)?$')) {
            throw 'An unrelated project occupies the target folder. Refusing to overwrite it.'
        }
    }

    $env:OPENJARVIS_REPO_URL = $repo
    $env:OPENJARVIS_HOME = $root
    $env:OPENJARVIS_CONFIG = Join-Path $root 'config.toml'
    if (-not $env:OPENJARVIS_MIC_RMS) { $env:OPENJARVIS_MIC_RMS = '140' }
    $env:OPENJARVIS_SKIP_SERVICE = '1'
    # OpenJarvis pins Rust 1.89 in rust/rust-toolchain.toml.
    # A working generic cargo.exe is NOT enough if this exact toolchain is missing.
    # Rustup sometimes leaves an unreadable partial component in its download cache.
    Write-Host '[0/5] Checking pinned Rust 1.89 and Cargo...' -ForegroundColor Cyan
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    if (Test-Path -LiteralPath $cargoBin) { $env:Path = "$cargoBin;$env:Path" }
    $rustupExe = (Get-Command rustup.exe -ErrorAction SilentlyContinue).Source
    if (-not $rustupExe) {
        $wingetExe = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
        if (-not $wingetExe) {
            throw 'Rustup and winget are unavailable. Install the official Rustup from https://rustup.rs then retry.'
        }
        Write-Host 'Installing free official Rustup. Windows may request approval.' -ForegroundColor Yellow
        & $wingetExe install --exact --id Rustlang.Rustup --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw 'Rustup could not be installed through winget. Use https://rustup.rs then retry.'
        }
        $env:Path = "$cargoBin;$env:Path"
        $rustupExe = (Get-Command rustup.exe -ErrorAction SilentlyContinue).Source
        if (-not $rustupExe) {
            throw 'Rustup was installed, but Windows has not loaded it into PATH. Open a fresh PowerShell and run the installer again.'
        }
    }

    $rustupRoot = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { Join-Path $env:USERPROFILE '.rustup' }
    $rustDownloads = [System.IO.Path]::GetFullPath((Join-Path $rustupRoot 'downloads')).TrimEnd('\')
    $rustupStdout = Join-Path $env:TEMP 'Jarvis_Rustup.stdout.log'
    $rustupStderr = Join-Path $env:TEMP 'Jarvis_Rustup.stderr.log'
    $rustInstalled = $false

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Host "Installing/checking required Rust 1.89.0 (attempt $attempt of 3)..." -ForegroundColor Cyan
        # Separate stdout/stderr capture avoids Windows PowerShell 5.1 turning
        # ordinary native stderr into a terminating error before retries run.
        try {
            $rustProc = Start-Process -FilePath $rustupExe -ArgumentList @(
                'toolchain','install','1.89.0','--profile','minimal',
                '--component','rustfmt','--component','clippy'
            ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $rustupStdout -RedirectStandardError $rustupStderr
            $resultCode = $rustProc.ExitCode
        } catch {
            throw "Rustup could not run on this PC: $($_.Exception.Message). Check Windows Security Protection History for blocked executables."
        }

        $rustLog = ''
        if (Test-Path -LiteralPath $rustupStdout) {
            $rustLog += [System.IO.File]::ReadAllText($rustupStdout)
        }
        if (Test-Path -LiteralPath $rustupStderr) {
            $rustLog += [Environment]::NewLine + [System.IO.File]::ReadAllText($rustupStderr)
        }
        if ($rustLog.Trim()) { Write-Host $rustLog }

        if ($resultCode -eq 0) {
            $rustInstalled = $true
            break
        }

        if ($attempt -eq 1) {
            # Only remove the specific corrupt Rustup cache blob named in its
            # own error. Never clear the entire cache or any other user files.
            $badFileMatch = [regex]::Match(
                $rustLog,
                "(?i)could not read downloaded file:\s*'(?<file>[^']+)'"
            )
            if ($badFileMatch.Success) {
                $badFile = $badFileMatch.Groups['file'].Value
                try {
                    $badFile = [System.IO.Path]::GetFullPath($badFile)
                    $badParent = [System.IO.Path]::GetDirectoryName($badFile).TrimEnd('\')
                    $badName = [System.IO.Path]::GetFileName($badFile)
                    if (
                        [string]::Equals($badParent, $rustDownloads, [System.StringComparison]::OrdinalIgnoreCase) -and
                        $badName -match '^[0-9a-fA-F]{64}$' -and
                        (Test-Path -LiteralPath $badFile -PathType Leaf)
                    ) {
                        Write-Host 'Removing only the damaged Rust download cache file before retry.' -ForegroundColor Yellow
                        Remove-Item -LiteralPath $badFile -Force -ErrorAction Stop
                    }
                } catch {
                    Write-Warning "Could not clear the specific failed Rust cache file: $($_.Exception.Message)"
                }
            }
        }
        if ($attempt -lt 3) {
            Write-Host 'Rust download was interrupted; retrying from the official Rust servers...' -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    }
    if (-not $rustInstalled) {
        throw "Rust 1.89.0 could not install after 3 attempts. Details in $rustupStderr. Check free disk space and Windows Security Protection History; do not disable antivirus."
    }

    # Verify the exact compiler that the OpenJarvis Rust workspace will use.
    & $rustupExe run '1.89.0' rustc --version
    if ($LASTEXITCODE -ne 0) { throw 'Rust 1.89 compiler failed its version check.' }
    & $rustupExe run '1.89.0' cargo --version
    if ($LASTEXITCODE -ne 0) { throw 'Cargo for Rust 1.89 failed its version check.' }
    Write-Host 'Rust 1.89 and Cargo verified; continuing OpenJarvis installation.' -ForegroundColor Green

    Write-Host '[1/5] Installing OpenJarvis and the local AI model...' -ForegroundColor Cyan
    & $upstream -SkipService
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Installer returned code $LASTEXITCODE" }

    $voiceDir = Join-Path $src 'jarvis_voice_setup'
    $ttsModule = Join-Path $src 'src\openjarvis\speech\jarvis_local_tts.py'
    if (-not (Test-Path $ttsModule)) { throw 'Local voice integration missing from clone.' }
    if (-not (Test-Path (Join-Path $voiceDir '01_Setup_Offline_Voice.bat'))) {
        throw 'Offline voice setup missing from clone.'
    }

    $uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
    if (-not $uv) { $uv = Join-Path $env:USERPROFILE '.local\bin\uv.exe' }
    if (-not (Test-Path $uv)) { throw 'uv missing after installation.' }

    $env:Path = "$(Split-Path -Parent $uv);$env:Path"
    Write-Host '[2/5] Installing the British Piper voice...' -ForegroundColor Cyan
    & (Join-Path $voiceDir '01_Setup_Offline_Voice.bat')
    if ($LASTEXITCODE -ne 0) { throw 'Local Piper voice setup failed.' }

    Write-Host '[3/5] Installing local microphone and voice playback dependencies...' -ForegroundColor Cyan
    Push-Location $src
    try {
        # The desktop extra already includes local Whisper, sounddevice and soundfile.
        # Piper runs in its own environment; the Kokoro voice extra is unnecessary.
        & .\.venv\Scripts\python.exe -c "from faster_whisper import WhisperModel; import sounddevice, soundfile; WhisperModel('base',device='cpu',compute_type='int8')"
        if ($LASTEXITCODE -ne 0) { throw 'Speech dependencies failed to install.' }
    } finally { Pop-Location }

    Write-Host '[4/5] Configuring Jarvis and backing up existing settings...' -ForegroundColor Cyan
    $python = Join-Path $src '.venv\Scripts\python.exe'
    if (-not (Test-Path $python)) { throw 'OpenJarvis Python environment missing.' }
    & $python (Join-Path $voiceDir 'configure_voice.py')
    if ($LASTEXITCODE -ne 0) { throw 'Jarvis configuration failed.' }

    Write-Host '[5/5] Starting the local offline voice...' -ForegroundColor Cyan
    $voicePython = Join-Path $jarvisVoiceHome 'offline-voice-venv\Scripts\python.exe'
    $voiceServer = Join-Path $voiceDir 'voice_server.py'
    if (-not (Test-Path $voicePython)) { throw 'Offline voice Python missing.' }
    $ready = $false
    try {
        $check = Invoke-RestMethod -Uri "$voiceUrl/health" -TimeoutSec 2
        $ready = ($check.ready -eq $true)
    } catch { }
    if (-not $ready) {
        Start-Process -FilePath $voicePython -ArgumentList ('"' + $voiceServer + '"') -WindowStyle Hidden -WorkingDirectory $voiceDir
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 500
            try {
                $check = Invoke-RestMethod -Uri "$voiceUrl/health" -TimeoutSec 2
                if ($check.ready -eq $true) { $ready = $true; break }
            } catch { }
        }
    }
    if (-not $ready) { throw 'Local speech service not ready. Run 02_Start_Offline_Voice.bat to inspect.' }

    $wav = Join-Path $env:TEMP 'jarvis_local_voice_test.wav'
    $params = @{
        Uri = "$voiceUrl/speak"
        Method = 'POST'
        ContentType = 'application/json'
        Body = '{"text":"Good day sir. Your offline Jarvis is now ready."}'
        OutFile = $wav
        UseBasicParsing = $true
        TimeoutSec = 180
    }
    Invoke-WebRequest @params
    if (-not (Test-Path $wav) -or (Get-Item $wav).Length -lt 44) {
        throw 'Local voice returned no usable WAV data.'
    }
    Write-Host "Test voice created successfully: $wav" -ForegroundColor Green
    Start-Process -FilePath $wav
    Write-Host ''
    Write-Host 'Setup completed. Starting Jarvis voice chat...' -ForegroundColor Green
    $jarvisExe = Join-Path $src '.venv\Scripts\jarvis.exe'
    if (-not (Test-Path $jarvisExe)) { throw 'Jarvis CLI missing after install.' }
    Push-Location $src
    try { & $jarvisExe chat --voice --engine ollama --skip-runtime-panel }
    finally { Pop-Location }
} finally {
    $env:OPENJARVIS_CONFIG = $oldConfig
    $env:OPENJARVIS_MIC_RMS = $oldMic
    $env:OPENJARVIS_REPO_URL = $oldRepo
    $env:OPENJARVIS_HOME = $oldRoot
    $env:OPENJARVIS_SKIP_SERVICE = $oldSkip
}
