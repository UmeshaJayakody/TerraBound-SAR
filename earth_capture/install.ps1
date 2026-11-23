# Sets up Earth Capture on Windows: a Python environment in earth_capture\.venv with everything it
# needs, then a check of MATLAB, Blender and the open-data servers.
#
#   powershell -ExecutionPolicy Bypass -File earth_capture\install.ps1
#
# Needs Python 3.10 or later (3.11 recommended) from python.org, and MATLAB (any recent release;
# no toolboxes). Blender is optional.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$venv = Join-Path $here '.venv'

function Find-Python {
    foreach ($v in '3.11', '3.12', '3.13', '3.10') {
        try { & py "-$v" -c "import sys" 2>$null; if ($LASTEXITCODE -eq 0) { return @('py', "-$v") } } catch {}
    }
    $p = Get-Command python -ErrorAction SilentlyContinue
    if ($p) { return @($p.Source) }
    throw 'Python 3.10 or later was not found. Install it from https://www.python.org/downloads/ and run this again.'
}

if (-not (Test-Path (Join-Path $venv 'Scripts\python.exe'))) {
    $py = Find-Python
    Write-Host "Creating the Python environment with $($py -join ' ') ..."
    if ($py.Count -gt 1) { & $py[0] $py[1] -m venv $venv } else { & $py[0] -m venv $venv }
}
$python = Join-Path $venv 'Scripts\python.exe'
Write-Host 'Installing the packages (a few minutes the first time) ...'
& $python -m pip install --upgrade pip --quiet
& $python -m pip install -r (Join-Path $here 'requirements.txt') --quiet
if ($LASTEXITCODE -ne 0) { throw 'Installing the packages failed; see the messages above.' }

Write-Host ''
Push-Location $here
try { & $python -m terrabound_earth doctor } finally { Pop-Location }
Write-Host ''
Write-Host 'Done. Start the app with:'
Write-Host "  $python -m terrabound_earth        (from the earth_capture folder)"
Write-Host 'or double-click earth_capture\Earth Capture.bat'
