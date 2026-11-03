# Generate the synthetic test streams for the spike 01 test matrix (see README.md "Make test streams").
# Output: spikes\01-decode\streams\*.h265 (gitignored). Needs ffmpeg with libx265 on PATH.
# 8K x265 encodes are slow (minutes each); run and go do something else:
#   powershell -File spikes\01-decode\make-streams.ps1
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'streams'
New-Item -ItemType Directory -Force $out | Out-Null
Set-Location $out

function Encode($name, $ffargs) {
    if (Test-Path $name) { Write-Host "skip  $name (exists)"; return }
    $t = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "start $name"
    & ffmpeg -hide_banner -loglevel error -y @ffargs $name
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for $name" }
    Write-Host ("done  {0}  {1:N1} MB  {2:N0}s" -f $name, ((Get-Item $name).Length / 1MB), $t.Elapsed.TotalSeconds)
}

$noise = 'noise=alls=12:allf=t'
$x265 = 'keyint=120:bframes=3:aud=1'

Encode 'hevc8_3840x2160_60.h265' @('-f','lavfi','-i','testsrc2=size=3840x2160:rate=60','-t','10','-vf',$noise,
    '-c:v','libx265','-preset','superfast','-pix_fmt','yuv420p','-b:v','60M','-maxrate','80M','-bufsize','160M','-x265-params',$x265)

Encode 'hevc8_7680x3840_60.h265' @('-f','lavfi','-i','testsrc2=size=7680x3840:rate=60','-t','10','-vf',$noise,
    '-c:v','libx265','-preset','superfast','-pix_fmt','yuv420p','-b:v','120M','-maxrate','150M','-bufsize','300M','-x265-params',$x265)

Encode 'hevc8_8192x4096_60.h265' @('-f','lavfi','-i','testsrc2=size=8192x4096:rate=60','-t','10','-vf',$noise,
    '-c:v','libx265','-preset','superfast','-pix_fmt','yuv420p','-b:v','120M','-maxrate','150M','-bufsize','300M','-x265-params',$x265)

Encode 'hevc10_7680x3840_60.h265' @('-f','lavfi','-i','testsrc2=size=7680x3840:rate=60','-t','10','-vf',$noise,
    '-c:v','libx265','-preset','superfast','-pix_fmt','yuv420p10le','-profile:v','main10','-b:v','120M','-maxrate','150M','-bufsize','300M','-x265-params',$x265)

Encode 'a_1080.h265' @('-f','lavfi','-i','testsrc2=size=1920x1080:rate=60','-t','3','-c:v','libx265','-preset','superfast','-x265-params','aud=1')
Encode 'b_2160.h265' @('-f','lavfi','-i','testsrc2=size=3840x2160:rate=60','-t','3','-c:v','libx265','-preset','superfast','-x265-params','aud=1')
if (-not (Test-Path 'reschange.h265')) {
    cmd /c 'copy /b a_1080.h265 + b_2160.h265 reschange.h265 >nul'
    Write-Host "done  reschange.h265"
}

Write-Host "--- streams ---"
Get-ChildItem *.h265 | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}} | Format-Table -AutoSize
