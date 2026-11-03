# Verify the implementation and bit already produced by build_integrated.tcl.
set root [file normalize [file join [file dirname [info script]] ..]]
set project [file join $root merged_cam_lcd_voice_scnn.xpr]
set out [file join $root generated display_restart_compat_20261102]
file mkdir $out
open_project $project
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
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {![llength $setup] || ![llength $hold]} {error "Timing paths missing"}
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set drc_errors [llength [get_drc_violations -filter {SEVERITY == Error}]]
if {[regexp -nocase {checking loops [(]([1-9][0-9]*)[)]} $timing_text] ||
    [regexp {TIMING-23} $methodology_text]} {error "Combinational-loop check failed"}
if {$wns < 0 || $whs < 0 || $drc_errors != 0} {error "Timing or DRC check failed"}
set bit [file join $root merged_cam_lcd_voice_scnn.runs impl_1 top.bit]
if {![file exists $bit] || [file size $bit] == 0} {error "Built bitstream is missing or empty"}
set f [open [file join $out build_result.txt] w]
puts $f "bit=$bit"
puts $f "top=top"
puts $f "wns=$wns"
puts $f "whs=$whs"
puts $f "drc_errors=$drc_errors"
puts $f "loops=0"
close $f
puts "DISPLAY_RESTART_VERIFY_PASS WNS=$wns WHS=$whs DRC_ERRORS=$drc_errors LOOPS=0 BIT=$bit"
close_design
close_project
