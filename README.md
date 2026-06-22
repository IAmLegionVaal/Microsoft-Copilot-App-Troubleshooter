# Microsoft Copilot App Troubleshooter

PowerShell 5.1 diagnostics and guarded repair tooling created by **Dewald Pretorius**.

## Files

- `Troubleshooter.ps1` — collects Copilot installation, process and endpoint evidence.
- `Repair.ps1` — performs reversible local repair actions with logs, confirmation and verification.
- `Launch_Copilot_Repair.bat` — interactive repair menu for technicians.

## Repair actions

### `Diagnose`

Collects read-only evidence for:

- Installed Copilot AppX/MSIX packages
- Repairable application packages versus provider/runtime packages
- Copilot cache locations
- Copilot and WebView2 process state
- Microsoft Edge WebView2 Runtime detection
- Start menu application registration
- Copilot and Microsoft sign-in endpoint connectivity

### `RepairAllSafe`

Runs the standard repair sequence:

1. Stops Copilot-related processes.
2. Moves recognised Copilot cache folders into a timestamped backup.
3. Flushes the Windows DNS resolver cache.
4. Re-registers the Copilot application package.
5. Restarts Copilot.

### `RestartApp`

Stops only Copilot and Copilot-owned WebView2 processes, then starts the Copilot application again. If no local Start menu application is registered, the tool opens the Copilot web application.

### `ResetCache`

Backs up and rebuilds recognised Copilot local cache locations, including:

- `LocalCache`
- `TempState`
- Copilot WebView2 data
- Package internet cache

Cache data is moved rather than deleted.

### `ResetAppPackage`

Uses `Reset-AppxPackage` when available to reset the installed user-facing Copilot application package. Provider, framework and runtime packages are deliberately excluded.

This action can clear local application data and should be used after the cache and re-registration repairs have failed.

If `Reset-AppxPackage` is unavailable on the Windows build, the script falls back to package re-registration.

### `ReregisterAppPackage`

Re-registers the installed Copilot application from its existing `AppxManifest.xml`. This can repair broken Start menu registration, package metadata and application launch failures without uninstalling the package.

### `FlushDns`

Clears the Windows DNS resolver cache.

## Usage

Read-only diagnosis:

```powershell
.\Repair.ps1 -Action Diagnose
```

Preview the complete repair workflow:

```powershell
.\Repair.ps1 -Action RepairAllSafe -WhatIf
```

Run the standard repairs:

```powershell
.\Repair.ps1 -Action RepairAllSafe
```

Run individual repairs:

```powershell
.\Repair.ps1 -Action RestartApp
.\Repair.ps1 -Action ResetCache
.\Repair.ps1 -Action ReregisterAppPackage
.\Repair.ps1 -Action ResetAppPackage -Confirm
.\Repair.ps1 -Action FlushDns
```

For an interactive menu, double-click:

```text
Launch_Copilot_Repair.bat
```

## Logs and backups

Each run writes to:

```text
Desktop\Copilot_Repair
```

The output includes:

- Before-repair JSON snapshot
- After-repair JSON snapshot
- Timestamped repair log
- Timestamped cache backups

## Safety

- All mutating actions use PowerShell `ShouldProcess` and support `-WhatIf`.
- Recognised cache folders are moved into backups instead of being deleted.
- Copilot-owned WebView2 processes are targeted; unrelated WebView2 processes are not intentionally stopped.
- Provider, framework and runtime packages are excluded from package reset and re-registration.
- Package reset is higher impact because it can clear local application data.
- The script does not uninstall Copilot or remove the user's Microsoft account.

## Validation status

Tested successfully by the author on his own Windows machines. The documented Copilot diagnostic and repair workflows worked as intended on those systems.

Results may vary with the Windows and Copilot version, WebView2 runtime, installed package, user profile, permissions, account configuration and network environment. Use `-WhatIf` when testing the toolkit on a new machine or software version.
