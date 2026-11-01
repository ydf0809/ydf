# Arguments: main XPR, report directory, parallel jobs.
if {$argc != 3} { error "Expected: project.xpr report_directory jobs" }
set xpr [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set jobs [lindex $argv 2]
file mkdir $out
open_project $xpr
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]
update_compile_order -fileset sources_1
set ips [get_ips -quiet]
if {[llength $ips]} { generate_target all $ips }
set top [get_property TOP [get_filesets sources_1]]
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis did not finish: [get_property STATUS [get_runs synth_1]]"
}
launch_runs impl_1 -to_step route_design -jobs $jobs
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation did not finish: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
report_methodology -file [file join $out methodology.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_io -file [file join $out io.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {![llength $setup] || ![llength $hold]} { error "Required timing paths are missing" }
set wns [get_property SLACK $setup]
set whs [get_property SLACK $hold]
set errors [llength [get_drc_violations -filter {SEVERITY == Error}]]
set f [open [file join $out timing.rpt] r]
set timing [read $f]
close $f
set f [open [file join $out methodology.rpt] r]
set methodology [read $f]
close $f
set loops 0
if {[regexp -nocase {checking loops [(]([1-9][0-9]*)[)]} $timing] ||
    [regexp {TIMING-23} $methodology]} { set loops 1 }
set f [open [file join $out metrics.txt] w]
puts $f "tool_version=[version -short]"
puts $f "top=$top"
puts $f "part=[get_property PART [current_project]]"
puts $f "wns=$wns"
puts $f "whs=$whs"
puts $f "drc_errors=$errors"
puts $f "loop_warning_present=$loops"
close $f
if {$wns < 0 || $whs < 0 || $errors != 0 || $loops != 0} {
    error "Candidate rejected: inspect timing, DRC and methodology reports"
}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Bit generation failed" }
set bit [file join [get_property DIRECTORY [get_runs impl_1]] [format "%s.bit" $top]]
if {![file exists $bit]} { error "Main-run bitstream is missing" }
set f [open [file join $out bit_path.txt] w]
puts $f $bit
close $f
close_project
puts "PREVIEW_BUILD_PASS $top"
