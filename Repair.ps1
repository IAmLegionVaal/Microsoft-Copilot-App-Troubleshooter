#requires -Version 5.1
<# Created by Dewald Pretorius. #>
[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Diagnose','FlushDns')][string]$Action='Diagnose',[string]$OutputPath=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'Copilot_Repair'))
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutputPath -Force|Out-Null
$report=Join-Path $OutputPath ('Report_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.json')
$state=[ordered]@{Action=$Action;CopilotEndpoint=(Test-NetConnection 'copilot.microsoft.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue);SignInEndpoint=(Test-NetConnection 'login.microsoftonline.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)}
$state|ConvertTo-Json|Set-Content -LiteralPath $report -Encoding UTF8
if($Action -eq 'FlushDns' -and $PSCmdlet.ShouldProcess('Windows DNS client cache','Clear')){Clear-DnsClientCache}
Write-Host "Completed. Report: $report"
