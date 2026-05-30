###############################################################################
# Synopsys ICC2 script template
# Project: High-Performance Pipelined INT8 Systolic-Array AI Accelerator
# Top    : accel_top
# Usage  : icc2_shell -f scripts/run_icc2.tcl | tee logs/icc2.log
###############################################################################

set TOP accel_top
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_DIR   [file normalize "$SCRIPT_DIR/.."]
set DC_RESULT  "$PROJ_DIR/results/dc"
set SDC_FILE   "$DC_RESULT/${TOP}.sdc"
set NETLIST    "$DC_RESULT/${TOP}_mapped.v"
set REPORT_DIR "$PROJ_DIR/reports/icc2"
set RESULT_DIR "$PROJ_DIR/results/icc2"
set WORK_DIR   "$PROJ_DIR/work/icc2"

file mkdir $REPORT_DIR
file mkdir $RESULT_DIR
file mkdir $WORK_DIR

# -----------------------------------------------------------------------------
# 32 nm physical library setup
# Export these before running ICC2, or edit the paths below.
# Example:
#   export TECH_FILE=/path/to/32nm.tf
#   export REF_LIBS="/path/to/32nm_stdcell.ndm"
#   export GDS_MAP_FILE=/path/to/gds.map
#   export TLUPLUS_MAX=/path/to/max.tluplus
#   export TLUPLUS_MIN=/path/to/min.tluplus
#   export TLUPLUS_MAP=/path/to/tech2itf.map
# -----------------------------------------------------------------------------
if {[info exists ::env(TECH_FILE)]} {
    set TECH_FILE $::env(TECH_FILE)
} else {
    set TECH_FILE "/path/to/32nm/tech.tf"
}

if {[info exists ::env(REF_LIBS)]} {
    set REF_LIBS $::env(REF_LIBS)
} else {
    set REF_LIBS "/path/to/32nm/stdcell.ndm"
}

if {![file exists $TECH_FILE]} {
    puts "ERROR: TECH_FILE does not exist: $TECH_FILE"
    puts "Edit scripts/run_icc2.tcl or export TECH_FILE before running ICC2."
    quit
}

if {![file exists $NETLIST]} {
    puts "ERROR: mapped netlist not found: $NETLIST"
    puts "Run Design Compiler first using scripts/run_dc.tcl."
    quit
}

# -----------------------------------------------------------------------------
# Create/open design library
# -----------------------------------------------------------------------------
set DESIGN_LIB "$WORK_DIR/${TOP}.dlib"
if {[file exists $DESIGN_LIB]} {
    file delete -force $DESIGN_LIB
}

create_lib $DESIGN_LIB -technology $TECH_FILE -ref_libs $REF_LIBS
read_verilog $NETLIST
current_design $TOP
link_block

read_sdc $SDC_FILE

# Optional TLU+ RC setup. Uncomment after setting your lab's files.
# if {[info exists ::env(TLUPLUS_MAX)] && [info exists ::env(TLUPLUS_MIN)] && [info exists ::env(TLUPLUS_MAP)]} {
#     set_tlu_plus_files \
#         -max_tluplus $::env(TLUPLUS_MAX) \
#         -min_tluplus $::env(TLUPLUS_MIN) \
#         -tech2itf_map $::env(TLUPLUS_MAP)
# }

# -----------------------------------------------------------------------------
# Floorplan
# Adjust utilization/aspect ratio after checking congestion.
# -----------------------------------------------------------------------------
initialize_floorplan \
    -core_utilization 0.65 \
    -core_offset {5 5 5 5} \
    -side_ratio {1 1}

# Power planning template. Replace VDD/VSS with your library's power/ground names
# if they are different.
connect_pg_net -net VDD [get_pins -hierarchical */VDD]
connect_pg_net -net VSS [get_pins -hierarchical */VSS]

# Basic ring/mesh commands are technology-specific. Add your lab's preferred
# power-ring and strap commands here if required before placement.
# create_pg_ring_pattern ...
# create_pg_mesh_pattern ...
# compile_pg

check_design -checks pre_placement_stage > $REPORT_DIR/check_pre_place.rpt

# -----------------------------------------------------------------------------
# Placement, CTS, route
# -----------------------------------------------------------------------------
place_opt
report_qor            > $REPORT_DIR/qor_after_place.rpt
report_timing -max_paths 20 > $REPORT_DIR/timing_after_place.rpt
report_congestion     > $REPORT_DIR/congestion_after_place.rpt

clock_opt
report_clock_qor      > $REPORT_DIR/clock_qor_after_cts.rpt
report_timing -max_paths 20 > $REPORT_DIR/timing_after_cts.rpt

route_auto
route_opt

# -----------------------------------------------------------------------------
# Final reports
# -----------------------------------------------------------------------------
report_qor                         > $REPORT_DIR/qor_final.rpt
report_timing -delay_type max -max_paths 50 > $REPORT_DIR/timing_setup_final.rpt
report_timing -delay_type min -max_paths 50 > $REPORT_DIR/timing_hold_final.rpt
report_area                        > $REPORT_DIR/area_final.rpt
report_power                       > $REPORT_DIR/power_final.rpt
report_clock_qor                   > $REPORT_DIR/clock_qor_final.rpt
check_routes                       > $REPORT_DIR/check_routes.rpt
check_design                       > $REPORT_DIR/check_design_final.rpt

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
write_verilog $RESULT_DIR/${TOP}_icc2.v
write_sdc     $RESULT_DIR/${TOP}_icc2.sdc
write_def     $RESULT_DIR/${TOP}.def

# GDS export requires a map file in most 32 nm kits.
if {[info exists ::env(GDS_MAP_FILE)] && [file exists $::env(GDS_MAP_FILE)]} {
    write_gds -long_names -design $TOP -layer_map $::env(GDS_MAP_FILE) $RESULT_DIR/${TOP}.gds
} else {
    puts "WARNING: GDS_MAP_FILE not set. DEF/netlist written, GDS skipped."
}

save_block
save_lib

puts "ICC2 implementation complete. Results are in $RESULT_DIR and reports are in $REPORT_DIR"
exit
