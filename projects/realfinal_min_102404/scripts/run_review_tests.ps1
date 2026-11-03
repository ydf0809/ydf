param([switch]$Quick)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'generated/code_review_20261103/sim'
$rtlDir=Join-Path $stage 'rtl'
$logs=Join-Path $root 'results/code_review_20261103/tests'
New-Item -ItemType Directory -Force -Path $stage,$rtlDir,$logs | Out-Null
$bin=if($env:XILINX_VIVADO){Join-Path $env:XILINX_VIVADO 'bin'}else{'D:/vivado2026.1/2026.1/Vivado/bin'}
if(-not $env:PROCESSOR_ARCHITECTURE){$env:PROCESSOR_ARCHITECTURE='AMD64'}
[xml]$project=Get-Content -LiteralPath (Join-Path $root 'realfinal.xpr') -Raw -Encoding utf8
$staged=@()
foreach($node in $project.SelectNodes("//FileSet[@Name='sources_1']/File")){
    $path=$node.Path.Replace('$PPRDIR',$root).Replace('$PSRCDIR',(Join-Path $root 'realfinal.srcs'))
    if([IO.Path]::GetExtension($path) -in @('.v','.sv')){
        $target=Join-Path $rtlDir ([IO.Path]::GetFileName($path))
        Copy-Item -LiteralPath $path -Destination $target -Force
        $staged+=$target
    }
}
$benches=Get-ChildItem -LiteralPath (Join-Path $root 'realfinal.srcs/sim_1/new') -Filter 'tb*.v' | ForEach-Object FullName
$list=Join-Path $stage 'compile.f'
$glbl=Join-Path (Split-Path -Parent $bin) 'data/verilog/src/glbl.v'
@($staged+$benches+$glbl)|ForEach-Object {'"'+$_+'"'}|Set-Content -LiteralPath $list -Encoding ascii
$tops=if($Quick){@('tb_rgb2hsv_pipeline','tb_camera_box_cdc','tb_ov7670_capture')}else{@('tb_rgb2hsv_pipeline','tb_camera_box_cdc','tb_ov7670_capture','tb_arm_red_track','tb_defense_spin','tb_bbox_unpack','tb_arm_stop','tb_voice_arm','tb_voice_mode','tb_board_link','tb_chassis_filter','tb_line_pid','tb_corner_turn','tb_iic_stop','tb_xunbi_tracking')}
Push-Location $stage
try{
    & (Join-Path $bin 'xvlog.bat') --sv -f $list 2>&1|Out-File (Join-Path $logs 'compile.log')
    if($LASTEXITCODE -ne 0){Get-Content (Join-Path $logs 'compile.log');throw 'Lower RTL compilation failed'}
    foreach($top in $tops){
        & (Join-Path $bin 'xelab.bat') -L unisims_ver $top glbl -s ($top+'_sim') 2>&1|Out-File (Join-Path $logs ($top+'_elaborate.log'))
        if($LASTEXITCODE -ne 0){Get-Content (Join-Path $logs ($top+'_elaborate.log'));throw "Elaboration failed: $top"}
        $output=& (Join-Path $bin 'xsim.bat') ($top+'_sim') -runall 2>&1
        $output|Out-File (Join-Path $logs ($top+'.log'))
        $output|Select-String 'PASS|FAIL|ERROR'
        if($LASTEXITCODE -ne 0 -or ($output -join ' ') -notmatch 'PASS' -or ($output -join "`n") -match '\bFAIL(?:ED)?\b|(?m)^\s*(?:ERROR|FATAL):'){throw "Regression failed: $top"}
    }
    "LOWER_REVIEW_REGRESSION_PASS tests=$($tops.Count)"
}finally{Pop-Location}
