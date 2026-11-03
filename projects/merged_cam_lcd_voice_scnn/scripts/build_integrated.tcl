# Rebuild this main XPR; all design/report paths stay inside this project.
set root [file normalize [file join [file dirname [info script]] ..]]
set xpr [file join $root merged_cam_lcd_voice_scnn.xpr]
set out [file join $root generated display_restart_compat_20261102]
file mkdir $out
open_project $xpr
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]
update_compile_order -fileset sources_1
set top [get_property TOP [get_filesets sources_1]]
puts "XPR_SYNC_PROJECT=$xpr TOP=$top"
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
report_methodology -file [file join $out methodology.rpt]
set f [open [file join $out timing.rpt] r]
set timing_text [read $f]
close $f
set f [open [file join $out methodology.rpt] r]
set methodology_text [read $f]
close $f
if {[regexp -nocase {checking loops [(]([1-9][0-9]*)[)]} $timing_text] ||
    [regexp {TIMING-23} $methodology_text]} {
    error "Combinational loop check failed; no bitstream is released"
}

set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {![llength $setup] || ![llength $hold]} {error "Timing paths missing"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set drc_errors [llength [get_drc_violations -filter {SEVERITY == Error}]]
puts "XPR_SYNC_TIMING WNS=$wns WHS=$whs DRC_ERRORS=$drc_errors"
if {$wns < 0 || $whs < 0 || $drc_errors != 0} {
    error "Timing or DRC failed; no new programming bit is released"
}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Bit generation failed: [get_property STATUS [get_runs impl_1]]"
}
set bit [file join [get_property DIRECTORY [get_runs impl_1]] ${top}.bit]
if {![file exists $bit]} {error "Original run bit missing: $bit"}
set f [open [file join $out build_result.txt] w]
puts $f "bit=$bit"
puts $f "top=$top"
puts $f "wns=$wns"
puts $f "whs=$whs"
puts $f "drc_errors=$drc_errors"
close $f
close_project
puts "XPR_SYNC_SUCCESS=$bit"
