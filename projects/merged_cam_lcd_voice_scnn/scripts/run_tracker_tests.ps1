$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$simSrc = Join-Path $root 'merged_cam_lcd_voice_scnn.srcs/sim_1/new'
$simDir = Join-Path $root 'generated/tracker_tests'
$logDir = Join-Path $root 'results/cleanup_20261102/tests'
New-Item -ItemType Directory -Force -Path $simDir,$logDir | Out-Null
$bin = if($env:XILINX_VIVADO) { Join-Path $env:XILINX_VIVADO 'bin' } else {
    $v = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if($v) { Split-Path -Parent $v.Source } else { 'D:/vivado2026.1/2026.1/Vivado/bin' }
}
if(-not $env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE='AMD64' }
foreach($tool in @('xvlog.bat','xelab.bat','xsim.bat')) {
    if(-not (Test-Path (Join-Path $bin $tool))) { throw "Missing simulator: $tool" }
}
if(Test-Path -LiteralPath (Join-Path $root 'weights')) { Copy-Item -LiteralPath (Join-Path $root 'weights') -Destination $simDir -Recurse -Force }
$rtl = Get-ChildItem (Join-Path $root 'rtl') -Filter '*.v' | ForEach-Object FullName
$tb = Get-ChildItem -LiteralPath $simSrc -Recurse -Filter '*.v' | ForEach-Object FullName
$filelist = Join-Path $simDir 'compile.f'
@($rtl + $tb) | ForEach-Object { '"' + $_ + '"' } | Set-Content -LiteralPath $filelist -Encoding ascii
$tests = @(
    @{Top='tb_i2c_config_clock'; Pass='I2C_CONFIG_CLOCK_TEST: PASS'},
    @{Top='tb_lcd_box_color'; Pass='LCD_BOX_COLOR_TEST: PASS'},
    @{Top='tb_air_defence_mode'; Pass='AIR_DEFENCE_MODE_TEST: PASS'},
    @{Top='tb_motion_candidate_priority'; Pass='MOTION_PRIORITY_TEST: PASS'},
    @{Top='tb_motion_detector'; Pass='TEST_RESULT: PASS'},
    @{Top='tb_roi_scheduler'; Pass='ROI_TEST: PASS'},
    @{Top='tb_periodic_recheck'; Pass='PERIODIC_RECHECK_TEST: PASS'},
    @{Top='tb_integrated_recheck_cdc'; Pass='INTEGRATED_RECHECK_CDC_TEST: PASS'},
    @{Top='tb_servo6_compat'; Pass='SERVO6_COMPAT_TEST: PASS'},
    @{Top='tb_lower_display_compat'; Pass='LOWER_DISPLAY_COMPAT_TEST: PASS'},
    @{Top='tb_upper_lower_serial_compat'; Pass='UPPER_LOWER_SERIAL_COMPAT_TEST: PASS'}
)
Push-Location $simDir
try {
    & (Join-Path $bin 'xvlog.bat') --sv -f $filelist 2>&1 | Out-File (Join-Path $logDir 'compile.log')
    if($LASTEXITCODE -ne 0) { Get-Content (Join-Path $logDir 'compile.log'); throw 'Compile failed' }
    foreach($test in $tests) {
        & (Join-Path $bin 'xelab.bat') -L unisims_ver $test.Top -s "$($test.Top)_sim" 2>&1 |
            Out-File (Join-Path $logDir "$($test.Top)_elaborate.log")
        if($LASTEXITCODE -ne 0) { Get-Content (Join-Path $logDir "$($test.Top)_elaborate.log"); throw "Elaboration failed: $($test.Top)" }
        $output = & (Join-Path $bin 'xsim.bat') "$($test.Top)_sim" -runall 2>&1
        $output | Out-File (Join-Path $logDir "$($test.Top).log")
        $output | Select-String 'PASS|FAIL|ERROR'
        if($LASTEXITCODE -ne 0 -or ($output -join ' ') -notmatch [regex]::Escape($test.Pass) -or ($output -join ' ') -match 'FAIL|ERROR:') {
            throw "Regression failed: $($test.Top)"
        }
    }
    "TRACKER_REGRESSION: PASS ($($tests.Count) testbenches)"
} finally { Pop-Location }
