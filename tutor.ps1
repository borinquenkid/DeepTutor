# DeepTutor — Zero-friction entry point for Windows

$VENV_DIR = ".venv"
$MIN_PYTHON = "3.11"

function Log-Info($msg) { Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Log-Success($msg) { Write-Host "✅ $msg" -ForegroundColor Green }
function Log-Warn($msg) { Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Log-Error($msg) { Write-Host "❌ $msg" -ForegroundColor Red }

# 1. Find Python
$PYTHON_CMD = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $ver = & $cmd -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>$null
        if ($null -ne $ver -and [version]$ver -ge [version]$MIN_PYTHON) {
            $PYTHON_CMD = $cmd
            break
        }
    } catch {}
}

if ($null -eq $PYTHON_CMD) {
    Log-Error "DeepTutor requires Python $MIN_PYTHON+."
    Log-Info "Please install it from https://python.org"
    exit 1
}

# 2. Virtual Environment
if (-not (Test-Path $VENV_DIR)) {
    Log-Info "Creating virtual environment in $VENV_DIR..."
    & $PYTHON_CMD -m venv $VENV_DIR
    Log-Success "Environment created."
}

# 3. Resolve internal Python
$PYTHON_EXE = Join-Path $VENV_DIR "Scripts\python.exe"
if (-not (Test-Path $PYTHON_EXE)) {
    # Fallback for some venv layouts
    $PYTHON_EXE = Join-Path $VENV_DIR "bin\python.exe"
}

# 4. Launch the Setup Tour
& $PYTHON_EXE scripts\start_tour.py $args
