set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root results program_latest_upper]
file mkdir $out
set bit [file join $root merged_cam_lcd_voice_scnn.runs impl_1 top.bit]
set verified_hash_file [file join $root results code_review_20261103 bitstream.sha256]
if {![file exists $verified_hash_file]} {error "Verified bitstream hash missing; run the checked project build first"}
set f [open $verified_hash_file r]; set expected_hash [string trim [read $f]]; close $f
set hash_report [exec certutil.exe -hashfile $bit SHA256]
if {![regexp -nocase {[0-9a-f]{64}} $hash_report actual_hash]} {error "Cannot read bitstream SHA-256"}
if {![string equal -nocase $actual_hash $expected_hash]} {error "The bitstream differs from the verified build"}
if {![file exists $bit] || [file size $bit] == 0} { error "Bitstream missing or empty: $bit" }
open_hw_manager
connect_hw_server -url localhost:3121 -cs_url localhost:3042
set targets [get_hw_targets -quiet]
if {[llength $targets] == 0} { error "No JTAG hardware target found; check upper board power and cable" }
set matches {}
foreach target $targets {
    if {[catch {open_hw_target $target} message]} {
        puts "UPPER: TARGET_UNAVAILABLE target=$target message=$message"
        continue
    }
    foreach device [get_hw_devices -quiet] {
        set part [get_property PART $device]
        puts "UPPER: DEVICE target=$target device=$device part=$part"
        if {[string match "xc7z020*" $part]} { lappend matches [list $target $device $part] }
    }
    close_hw_target $target
}
puts "UPPER: MATCH_COUNT=[llength $matches]"
if {[llength $matches] != 1} { error "Expected exactly one xc7z020 device; refusing ambiguous selection" }
lassign [lindex $matches 0] target device part
open_hw_target $target
set device [get_hw_devices $device]
current_hw_device $device
set_property PROBES.FILE {} $device
set_property FULL_PROBES.FILE {} $device
set_property PROGRAM.FILE $bit $device
puts "UPPER: PROGRAM_START target=$target device=$device bit=$bit"
program_hw_devices $device
refresh_hw_device $device
set done [get_property REGISTER.IR.BIT5_DONE $device]
set status [open [file join $out program_status.txt] w]
puts $status "Device: $device"
puts $status "Part: $part"
puts $status "Target: $target"
puts $status "Bitstream: $bit"
puts $status "SHA-256: $expected_hash"
puts $status "DONE: $done"
puts $status "Configuration: JTAG volatile (no flash write)"
close $status
if {$done ni {1 true TRUE}} { error "FPGA DONE was not asserted after programming: $done" }
puts "UPPER: PROGRAM_PASS device=$device DONE=$done"
close_hw_target $target
disconnect_hw_server
close_hw_manager
