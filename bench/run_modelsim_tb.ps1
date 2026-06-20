# Script PowerShell để chạy testbench ModelSim
# Usage: .\run_modelsim_tb.ps1

# Kiểm tra xem ModelSim đã cài đặt chưa
$ModelSimPath = "vsim"
$ModelSimFound = $false

# Thử tìm vsim trong PATH
try {
    $vsim_check = Get-Command "vsim" -ErrorAction Stop
    $ModelSimFound = $true
    $ModelSimPath = $vsim_check.Source
    Write-Host "✓ ModelSim found at: $ModelSimPath" -ForegroundColor Green
} catch {
    Write-Host "✗ ModelSim (vsim) not found in PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install ModelSim or add it to your PATH"
    Write-Host "Common installation paths:"
    Write-Host "  - C:\Program Files\Mentor\Modelsim\*\win32pe\vsim.exe"
    Write-Host "  - C:\intelFPGA\*\modelsim_ase\win32aloem\vsim.exe"
    exit 1
}

# Lấy thư mục hiện tại của script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Starting ModelSim Testbench"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Working directory: $ScriptDir"
Write-Host ""

# Điều hướng đến thư mục bench
Push-Location $ScriptDir

# Chạy ModelSim với script .do
Write-Host "Running ModelSim with do-file: run_tb_lane.do" -ForegroundColor Yellow
Write-Host ""

# Chạy vsim theo batch mode (không hiển thị GUI)
& vsim -do "run_tb_lane.do" -batch

# Kiểm tra exit code
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✓ Simulation completed successfully!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✗ Simulation encountered an error (Exit code: $LASTEXITCODE)" -ForegroundColor Red
}

# Verify output files
if (Test-Path "transcript") {
    Write-Host ""
    Write-Host "Generated files:" -ForegroundColor Cyan
    Write-Host "  - transcript (simulation log)"
    if (Test-Path "work") {
        Write-Host "  - work/ (compiled design directory)"
    }
}

Pop-Location

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Testbench Execution Finished"
Write-Host "========================================" -ForegroundColor Cyan
