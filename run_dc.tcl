###############################################################################
# Synopsys Design Compiler synthesis script
# Project : High-Performance Pipelined INT8 Systolic-Array AI Accelerator
# Top     : accel_top
#
# Run:
#   dc_shell -f scripts/run_dc.tcl | tee dc.log
#
# Default library:
#   SAED32 LVT typical corner, 1.05 V, 25 C
###############################################################################

set TOP accel_top

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_DIR   [file normalize "$SCRIPT_DIR/.."]
set RTL_DIR    "$PROJ_DIR/rtl"
set SDC_FILE   "$PROJ_DIR/constraints/accel_top_32nm.sdc"

set REPORT_DIR "$PROJ_DIR/reports/dc"
set RESULT_DIR "$PROJ_DIR/results/dc"
set WORK_DIR   "$PROJ_DIR/work/dc"

file mkdir $REPORT_DIR
file mkdir $RESULT_DIR
file mkdir $WORK_DIR

###############################################################################
# Library setup
###############################################################################

# Export these from the shell, or let the script use the SAED32 defaults below.
if {[info exists ::env(PDK_ROOT)]} {
    set PDK_ROOT $::env(PDK_ROOT)
} else {
    set PDK_ROOT "/data/pdk/pdk32nm/SAED32_EDK"
}

if {[info exists ::env(TARGET_LIB)]} {
    set TARGET_LIB $::env(TARGET_LIB)
} else {
    # High-performance choice: LVT typical, 1.05 V, 25 C.
    set TARGET_LIB "$PDK_ROOT/lib/stdcell_lvt/db_ccs/saed32lvt_tt1p05v25c.db"
}

if {[info exists ::env(LINK_LIBS)]} {
    set LINK_LIBS $::env(LINK_LIBS)
} else {
    # Optional: keep other VT libraries visible for linking only.
    set LINK_LIBS [list \
        $TARGET_LIB \
        "$PDK_ROOT/lib/stdcell_rvt/db_ccs/saed32rvt_tt1p05v25c.db" \
        "$PDK_ROOT/lib/stdcell_hvt/db_ccs/saed32hvt_tt1p05v25c.db" \
    ]
}

if {![file exists $TARGET_LIB]} {
    puts "ERROR: TARGET_LIB not found: $TARGET_LIB"
    puts "Check PDK_ROOT or choose another .db file from your SAED32 library folder."
    quit
}

foreach lib $LINK_LIBS {
    if {![file exists $lib]} {
        puts "ERROR: link library not found: $lib"
        quit
    }
}

define_design_lib WORK -path $WORK_DIR

set_app_var search_path [list \
    $RTL_DIR \
    "$PDK_ROOT/lib/stdcell_lvt/db_ccs" \
    "$PDK_ROOT/lib/stdcell_rvt/db_ccs" \
    "$PDK_ROOT/lib/stdcell_hvt/db_ccs" \
]

set_app_var target_library [list $TARGET_LIB]
set_app_var link_library   [concat "*" $LINK_LIBS]

# Use DesignWare arithmetic implementations where available.
set_app_var synthetic_library [list dw_foundation.sldb]
set_app_var link_library [concat $link_library $synthetic_library]

set_app_var hdlin_enable_vpp true
set_app_var verilogout_no_tri true
set_app_var compile_seqmap_identify_shift_registers false

###############################################################################
# Read and elaborate RTL
###############################################################################

set RTL_FILES [list \
    "$RTL_DIR/systolic_pe.v" \
    "$RTL_DIR/systolic_array_8x8.v" \
    "$RTL_DIR/accel_regs.v" \
    "$RTL_DIR/accel_top.v" \
]

analyze -format sverilog $RTL_FILES
elaborate $TOP
current_design $TOP
link
uniquify

check_design > "$REPORT_DIR/check_design.rpt"

###############################################################################
# Constraints and synthesis
###############################################################################

source $SDC_FILE
check_timing > "$REPORT_DIR/check_timing_precompile.rpt"

# High-effort timing synthesis for the pipelined performance project.
compile_ultra -timing_high_effort_script -no_autoungroup

check_timing > "$REPORT_DIR/check_timing_postcompile.rpt"
check_design > "$REPORT_DIR/check_design_postcompile.rpt"

###############################################################################
# Reports
###############################################################################

report_qor                                      > "$REPORT_DIR/qor.rpt"
report_timing -delay_type max -max_paths 20    > "$REPORT_DIR/timing_setup.rpt"
report_timing -delay_type min -max_paths 20    > "$REPORT_DIR/timing_hold.rpt"
report_area                                    > "$REPORT_DIR/area.rpt"
report_area -hierarchy                         > "$REPORT_DIR/area_hier.rpt"
report_power                                   > "$REPORT_DIR/power.rpt"
report_power -hierarchy                        > "$REPORT_DIR/power_hier.rpt"
report_constraint -all_violators               > "$REPORT_DIR/constraints_violators.rpt"
report_reference -hierarchy                    > "$REPORT_DIR/reference_hier.rpt"

###############################################################################
# Outputs for ICC2
###############################################################################

write -format ddc     -hierarchy -output "$RESULT_DIR/${TOP}.ddc"
write -format verilog -hierarchy -output "$RESULT_DIR/${TOP}_mapped.v"
write_sdc "$RESULT_DIR/${TOP}.sdc"
write_sdf "$RESULT_DIR/${TOP}.sdf"

puts "======================================================================"
puts "DC synthesis completed successfully."
puts "Target library : $TARGET_LIB"
puts "Reports        : $REPORT_DIR"
puts "Results        : $RESULT_DIR"
puts "======================================================================"

exit
