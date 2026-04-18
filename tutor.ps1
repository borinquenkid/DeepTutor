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
    
    # ── PHASE 1: THE BRAIN ───────────────────────────────────────────
    Write-Host "`nStep 1: Configure The Brain (LLM)" -ForegroundColor White -Style Bold
    Write-Host "Choose your AI provider for reasoning and chat:"
    Write-Host "  1) Gemini (Recommended)" -ForegroundColor Green
    Write-Host "  2) OpenAI" -ForegroundColor Blue
    Write-Host "  3) Anthropic" -ForegroundColor Yellow
    Write-Host "  4) DeepSeek"
    Write-Host "  5) Groq"
    Write-Host "  6) Ollama (Local)`n"
    
    $b_choice = Read-Host "Selection"
    
    $b_binding = ""; $b_host = ""; $b_key_url = ""; $b_env = ""

    switch ($b_choice) {
        "1" { $b_binding = "gemini"; $b_host = "https://generativelanguage.googleapis.com/v1beta/openai/"; $b_key_url = "https://aistudio.google.com/app/apikey"; $b_env = "GEMINI_API_KEY" }
        "2" { $b_binding = "openai"; $b_host = "https://api.openai.com/v1"; $b_key_url = "https://platform.openai.com/api-keys"; $b_env = "OPENAI_API_KEY" }
        "3" { $b_binding = "anthropic"; $b_host = "https://api.anthropic.com/v1"; $b_key_url = "https://console.anthropic.com/settings/keys"; $b_env = "ANTHROPIC_API_KEY" }
        "4" { $b_binding = "deepseek"; $b_host = "https://api.deepseek.com"; $b_key_url = "https://platform.deepseek.com/api_keys"; $b_env = "DEEPSEEK_API_KEY" }
        "5" { $b_binding = "groq"; $b_host = "https://api.groq.com/openai/v1"; $b_key_url = "https://console.groq.com/keys"; $b_env = "GROQ_API_KEY" }
        "6" { $b_binding = "ollama"; $b_host = "http://localhost:11434/v1"; $b_env = "" }
        Default { Write-Host "Skipping Brain setup..." }
    }

    if ($b_binding -ne "") {
        $b_key = "ollama"
        if ($b_binding -ne "ollama") {
            Write-Host "Get your key at: $b_key_url" -ForegroundColor Blue
            $b_key = Read-Host "Paste your Brain API Key"
        }
    }

    # ── PHASE 2: THE LIBRARIAN ───────────────────────────────────────
    Write-Host "`nStep 2: Configure The Librarian (Embedding)" -ForegroundColor White -Style Bold
    Write-Host "Choose your AI provider for reading documents:"
    Write-Host "  1) Same as The Brain" -Style Bold
    Write-Host "  2) Gemini"
    Write-Host "  3) OpenAI"
    Write-Host "  4) Cohere"
    Write-Host "  5) Ollama (Local)`n"
    
    $l_choice = Read-Host "Selection"
    $default_dim = if ($b_binding -eq "gemini") { "768" } else { "3072" }

    $l_binding = ""; $l_host = ""; $l_key = ""; $l_dim = ""

    switch ($l_choice) {
        "1" { $l_binding = $b_binding; $l_host = $b_host; $l_key = $b_key; $l_dim = $default_dim }
        "2" { $l_binding = "gemini"; $l_host = "https://generativelanguage.googleapis.com/v1beta/openai/"; $l_dim = "768" }
        "3" { $l_binding = "openai"; $l_host = "https://api.openai.com/v1"; $l_dim = "3072" }
        "4" { $l_binding = "cohere"; $l_host = "https://api.cohere.ai"; $l_dim = "1024" }
        "5" { $l_binding = "ollama"; $l_host = "http://localhost:11434"; $l_dim = "768"; $l_key = "ollama" }
        Default { Write-Host "Skipping Librarian setup..." }
    }

    if ($l_binding -ne "" -and $l_choice -ne "1" -and $l_binding -ne "ollama") {
        $l_key = Read-Host "Paste your Librarian API Key"
    }

    # ── PHASE 3: THE EXPLORER ────────────────────────────────────────
    Write-Host "`nStep 3: Configure The Explorer (Web Search)" -ForegroundColor White -Style Bold
    Write-Host "Optional: choose a web search provider:"
    Write-Host "  1) Brave Search" -ForegroundColor Blue
    Write-Host "  2) Tavily" -ForegroundColor Yellow
    Write-Host "  3) Perplexity"
    Write-Host "  s) Skip`n"
    
    $e_choice = Read-Host "Selection"
    $e_prov = ""; $e_url = ""; $e_key = ""

    switch ($e_choice) {
        "1" { $e_prov = "brave"; $e_url = "https://api.search.brave.com/app/dashboard" }
        "2" { $e_prov = "tavily"; $e_url = "https://tavily.com/dashboard" }
        "3" { $e_prov = "perplexity"; $e_url = "https://www.perplexity.ai/settings/api" }
    }

    if ($e_prov -ne "") {
        Write-Host "Get your key at: $e_url" -ForegroundColor Blue
        $e_key = Read-Host "Paste your Explorer API Key"
    }

    # ── SAVE TO .ENV ────────────────────────────────────────────────
    if (-not (Test-Path ".env")) { New-Item -Path ".env" -ItemType File }
    $temp_env = Get-Content ".env" | Where-Object { $_ -notmatch "^(LLM_|EMBEDDING_|SEARCH_|$b_env)=" }
    $temp_env | Set-Content ".env"

    if ($b_binding -ne "") {
        Add-Content -Path ".env" -Value "LLM_BINDING=$b_binding"
        Add-Content -Path ".env" -Value "LLM_HOST=$b_host"
        Add-Content -Path ".env" -Value "LLM_API_KEY=$b_key"
        if ($b_env -ne "") { Add-Content -Path ".env" -Value "$b_env=$b_key" }
    }
    if ($l_binding -ne "") {
        Add-Content -Path ".env" -Value "EMBEDDING_BINDING=$l_binding"
        Add-Content -Path ".env" -Value "EMBEDDING_HOST=$l_host"
        Add-Content -Path ".env" -Value "EMBEDDING_API_KEY=$l_key"
        Add-Content -Path ".env" -Value "EMBEDDING_DIMENSION=$l_dim"
    }
    if ($e_prov -ne "") {
        Add-Content -Path ".env" -Value "SEARCH_PROVIDER=$e_prov"
        Add-Content -Path ".env" -Value "SEARCH_API_KEY=$e_key"
    }

    Log-Success "Configuration saved to .env"
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
