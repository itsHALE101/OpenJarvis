# Exercise only the Ollama stage of the native installer; never install software in tests.
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'install.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)
if ($errors) { throw ($errors | Out-String) }
$names = 'Find-OllamaExecutable','Get-LocalOllamaTags','Wait-OllamaInstaller','Install-OllamaIfMissing','Initialize-LocalOllama'
foreach ($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
    if ($names -contains $fn.Name) { . ([scriptblock]::Create($fn.Extent.Text)) }
}
function Assert($Value,$Text) { if (-not $Value) { throw $Text }; Write-Host "PASS $Text" }
function Write-Info($s) {}
function Write-Ok($s) {}

# Live test when requested; it can only list installed models.
if ($env:OPENJARVIS_TEST_LIVE -eq '1') {
    $before = $env:Path
    try {
        $env:Path = "$env:SystemRoot\System32"
        $real = Find-OllamaExecutable
        Assert (Test-Path -LiteralPath $real) 'find installed Ollama with stale PATH'
        & $real list
        Assert ($LASTEXITCODE -eq 0) 'real CLI can list models'
    } finally { $env:Path = $before }
}

$tags = [pscustomobject]@{models=@([pscustomobject]@{name='qwen3.8:27b'})}
$empty = [pscustomobject]@{models=@()}
$waiter = [pscustomobject]@{ ExitCode=0; Id=123; Finished=$true }
$waiter | Add-Member ScriptMethod WaitForExit { param($ms) return $this.Finished }
Wait-OllamaInstaller $waiter 'test.log'
$waiter.ExitCode=4
try { Wait-OllamaInstaller $waiter 'test.log'; throw 'no failure' } catch { Assert ($_.Exception.Message -like '*exited with 4*') 'failed installer returns its exit code' }
$waiter.Finished=$false
try { Wait-OllamaInstaller $waiter 'test.log' 0; throw 'no failure' } catch { Assert ($_.Exception.Message -like '*still running*') 'bounded installer wait' }

function Get-LocalOllamaTags { return $script:sample }
function Find-OllamaExecutable { return $script:fakeExe }
function Install-OllamaIfMissing { $script:installed++; $script:sample=$empty }
function Invoke-RestMethod { $script:pulled++; return @{status='success'} }
function Start-Process { $script:started++ }
function Start-Sleep {}
$script:fakeExe=$null; $script:sample=$tags; $script:installed=0; $script:pulled=0
Initialize-LocalOllama
Assert ($installed -eq 0 -and $pulled -eq 0) 'daemon-only install reuses Qwen'
$script:sample=$empty
Initialize-LocalOllama
Assert ($installed -eq 0 -and $pulled -eq 1) 'missing Qwen triggers one model pull'
$script:sample=$null
Initialize-LocalOllama
Assert ($installed -eq 1 -and $pulled -eq 2) 'clean install then starter model'
$script:sample=$null; $script:fakeExe='installed.exe'; $script:started=0
try { Initialize-LocalOllama; throw 'no failure' } catch {
    Assert ($_.Exception.Message -like '*did not answer*' -and $started -eq 1 -and $installed -eq 1) 'unavailable daemon retried without reinstall'
}
