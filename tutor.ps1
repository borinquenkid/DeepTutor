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

# 4. Interactive Configuration
# If .env doesn't exist or doesn't have a non-empty LLM_API_KEY, ask for it
$trigger_setup = $false
if (-not (Test-Path ".env")) {
    $trigger_setup = $true
} else {
    $env_content = Get-Content ".env"
    if (-not ($env_content | Select-String -Pattern "LLM_API_KEY=.+")) {
        $trigger_setup = $true
    }
}

if ($trigger_setup) {
    Write-Host "`n🔑 DeepTutor Setup" -ForegroundColor White -Style Bold
    Write-Host "Choose your AI provider to get started:"
    Write-Host "  1) Gemini (Recommended - Free & Fast)" -ForegroundColor Green
    Write-Host "  2) OpenAI (GPT-4o, etc.)" -ForegroundColor Blue
    Write-Host "  3) Anthropic (Claude 3.5)" -ForegroundColor Yellow
    Write-Host "  4) DeepSeek"
    Write-Host "  5) Groq (Ultra-fast)"
    Write-Host "  6) Ollama (Local - No API Key needed)"
    Write-Host "  s) Skip for now`n"
    
    $choice = Read-Host "Selection"
    
    $binding = ""
    $host_url = ""
    $key_url = ""
    $env_key = ""

    switch ($choice) {
        "1" {
            $binding = "gemini"
            $host_url = "https://generativelanguage.googleapis.com/v1beta/openai/"
            $key_url = "https://aistudio.google.com/app/apikey"
            $env_key = "GEMINI_API_KEY"
        }
        "2" {
            $binding = "openai"
            $host_url = "https://api.openai.com/v1"
            $key_url = "https://platform.openai.com/api-keys"
            $env_key = "OPENAI_API_KEY"
        }
        "3" {
            $binding = "anthropic"
            $host_url = "https://api.anthropic.com/v1"
            $key_url = "https://console.anthropic.com/settings/keys"
            $env_key = "ANTHROPIC_API_KEY"
        }
        "4" {
            $binding = "deepseek"
            $host_url = "https://api.deepseek.com"
            $key_url = "https://platform.deepseek.com/api_keys"
            $env_key = "DEEPSEEK_API_KEY"
        }
        "5" {
            $binding = "groq"
            $host_url = "https://api.groq.com/openai/v1"
            $key_url = "https://console.groq.com/keys"
            $env_key = "GROQ_API_KEY"
        }
        "6" {
            $binding = "ollama"
            $host_url = "http://localhost:11434/v1"
        }
        Default {
            Write-Host "Skipping interactive config..."
        }
    }

    if ($binding -ne "") {
        if (-not (Test-Path ".env")) { New-Item -Path ".env" -ItemType File }
        
        # Clean up existing keys to avoid duplicates
        $temp_env = Get-Content ".env" | Where-Object { $_ -notmatch "^(LLM_BINDING|LLM_HOST|LLM_API_KEY|$env_key)=" }
        $temp_env | Set-Content ".env"

        Add-Content -Path ".env" -Value "LLM_BINDING=$binding"
        Add-Content -Path ".env" -Value "LLM_HOST=$host_url"
        Add-Content -Path ".env" -Value "EMBEDDING_BINDING=$binding"
        Add-Content -Path ".env" -Value "EMBEDDING_HOST=$host_url"
        
        if ($binding -ne "ollama") {
            Write-Host "`nYou can get your API Key at: $key_url" -ForegroundColor Blue
            $api_key = Read-Host "Paste your API Key"
            if ($api_key -ne "") {
                Add-Content -Path ".env" -Value "LLM_API_KEY=$api_key"
                Add-Content -Path ".env" -Value "EMBEDDING_API_KEY=$api_key"
                Add-Content -Path ".env" -Value "$env_key=$api_key"
                Log-Success "Configuration saved to .env (The Brain and Librarian are ready!)"
            }
        } else {
            Add-Content -Path ".env" -Value "LLM_API_KEY=ollama"
            Add-Content -Path ".env" -Value "EMBEDDING_API_KEY=ollama"
            Log-Success "Ollama configuration saved to .env (ensure Ollama is running)"
        }
    }
    Write-Host ""
}

# 5. Clear Port Conflicts
# Ensure ports 8001 and 3782 are free to avoid "Address already in use" crashes
function Clear-Port($port) {
    $pid = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
    if ($null -ne $pid) {
        Log-Warn "Port $port is in use by PID $pid. Clearing..."
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    }
}

Clear-Port 8001
Clear-Port 3782

# 6. Launch the Setup Tour
& $PYTHON_EXE scripts\start_tour.py $args
