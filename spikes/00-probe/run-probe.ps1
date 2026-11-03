# Copy the probe to the Frame, run it, save the output under results/.
#   powershell -File spikes\00-probe\run-probe.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$out = Join-Path $here "results\probe-$stamp.txt"

ssh -o BatchMode=yes -o ConnectTimeout=5 frame 'echo up' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "frame not reachable" }

ssh frame 'rm -rf /tmp/probe && mkdir -p /tmp/probe'
scp -q (Join-Path $here 'probe.sh') (Join-Path $here 'v4l2_enum.py') 'frame:/tmp/probe/'
ssh frame 'bash /tmp/probe/probe.sh' | Out-File -Encoding utf8 $out
Write-Host "saved $out ($((Get-Content $out).Count) lines)"
