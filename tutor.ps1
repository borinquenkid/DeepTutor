# DeepTutor — Zero-friction entry point for Windows

$VENV_DIR = ".venv"
$MIN_PYTHON = "3.11"

function Log-Info($msg) { Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Log-Success($msg) { Write-Host "✅ $msg" -ForegroundColor Green }
function Log-Warn($msg) { Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Log-Error($msg) { Write-Host "❌ $msg" -ForegroundColor Red }

# 1. Check Git
function Check-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Log-Warn "Git is not installed."
        Log-Info "Attempting to install Git via winget..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Git.Git -e --source winget --silent
        } else {
            Log-Error "winget not found. Please install Git manually from https://git-scm.com"
        }
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        if (-not (Test-Path ".git")) {
            Log-Info "Initializing git repository..."
            & git init -q
            & git remote add origin https://github.com/HKUDS/DeepTutor.git
            & git fetch origin -q
            & git checkout -b main origin/main -q
            Log-Success "Git initialized and linked to origin."
        } else {
            # Check for updates (best effort, don't hang)
            Log-Info "Checking for updates..."
            try {
                # Fetch updates in the background or quickly
                & git fetch origin -q
                
                $local = & git rev-parse @
                $upstream = & git rev-parse @{u}
                $base = & git merge-base @ @{u}

                if ($local -eq $upstream) {
                    Log-Success "DeepTutor is up to date."
                } elseif ($local -eq $base) {
                    Log-Warn "Updates are available!"
                    Write-Host "  Run 'git pull' to update to the latest version."
                }
            } catch {
                Log-Warn "Could not check for updates (is the network up?)"
            }
        }
    } else {
        Log-Warn "Git check failed. Some functionality might be missing."
    }
}

Check-Git

# 2. Find Python
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
    Log-Warn "Python $MIN_PYTHON+ not found."
    Log-Info "Attempting to install Python 3.11 via winget..."
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id Python.Python.3.11 -e --source winget --silent
        
        # Refresh session PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Re-check
        foreach ($cmd in @("python", "python3", "py")) {
            try {
                $ver = & $cmd -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>$null
                if ($null -ne $ver -and [version]$ver -ge [version]$MIN_PYTHON) {
                    $PYTHON_CMD = $cmd
                    break
                }
            } catch {}
        }
    } else {
        Log-Error "winget not found. Please install Python 3.11 manually from https://python.org"
        exit 1
    }
}

if ($null -eq $PYTHON_CMD) {
    Log-Error "Failed to automatically install Python $MIN_PYTHON+."
    Log-Info "Please install it from https://python.org"
    exit 1
}

# 2. Virtual Environment
if (-not (Test-Path $VENV_DIR)) {
    Log-Info "Creating virtual environment in $VENV_DIR..."
    & $PYTHON_CMD -m venv $VENV_DIR
    Log-Success "Environment created."

    $INT_PYTHON = Join-Path $VENV_DIR "Scripts\python.exe"
    if (-not (Test-Path $INT_PYTHON)) { $INT_PYTHON = Join-Path $VENV_DIR "bin\python.exe" }

    Log-Info "Installing dependencies (this may take a few minutes)..."
    & $INT_PYTHON -m pip install --upgrade pip -q
    & $INT_PYTHON -m pip install -r requirements.txt -q
    & $INT_PYTHON -m pip install -e . -q
    Log-Success "Dependencies installed."
}

# 3. Resolve internal Python
$PYTHON_EXE = Join-Path $VENV_DIR "Scripts\python.exe"
if (-not (Test-Path $PYTHON_EXE)) {
    # Fallback for some venv layouts
    $PYTHON_EXE = Join-Path $VENV_DIR "bin\python.exe"
}

# 4. Launch the Setup Tour
& $PYTHON_EXE scripts\start_tour.py $args
