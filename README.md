# dsh-plugin-chatgpt-crash-fix

> A DSH plugin that diagnoses and fixes ChatGPT / Codex desktop app (Windows Store package `OpenAI.Codex`) **crashes ~60-90s after launch**: crash-dump triage → Microsoft Store channel check → proxy-interference fix. Fully reproducible and rollback-safe.

English · [中文](README.zh.md)

## Problem

The ChatGPT desktop app on Windows opens fine, then the **whole process tree exits after ~60-90 seconds** with no system error dialog. The app log shows `[windows-store-updater] Checking Windows Store for package updates` right before it dies. Often triggered after an **interrupted Windows update** or after enabling a **Clash-style system proxy**.

## Root cause (verified via crash dumps)

```
Clash-style software sets a system proxy (e.g. 127.0.0.1:7897)
  └─ proxy fails to forward Microsoft update domains (direct works, via-proxy fails)
       └─ Windows Update / Microsoft Store channel breaks (0x80072EFD)
            └─ the app's Store-updater native module windows-updater.node crashes (0xC0000005)
                 └─ the whole app exits
```

## Fix (best of both worlds)

Keep the proxy on (OpenAI traffic stays proxied — avoids account-ban risk), and add **Microsoft domains to the proxy bypass list** so Store/Update go direct. The channel recovers, the app updates to a fixed build and stops crashing.

## Contents

| Item | Description |
| --- | --- |
| `skills/chatgpt-crash-fix/SKILL.md` | Playbook that teaches any DSH agent the diagnose → fix → verify flow |
| `scripts/diagnose-chatgpt-crash.ps1` | One-shot read-only diagnosis: app state, crash dumps, Store channel, proxy |
| `scripts/check-store-channel.ps1` | Store / Windows Update channel check (read-only) |
| `scripts/check-proxy-config.ps1` | Proxy + bypass-list check (read-only) |
| `scripts/fix-proxy-bypass.ps1` | One-command fix: backup → add MS bypass → verify (with `-Restore`) |
| `lib/index.js` | Cordis plugin registering the `/chatgpt-crash-fix` command |

## Install

```bash
# As a DSH plugin
dsh plugin add dsh-plugin-chatgpt-crash-fix

# Or just clone for the scripts + skill
git clone https://github.com/lammarco86/dsh-plugin-chatgpt-crash-fix.git
```

## Usage

```powershell
# 1) Diagnose (read-only)
powershell -ExecutionPolicy Bypass -File scripts\diagnose-chatgpt-crash.ps1

# 2) If it reports "WU failed + proxy on + no MS bypass", fix
powershell -ExecutionPolicy Bypass -File scripts\fix-proxy-bypass.ps1 -ProxyServer "127.0.0.1:7897"

# 3) Rollback
powershell -ExecutionPolicy Bypass -File scripts\fix-proxy-bypass.ps1 -Restore
```

## Verified outcome

- Crash dump triage pinpointed the faulting module: `...\resources\native\windows-updater.node` (0xC0000005).
- After adding the MS bypass list: WU scan recovered, the app updated via the Store (26.818.2441.0 → 26.818.5229.0), it stays running, and the updater log shows `overallState=NoUpdates`.
- Proxy kept on; OpenAI authentication works through it.

## Disclaimer

Not affiliated with OpenAI, Anywhere Labs, or DeepSeek. No security endorsement. Scripts only touch user proxy settings and always back up first; review before running. Never publish crash dumps, `auth.json`, or proxy subscriptions with this repo.

## License

[MIT](LICENSE)
