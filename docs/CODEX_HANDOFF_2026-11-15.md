# Jarvis offline assistant — Codex handover (15 November 2026)

> Purpose: continue and **finish the existing Windows Jarvis AI installation**, not start a new assistant or unrelated project. This is a technical handover from a ChatGPT troubleshooting conversation after an earlier conversation crashed. It contains no private conversation transcript or credentials.

## Project and environment

- Repository: `itsHALE101/OpenJarvis` (this repository), default branch `main`. User's offline Windows installation is a **separate** instance intended to preserve their existing Jarvis.
- Installer/bootstrap previously used: `START_JARVIS_OFFLINE_*.bat` scripts. Different historical copies pin different commits, so **identify the exact version locally before applying a patch**.
- Windows install tree observed in Explorer: `%LOCALAPPDATA%\OpenJarvis-Offline\src`; includes `.venv`, `jarvis_voice_setup`, `rust`, `deploy`, etc.
- Desired result: free, local/offline Jarvis with Ollama/Qwen inference, Whisper speech recognition, Piper offline British voice, and `jarvis chat --voice` working. Preserve existing installations and config. Do not introduce paid APIs or unnecessary rebuilds.

## What is actually verified

1. The user ran Ollama in a Command Prompt; it downloaded a Qwen model (roughly 16 GB among its layers), printed `success`, displayed the `>>> ` prompt, and generated a relevant response identifying itself as Qwen. This **proves that Ollama + at least one Qwen model worked in that terminal**; the exact Ollama model tag, GPU/CPU use and voice integration have **not** been verified.
2. The Jarvis installer printed `[ok] Dependencies installed` and `[info] Checking Ollama...` followed by `[info] Ollama not on PATH - downloading the official installer (~150 MB)...` and `[info] Running OllamaSetup.exe /S (this can take a minute)...`.
3. Multiple screenshots showed the Jarvis installer still stopped at the same `Running OllamaSetup.exe /S` line. This could be a silent-installer stall or environment/PATH mismatch; do **not** assert a root cause without investigating.
4. The user was asked to open a **second** Command Prompt and run `where ollama` and `tasklist /FI "IMAGENAME eq OllamaSetup.exe"`. Results are **not yet available**.
5. Files under the install tree exist, but **the full Jarvis voice setup has not yet been shown working**.

## Relevant source-code findings

In `deploy/windows/install.ps1` (inspected on `main` on 15 Nov 2026):
- Around lines 398–431, installer calls `(Get-Command ollama -ErrorAction SilentlyContinue).Source`.
- When not found on current process PATH, it downloads `https://ollama.com/download/OllamaSetup.exe`, then runs `Start-Process -FilePath $ollamaSetup -ArgumentList '/S' -Wait` with **no explicit timeout**.
- It then refreshes PATH from the registry, retries `Get-Command`, and may fail if the Ollama executable still isn't discoverable.
- Around lines 434–461 it tests `ollama list`, starts `ollama serve` as fallback, and waits for a responsive daemon.
- Around lines 462 onward it pulls the starter `qwen3.5:2b` model. The already-downloaded 16 GB Qwen model should not be confused with this exact tag; check `ollama list` locally.

In `jarvis_voice_setup/one_click_windows.ps1`:
- Calls Windows installation, then `jarvis_voice_setup/01_Setup_Offline_Voice.bat` for Piper, installs speech/desktop dependencies, runs `configure_voice.py`, checks the local voice service at `http://127.0.0.1:4701/health`, posts to `/speak` to create a WAV voice test, then starts `.venv\Scripts\jarvis.exe chat --voice`.
- Review these steps in the exact pinned/local revision, not solely `main`.

## Requested work for Codex

Take ownership of this **existing** Jarvis project and resolve the installer issue end-to-end.

1. Inspect the existing code, current branches/working tree and exact pinned bootstrap revision. Reproduce the PATH/reinstall problem on Windows if possible. Preserve the user's existing installation, Qwen model, settings, and data.
2. Make Ollama detection **idempotent**: check existing executable installations (including standard per-user Windows install path), optionally probe the local Ollama daemon, refresh PATH where appropriate, and verify `ollama list` before triggering a redundant installer. Do not automatically reinstall a functioning Ollama solely because it was missing from the inherited PATH.
3. Give silent installer a bounded timeout, useful logging/progress and a safe error/recovery path. Do not kill processes indiscriminately. Check whether Windows installer flags are appropriate. Never tell the user to disable Windows security.
4. Test scripted success, Ollama already installed/not on PATH, installer fails or stalls, daemon unavailable, model installed/missing, and clean install paths. Avoid reinstalling multi-GB model unnecessarily. Make Windows PowerShell 5.1 behavior explicit.
5. Resume installation from the user's state and verify Piper speech setup, Whisper microphone recognition, the local voice-service health check and WAV response, and the full `jarvis chat --voice` loop. Ensure a simple repeatable launch command/shortcut and document recoveries.
6. Run and report available automated tests and static validation; distinguish code-tested from actions that require testing on the user's Windows PC. Do not claim the local installation is complete until actually verified.
7. Make a focused patch/PR and short user-facing steps. Avoid introducing paid services, new unrelated features, or needlessly asking the user to re-explain the project. Only request the minimum physical-device input needed (e.g., the two outstanding commands, microphone access/voice test).

## First actions for local diagnosis

Run these in a **new** Command Prompt, keeping the existing Jarvis installer window open initially:

```bat
where ollama
tasklist /FI "IMAGENAME eq OllamaSetup.exe"
ollama list
```

Also inspect the effective PATH and, if necessary, the executable under `%LOCALAPPDATA%\Programs\Ollama\ollama.exe`. Treat any output as diagnostic evidence, not as automatic permission to terminate, uninstall or overwrite anything.

## Constraints

- Continue **this Jarvis AI project**; prior unrelated suggestions about Cuenora/college are not its scope.
- Free/local-first, reliable, British spoken voice; avoid paid API dependencies.
- Protect and preserve the original Jarvis installation. Keep new offline installation isolated and existing models intact.
- The user prefers that Codex do the engineering, test assumptions and take the project as far as possible without repeated manual instructions.
- This file is a **handover**, not proof that a fix, installer, tests or full voice assistant are already complete.
