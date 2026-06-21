# Microsoft Copilot App Troubleshooter

PowerShell 5.1 diagnostics and guarded connectivity repair tooling created by **Dewald Pretorius**.

`Troubleshooter.ps1` collects the original Copilot evidence. `Repair.ps1` provides a read-only `Diagnose` action and a `FlushDns` repair action protected by PowerShell `ShouldProcess` confirmation.

```powershell
.\Troubleshooter.ps1
.\Repair.ps1 -Action Diagnose
.\Repair.ps1 -Action FlushDns -WhatIf
.\Repair.ps1 -Action FlushDns -Confirm
```

Each run writes a timestamped JSON report of Copilot and Microsoft sign-in endpoint reachability. The workflow is source-reviewed for Windows PowerShell 5.1 but has not been runtime-tested against every Copilot client or tenant configuration.
