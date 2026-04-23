# DeepTutor — Zero-friction entry point for Windows

$VENV_DIR = ".venv"
$MIN_PYTHON = "3.11"

function Log-Info($msg) { Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Log-Success($msg) { Write-Host "✅ $msg" -ForegroundColor Green }
function Log-Warn($msg) { Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Log-Error($msg) { Write-Host "❌ $msg" -ForegroundColor Red }

# Frictionless Ollama Setup for Windows
function Ensure-Ollama {
    Write-Host "🔍 Checking Librarian (Ollama)..." -ForegroundColor Cyan
    
    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Log-Warn "Ollama not found. Attempting frictionless install..."
        Log-Info "Downloading Ollama for Windows..."
        # Winget is preferred on modern Windows
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install Ollama.Ollama
        } else {
            Log-Error "Please install Ollama from https://ollama.com manually."
            return
        }
    }

    # Check if running
    try {
        Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -ErrorAction Stop > $null
    } catch {
        Log-Info "Ollama is not running. Starting it..."
        Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 5
    }

    # Ensure model exists
    $models = ollama list
    if (-not ($models -match "nomic-embed-text")) {
        Log-Info "Pulling Librarian model (nomic-embed-text)..."
        ollama pull nomic-embed-text
    }
    Log-Success "Librarian is ready."
}

# 1. Environment Check
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log-Warn "Git not found. Installing via winget..."
    winget install Git.Git
}

# 2. Find Python
$PYTHON_EXE = ""
foreach ($cmd in "python.exe", "python3.exe", "py.exe") {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $ver = & $cmd -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
        if ([version]$ver -ge [version]$MIN_PYTHON) {
            $PYTHON_EXE = (Get-Command $cmd).Source
            break
        }
    }
}

if ($PYTHON_EXE -eq "") {
    Log-Warn "Python $MIN_PYTHON+ not found. Installing via winget..."
    winget install Python.Python.3.11
    $PYTHON_EXE = "python.exe"
}

# 3. Virtual Environment
if (-not (Test-Path $VENV_DIR)) {
    Log-Info "Creating virtual environment..."
    & $PYTHON_EXE -m venv $VENV_DIR
    Log-Success "Environment created."
    
    $INTERNAL_PYTHON = "$VENV_DIR\Scripts\python.exe"
    Log-Info "Installing dependencies..."
    & $INTERNAL_PYTHON -m pip install --upgrade pip -q
    & $INTERNAL_PYTHON -m pip install -r requirements.txt -q
    & $INTERNAL_PYTHON -m pip install -e . -q
    Log-Success "Dependencies installed."
}

$PYTHON_EXE = "$VENV_DIR\Scripts\python.exe"

# 4. Interactive Configuration
$trigger_setup = $false
if (-not (Test-Path ".env")) {
    $trigger_setup = $true
} else {
    $env_content = Get-Content ".env"
    if (-not ($env_content | Select-String -Pattern "LLM_API_KEY=.+") -or -not (Test-Path "data/user/settings/model_catalog.json")) {
        $trigger_setup = $true
    }
}

if ($args -contains "--setup") { $trigger_setup = $true }

# If already configured, ask if they want to reconfigure
if (-not $trigger_setup) {
    Write-Host "`n🚀 DeepTutor is ready!" -ForegroundColor Cyan
    Write-Host "  - Press Enter to start."
    Write-Host "  - Type 'r' and Enter to reconfigure/reset settings." -ForegroundColor Yellow
    $ready_choice = Read-Host "Choice"
    if ($ready_choice -eq "r" -or $ready_choice -eq "R") {
        $trigger_setup = $true
    }
}

if ($trigger_setup) {
    Write-Host "`n🔑 DeepTutor Setup" -ForegroundColor White
    
    # PHASE 1: BRAIN
    Write-Host "`nStep 1: Configure The Brain (LLM)" -ForegroundColor White
    Write-Host "Choose your AI provider:"
    Write-Host "  1) Gemini"
    Write-Host "  2) OpenAI"
    Write-Host "  3) Anthropic"
    Write-Host "  4) DeepSeek"
    Write-Host "  5) Groq (Fast & Free)" -ForegroundColor Green
    Write-Host "  6) NVIDIA NIM (Free Cloud API - 80+ Models)" -ForegroundColor Green
    Write-Host "  7) Ollama (Local)"
    
    $b_choice = Read-Host "Selection"
    $b_binding = ""; $b_host = ""; $b_key_url = ""; $b_env = ""; $b_model = ""

    switch ($b_choice) {
        "1" { $b_binding = "gemini"; $b_host = "https://generativelanguage.googleapis.com/v1beta/openai/"; $b_key_url = "https://aistudio.google.com/app/apikey"; $b_env = "GEMINI_API_KEY"; $b_model = "gemini-1.5-flash" }
        "2" { $b_binding = "openai"; $b_host = "https://api.openai.com/v1"; $b_key_url = "https://platform.openai.com/api-keys"; $b_env = "OPENAI_API_KEY"; $b_model = "gpt-4o-mini" }
        "3" { $b_binding = "anthropic"; $b_host = "https://api.anthropic.com/v1"; $b_key_url = "https://console.anthropic.com/settings/keys"; $b_env = "ANTHROPIC_API_KEY"; $b_model = "claude-3-5-sonnet-latest" }
        "4" { $b_binding = "deepseek"; $b_host = "https://api.deepseek.com"; $b_key_url = "https://platform.deepseek.com/api_keys"; $b_env = "DEEPSEEK_API_KEY"; $b_model = "deepseek-chat" }
        "5" { $b_binding = "groq"; $b_host = "https://api.groq.com/openai/v1"; $b_key_url = "https://console.groq.com/keys"; $b_env = "GROQ_API_KEY"; $b_model = "llama-3.3-70b-versatile" }
        "6" { 
            $b_binding = "nvidia"; $b_host = "https://integrate.api.nvidia.com/v1"; $b_key_url = "https://build.nvidia.com/models"; $b_env = "NVIDIA_API_KEY"
            Write-Host "`nChoose model grade: 1) Standard (Llama-70B) 2) Power (Llama-405B) 3) DeepSeek-V3"
            $m_grade = Read-Host "Selection [1]"
            if ($m_grade -eq "2") { $b_model = "meta/llama-3.1-405b-instruct" } elseif ($m_grade -eq "3") { $b_model = "deepseek-ai/deepseek-v3.2" } else { $b_model = "meta/llama-3.1-70b-instruct" }
        }
        "7" { $b_binding = "ollama"; $b_host = "http://localhost:11434/v1"; $b_model = "llama3.2" }
    }

    if ($b_binding -ne "") {
        if ($b_binding -ne "ollama") {
            Write-Host "`n🔑 Get your key at: $b_key_url" -ForegroundColor Blue
            try { Start-Process $b_key_url } catch {}
            $b_key = Read-Host "Paste your Brain API Key"
            while (-not $b_key) { $b_key = Read-Host "A key is required. Paste your Brain API Key" }
        } else { $b_key = "ollama" }

        # PHASE 2: LIBRARIAN
        Write-Host "`nStep 2: Configure The Librarian (Embedding)" -ForegroundColor White
        if ($b_binding -eq "groq" -or $b_binding -eq "deepseek") {
            Write-Host "  Note: $b_binding lacks embeddings. Recommended: Option 7 (Ollama)." -ForegroundColor Yellow
        }
        Write-Host "  1) Same as Brain (if supported)"
        Write-Host "  2) Gemini"
        Write-Host "  3) OpenAI"
        Write-Host "  7) Ollama (Local & Free)" -ForegroundColor Green
        Write-Host "  8) NVIDIA NIM"
        
        $l_choice = Read-Host "Selection"
        $l_binding = ""; $l_host = ""; $l_key = ""; $l_model = ""; $l_dim = ""

        switch ($l_choice) {
            "1" { 
                if ($b_binding -match "groq|deepseek|anthropic") {
                    Log-Warn "Auto-switching to Ollama for Librarian."
                    $l_binding = "ollama"; $l_host = "http://localhost:11434"; $l_key = "ollama"
                } else { $l_binding = $b_binding; $l_host = $b_host; $l_key = $b_key }
            }
            "2" { $l_binding = "gemini"; $l_host = "https://generativelanguage.googleapis.com/v1beta" }
            "3" { $l_binding = "openai"; $l_host = "https://api.openai.com/v1" }
            "7" { $l_binding = "ollama"; $l_host = "http://localhost:11434"; $l_key = "ollama" }
            "8" { $l_binding = "nvidia"; $l_host = "https://integrate.api.nvidia.com/v1" }
        }

        if ($l_binding -eq "ollama") { Ensure-Ollama }

        switch ($l_binding) {
            "gemini" { $l_model = "gemini-embedding-001"; $l_dim = "3072" }
            "openai" { $l_model = "text-embedding-3-large"; $l_dim = "3072" }
            "ollama" { $l_model = "nomic-embed-text"; $l_dim = "768" }
            "nvidia" { $l_model = "nvidia/nv-embedqa-e5-v5"; $l_dim = "1024" }
        }

        if ($l_binding -ne "" -and $l_choice -ne "1" -and $l_binding -ne "ollama") {
            $l_key = Read-Host "Paste your Librarian API Key"
        }

        # PHASE 3: EXPLORER
        Write-Host "`nStep 3: Configure The Explorer (Search)" -ForegroundColor White
        Write-Host "  1) Brave Search`n  2) Tavily`n  3) DuckDuckGo (Free)" -ForegroundColor Green
        $e_choice = Read-Host "Selection"
        $e_prov = ""; $e_key = "none"
        switch ($e_choice) {
            "1" { $e_prov = "brave"; $e_url = "https://api.search.brave.com/app/dashboard" }
            "2" { $e_prov = "tavily"; $e_url = "https://tavily.com/dashboard" }
            "3" { $e_prov = "duckduckgo" }
        }

        if ($e_prov -ne "" -and $e_prov -ne "duckduckgo") {
            try { Start-Process $e_url } catch {}
            $e_key = Read-Host "Paste Explorer API Key"
        }

        # SAVE
        $clean_pattern = "^(LLM_|EMBEDDING_|SEARCH_|GEMINI_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|DEEPSEEK_API_KEY|GROQ_API_KEY|MISTRAL_API_KEY|COHERE_API_KEY|BRAVE_API_KEY|TAVILY_API_KEY|PERPLEXITY_API_KEY|GOOGLE_API_KEY|NVIDIA_API_KEY)="
        if (Test-Path ".env") {
            $old_env = Get-Content ".env" | Where-Object { $_ -notmatch $clean_pattern }
            $old_env | Set-Content ".env"
        }
        "LLM_BINDING=$b_binding`nLLM_HOST=$b_host`nLLM_API_KEY=$b_key`nLLM_MODEL=$b_model" | Add-Content ".env"
        if ($b_env -ne "") { "$b_env=$b_key" | Add-Content ".env" }
        "EMBEDDING_BINDING=$l_binding`nEMBEDDING_HOST=$l_host`nEMBEDDING_API_KEY=$l_key`nEMBEDDING_MODEL=$l_model`nEMBEDDING_DIMENSION=$l_dim" | Add-Content ".env"
        "SEARCH_PROVIDER=$e_prov`nSEARCH_API_KEY=$e_key" | Add-Content ".env"
        Log-Success "Configuration saved to .env"
        $trigger_setup = $false
    }
}

# 5. Clear Ports
function Clear-Port($port) {
    $pid = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
    if ($pid) { Log-Warn "Clearing port $port (PID $pid)"; Stop-Process -Id $pid -Force }
}
Clear-Port 8001; Clear-Port 3782

# 6. Launch
if ($trigger_setup) {
    & $PYTHON_EXE scripts\start_tour.py $args
} else {
    & $PYTHON_EXE scripts\start_web.py $args
}
