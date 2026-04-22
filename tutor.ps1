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

# 4. Interactive Configuration
# If .env doesn't exist, or has empty config, or the tour hasn't been finalized, trigger setup
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
    Write-Host "`n🚀 DeepTutor is ready!" -ForegroundColor Cyan -Style Bold
    Write-Host "  - Press Enter to start."
    Write-Host "  - Type 'r' and Enter to reconfigure/reset settings." -ForegroundColor Yellow
    $ready_choice = Read-Host "Choice"
    if ($ready_choice -eq "r" -or $ready_choice -eq "R") {
        $trigger_setup = $true
    }
}

if ($trigger_setup) {
    Write-Host "`n🔑 DeepTutor Setup" -ForegroundColor White -Style Bold
    
    # If we already have a .env, offer to just start
    if (Test-Path ".env") {
        $env_content = Get-Content ".env"
        if ($env_content | Select-String -Pattern "LLM_API_KEY=.+") {
            Write-Host "  0) Start DeepTutor Now (Use existing config)" -ForegroundColor Green -Style Bold
        }
    }

    # ── PHASE 1: THE BRAIN ───────────────────────────────────────────
    Write-Host "`nStep 1: Configure The Brain (LLM)" -ForegroundColor White -Style Bold
    Write-Host "Choose your AI provider for reasoning and chat:"
    Write-Host "  1) Gemini"
    Write-Host "  2) OpenAI"
    Write-Host "  3) Anthropic" -ForegroundColor Yellow
    Write-Host "  4) DeepSeek"
    Write-Host "  5) Groq"
    Write-Host "  6) NVIDIA NIM (Free - 80+ Models)" -ForegroundColor Green
    Write-Host "  7) Ollama (Local)"
    Write-Host "  s) Skip / Continue to Server`n"
    
    $b_choice = Read-Host "Selection"
    
    if ($b_choice -eq "0") {
        Write-Host "Starting DeepTutor..."
    } else {
        $b_binding = ""; $b_host = ""; $b_key_url = ""; $b_env = ""; $b_model = ""

        switch ($b_choice) {
            "1" { 
                $b_binding = "gemini"; $b_host = "https://generativelanguage.googleapis.com/v1beta/openai/"; $b_key_url = "https://aistudio.google.com/app/apikey"; $b_env = "GEMINI_API_KEY"; $b_model = "gemini-1.5-flash"
                Write-Host "`nChoose model grade:"
                Write-Host "  1) Standard (Gemini 1.5 Flash - Free & Fast)" -ForegroundColor Green
                Write-Host "  2) Power (Gemini 1.5 Pro - Smarter)" -ForegroundColor Blue
                $m_grade = Read-Host "Selection [1]"
                if ($m_grade -eq "2") { $b_model = "gemini-1.5-pro" } else { $b_model = "gemini-1.5-flash" }
            }
            "2" { 
                $b_binding = "openai"; $b_host = "https://api.openai.com/v1"; $b_key_url = "https://platform.openai.com/api-keys"; $b_env = "OPENAI_API_KEY"; $b_model = "gpt-4o-mini"
                Write-Host "`nChoose model grade:"
                Write-Host "  1) Standard (GPT-4o-mini - Cheap & Fast)" -ForegroundColor Green
                Write-Host "  2) Power (GPT-4o - Smarter)" -ForegroundColor Blue
                $m_grade = Read-Host "Selection [1]"
                if ($m_grade -eq "2") { $b_model = "gpt-4o" } else { $b_model = "gpt-4o-mini" }
            }
            "3" { 
                $b_binding = "anthropic"; $b_host = "https://api.anthropic.com/v1"; $b_key_url = "https://console.anthropic.com/settings/keys"; $b_env = "ANTHROPIC_API_KEY"; $b_model = "claude-3-5-haiku-latest"
                Write-Host "`nChoose model grade:"
                Write-Host "  1) Standard (Claude 3.5 Haiku)" -ForegroundColor Green
                Write-Host "  2) Power (Claude 3.5 Sonnet)" -ForegroundColor Blue
                $m_grade = Read-Host "Selection [1]"
                if ($m_grade -eq "2") { $b_model = "claude-3-5-sonnet-latest" } else { $b_model = "claude-3-5-haiku-latest" }
            }
            "4" { $b_binding = "deepseek"; $b_host = "https://api.deepseek.com"; $b_key_url = "https://platform.deepseek.com/api_keys"; $b_env = "DEEPSEEK_API_KEY"; $b_model = "deepseek-chat" }
            "5" { $b_binding = "groq"; $b_host = "https://api.groq.com/openai/v1"; $b_key_url = "https://console.groq.com/keys"; $b_env = "GROQ_API_KEY"; $b_model = "llama-3.3-70b-versatile" }
            "6" { 
                $b_binding = "nvidia"; $b_host = "https://integrate.api.nvidia.com/v1"; $b_key_url = "https://build.nvidia.com/models"; $b_env = "NVIDIA_API_KEY"
                Write-Host "`nChoose model grade:"
                Write-Host "  1) Standard (Llama-3.1-70B)" -ForegroundColor Green
                Write-Host "  2) Power (Llama-3.1-405B - Best)" -ForegroundColor Blue
                Write-Host "  3) DeepSeek-V3"
                $m_grade = Read-Host "Selection [1]"
                if ($m_grade -eq "2") { $b_model = "nvidia/llama-3.1-405b-instruct" } elseif ($m_grade -eq "3") { $b_model = "deepseek/deepseek-v3" } else { $b_model = "nvidia/llama-3.1-70b-instruct" }
            }
            "7" { $b_binding = "ollama"; $b_host = "http://localhost:11434/v1"; $b_env = ""; $b_model = "llama3.2" }
            Default { Write-Host "Skipping configuration..." }
        }
            Default { Write-Host "Skipping configuration..." }
        }

        if ($b_binding -ne "") {
            $b_key = "ollama"
            if ($b_binding -ne "ollama") {
                Write-Host "`n🔑 Get your $b_binding API Key at: $b_key_url" -ForegroundColor Blue -Style Bold
                
                # Frictionless: attempt to open the browser
                try { Start-Process "$b_key_url" } catch {}

                $b_key = Read-Host "Paste your Brain API Key (or press Enter once you have it)"
                while (-not $b_key) {
                    Write-Host "⚠️  A Brain API Key is required for $b_binding to work." -ForegroundColor Yellow
                    $b_key = Read-Host "Paste your Brain API Key"
                }
            }

            # ── PHASE 2: THE LIBRARIAN ───────────────────────────────────────
            Write-Host "`nStep 2: Configure The Librarian (Embedding)" -ForegroundColor White -Style Bold
            Write-Host "Choose your AI provider for reading documents:"
            
            # Recommendation for Groq/DeepSeek users
            if ($b_binding -eq "groq" -or $b_binding -eq "deepseek") {
                Write-Host "  Note: Your chosen Brain ($b_binding) does not support embeddings." -ForegroundColor Yellow
                Write-Host "  Recommended: Option 7 (Ollama) for local/free Librarian." -ForegroundColor Green
            }

            Write-Host "  1) Same as The Brain (Only if Brain supports it)" -Style Bold
            Write-Host "  2) Gemini"
            Write-Host "  3) OpenAI"
            Write-Host "  4) Mistral"
            Write-Host "  5) Voyage AI"
            Write-Host "  6) Cohere"
            Write-Host "  7) Ollama (Local & Free)" -ForegroundColor Green -Style Bold`n"
            
            $l_choice = Read-Host "Selection"
            $l_binding = ""; $l_host = ""; $l_key = ""; $l_dim = ""; $l_model = ""

            switch ($l_choice) {
                "1" { 
                    if ($b_binding -eq "groq" -or $b_binding -eq "deepseek" -or $b_binding -eq "anthropic") {
                        Write-Host "⚠️  $b_binding does not have a Librarian service. Switching to Ollama (Local) instead." -ForegroundColor Yellow
                        $l_binding = "ollama"; $l_host = "http://localhost:11434"; $l_key = "ollama"
                    } else {
                        $l_binding = $b_binding; $l_host = $b_host; $l_key = $b_key
                    }
                }
                "2" { $l_binding = "gemini"; $l_host = "https://generativelanguage.googleapis.com" }
                "3" { $l_binding = "openai"; $l_host = "https://api.openai.com/v1" }
                "4" { $l_binding = "mistral"; $l_host = "https://api.mistral.ai/v1" }
                "5" { $l_binding = "voyage"; $l_host = "https://api.voyageai.com/v1" }
                "6" { $l_binding = "cohere"; $l_host = "https://api.cohere.ai" }
                "7" { $l_binding = "ollama"; $l_host = "http://localhost:11434"; $l_key = "ollama" }
                Default { Write-Host "Skipping Librarian setup..." }
            }

            # Refine Gemini host: Librarian needs native v1beta
            if ($l_binding -eq "gemini") {
                $l_host = "https://generativelanguage.googleapis.com/v1beta"
            }

            if ($l_binding -ne "") {
                switch ($l_binding) {
                    "gemini" { $l_model = "gemini-embedding-001"; $l_dim = "3072" }
                    "openai" { $l_model = "text-embedding-3-large"; $l_dim = "3072" }
                    "mistral" { $l_model = "mistral-embed"; $l_dim = "1024" }
                    "voyage" { $l_model = "voyage-3"; $l_dim = "1024" }
                    "cohere" { $l_model = "embed-v4.0"; $l_dim = "1024" }
                    "ollama" { $l_model = "nomic-embed-text"; $l_dim = "768" }
                }
            }

            if ($l_binding -ne "" -and $l_choice -ne "1" -and $l_binding -ne "ollama") {
                $l_key = Read-Host "Paste your Librarian API Key"
            }

            # ── PHASE 3: THE EXPLORER ────────────────────────────────────────
            Write-Host "`nStep 3: Configure The Explorer (Web Search)" -ForegroundColor White -Style Bold
            Write-Host "Optional: choose a web search provider to enable real-time info:"
            Write-Host "  1) Brave Search (Highly Recommended)" -ForegroundColor Blue
            Write-Host "  2) Tavily (AI-optimized)" -ForegroundColor Yellow
            Write-Host "  3) DuckDuckGo (Free - No Key Needed)"
            Write-Host "  4) Perplexity"
            Write-Host "  5) Serper.dev (Google Search API)"
            Write-Host "  6) Jina Reader"
            Write-Host "  7) Exa.ai"
            Write-Host "  8) Baidu (China)"
            Write-Host "  s) Skip`n"
            
            $e_choice = Read-Host "Selection"
            $e_prov = ""; $e_url = ""; $e_key = ""

            switch ($e_choice) {
                "1" { $e_prov = "brave"; $e_url = "https://api.search.brave.com/app/dashboard" }
                "2" { $e_prov = "tavily"; $e_url = "https://tavily.com/dashboard" }
                "3" { $e_prov = "duckduckgo"; $e_key = "none" }
                "4" { $e_prov = "perplexity"; $e_url = "https://www.perplexity.ai/settings/api" }
                "5" { $e_prov = "serper"; $e_url = "https://serper.dev/dashboard" }
                "6" { $e_prov = "jina"; $e_url = "https://jina.ai/reader/" }
                "7" { $e_prov = "exa"; $e_url = "https://dashboard.exa.ai/" }
                "8" { $e_prov = "baidu"; $e_url = "https://ziyuan.baidu.com/console/index" }
            }

            if ($e_prov -ne "" -and $e_prov -ne "duckduckgo") {
                Write-Host "Get your key at: $e_url" -ForegroundColor Blue
                $e_key = Read-Host "Paste your Explorer API Key"
            }

            # ── SAVE TO .ENV ────────────────────────────────────────────────
            if (-not (Test-Path ".env")) { New-Item -Path ".env" -ItemType File }
            $clean_pattern = "^(LLM_|EMBEDDING_|SEARCH_|GEMINI_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|DEEPSEEK_API_KEY|GROQ_API_KEY|MISTRAL_API_KEY|COHERE_API_KEY|BRAVE_API_KEY|TAVILY_API_KEY|PERPLEXITY_API_KEY|GOOGLE_API_KEY|SERPER_API_KEY|JINA_API_KEY|EXA_API_KEY|BAIDU_API_KEY)="
            $temp_env = Get-Content ".env" | Where-Object { $_ -notmatch $clean_pattern }
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

                $l_env_key = switch ($l_binding) {
                    "gemini" { "GEMINI_API_KEY" }
                    "openai" { "OPENAI_API_KEY" }
                    "cohere" { "COHERE_API_KEY" }
                    Default { "" }
                }
                if ($l_env_key -ne "" -and $l_env_key -ne $b_env) {
                    Add-Content -Path ".env" -Value "$l_env_key=$l_key"
                }
            }
            if ($e_prov -ne "") {
                Add-Content -Path ".env" -Value "SEARCH_PROVIDER=$e_prov"
                Add-Content -Path ".env" -Value "SEARCH_API_KEY=$e_key"
                $e_env_key = switch ($e_prov) {
                    "brave" { "BRAVE_API_KEY" }
                    "tavily" { "TAVILY_API_KEY" }
                    "perplexity" { "PERPLEXITY_API_KEY" }
                    "serper" { "SERPER_API_KEY" }
                    "jina" { "JINA_API_KEY" }
                    "exa" { "EXA_API_KEY" }
                    "baidu" { "BAIDU_API_KEY" }
                    Default { "" }
                }
                if ($e_env_key -ne "") {
                    Add-Content -Path ".env" -Value "$e_env_key=$e_key"
                }
            }

            Log-Success "Configuration saved to .env"
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

# 6. Launch
if ($trigger_setup) {
    & $PYTHON_EXE scripts\start_tour.py $args
} else {
    & $PYTHON_EXE scripts\start_web.py $args
}
