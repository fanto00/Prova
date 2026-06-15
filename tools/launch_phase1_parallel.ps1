# Lancia 5 traduzioni parallele (Fase 1, moduli indipendenti)
# Usa Google Gemini API (freemium)
# Esegui: .\tools\launch_phase1_parallel.ps1

Write-Host "==============================================="
Write-Host "Fase 1: Traduzioni Parallele (5 Moduli)" -ForegroundColor Green
Write-Host "==============================================="
Write-Host ""
Write-Host "Prerequisiti:"
Write-Host "  ✓ GEMINI_API_KEY env var set (vedi SETUP_GEMINI.md)"
Write-Host "  ✓ google-generativeai installed (pip install google-generativeai)"
Write-Host ""

# Verifica GEMINI_API_KEY
if ([string]::IsNullOrEmpty($env:GEMINI_API_KEY)) {
    Write-Host "ERROR: GEMINI_API_KEY not set!" -ForegroundColor Red
    Write-Host "Run: `$env:GEMINI_API_KEY = '<your-key>'"
    exit 1
}

$PYTHON_SCRIPT = "tools/run_parallel_translations.py"

if (-not (Test-Path $PYTHON_SCRIPT)) {
    Write-Host "ERROR: Script not found: $PYTHON_SCRIPT" -ForegroundColor Red
    exit 1
}

Write-Host "Starting 5 parallel processes..."
Write-Host ""

# Crea cartella per i log
$logDir = ".\tools\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Lancia 5 process in background
$jobs = @()

for ($i = 1; $i -le 5; $i++) {
    $logFile = "$logDir\module_$i.log"
    $job = Start-Job -ScriptBlock {
        param($module, $script)
        python $script --module $module
    } -ArgumentList $i, $PYTHON_SCRIPT

    $jobs += $job
    Write-Host "  [$i] Job ID $($job.Id) → Module $i"
}

Write-Host ""
Write-Host "Waiting for all processes..."
Write-Host ""

# Aspetta che tutti finiscano
$jobs | Wait-Job

# Raccogli risultati
Write-Host ""
Write-Host "==============================================="
Write-Host "✓ Fase 1 Complete!" -ForegroundColor Green
Write-Host "==============================================="
Write-Host ""

# Mostra risultati
foreach ($job in $jobs) {
    $result = Receive-Job -Job $job
    Write-Host "Job $($job.Id):" -ForegroundColor Yellow
    Write-Host $result
    Write-Host ""
}

# Cleanup
$jobs | Remove-Job

Write-Host "Next: Run TDD tests and math reviews"
Write-Host "  python -m pytest tests/test_app_*.py -v" -ForegroundColor Cyan
Write-Host ""
