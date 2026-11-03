set root [file normalize [file join [file dirname [info script]] ..]]
set xprs [glob -nocomplain -directory $root *.xpr]
if {[llength $xprs] != 1} {error "Expected one main XPR"}
set xpr [lindex $xprs 0]
set out [file join $root results code_review_20261103]
file mkdir $out
open_project $xpr
reset_project -exclude_ips -exclude_sim_runs
set top [get_property TOP [get_filesets sources_1]]
if {$top eq "super_top"} {
    set_property PROCESSING_ORDER LATE [get_files *10086.xdc]
    set clock_ip [get_ips clk_wiz_0]
    if {[get_property CONFIG.PRIM_SOURCE $clock_ip] ne "No_buffer"} {
        set_property CONFIG.PRIM_SOURCE No_buffer $clock_ip
        generate_target all $clock_ip
    }
}
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {error "Implementation failed"}
open_run impl_1
report_drc -file [file join $out drc.rpt]
set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]
report_methodology -file [file join $out methodology.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 -file [file join $out timing.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_utilization -file [file join $out utilization.rpt]
set f [open [file join $out timing.rpt] r]; set timing [read $f]; close $f
set f [open [file join $out methodology.rpt] r]; set methodology [read $f]; close $f
foreach name {no_clock unconstrained_internal_endpoints loops latch_loops} {
    set pattern [format {checking %s \(([1-9][0-9]*)\)} $name]
    if {[regexp $pattern $timing]} {error "Clock coverage or loop check failed: $name"}
}
if {[regexp {TIMING-(4|17|23|27)[ |#]} $methodology]} {error "Clock methodology check failed"}
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set f [open [file join $out build_result.txt] w]
puts $f "top=$top"; puts $f "wns=$wns"; puts $f "whs=$whs"; puts $f "drc_errors=$drc_errors"
close $f
if {$wns < 0 || $whs < 0 || $drc_errors != 0} {error "Timing/DRC check failed; bitstream not released"}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Bitstream generation failed"}
set bit [file join [get_property DIRECTORY [get_runs impl_1]] ${top}.bit]
if {![file exists $bit]} {error "Main-run bitstream missing"}
set hash_report [exec certutil.exe -hashfile $bit SHA256]
if {![regexp -nocase {[0-9a-f]{64}} $hash_report bit_hash]} {error "Cannot read bitstream SHA-256"}
set f [open [file join $out bitstream.sha256] w]; puts $f [string toupper $bit_hash]; close $f
puts "REVIEW_BUILD_PASS TOP=$top WNS=$wns WHS=$whs DRC_ERRORS=$drc_errors BIT=$bit"
close_project
