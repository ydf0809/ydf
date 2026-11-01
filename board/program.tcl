# Run only after checking the physical board, exact device and bit manifest.
# vivado -mode batch -source board/program.tcl -tclargs upper target_name device_name
if {$argc != 3} { error "Expected: upper|lower exact_hw_target exact_hw_device" }
set board [lindex $argv 0]
set target_name [lindex $argv 1]
set device_name [lindex $argv 2]
if {$board ni {upper lower}} { error "Unknown board" }
set root [file normalize [file join [file dirname [info script]] ..]]
set filename [expr {$board eq "upper" ? "top.bit" : "super_top.bit"}]
set bit [file join $root board bitstreams $board $filename]
if {![file isfile $bit]} { error "Build the selected main XPR first" }
open_hw_manager
connect_hw_server
set targets [get_hw_targets -quiet $target_name]
if {[llength $targets] != 1 || [get_property NAME $targets] ne $target_name} {
    error "Target must match exactly one connected board"
}
open_hw_target $targets
set devices [get_hw_devices -quiet $device_name]
if {[llength $devices] != 1 || [get_property NAME $devices] ne $device_name} {
    error "Device must match exactly one selected device"
}
if {![string match "xc7z020*" [get_property PART $devices]]} {
    error "Unexpected device; expected xc7z020"
}
set_property PROGRAM.FILE $bit $devices
program_hw_devices $devices
close_hw_manager
puts "PROGRAMMED $board; programming success is not functional validation"
