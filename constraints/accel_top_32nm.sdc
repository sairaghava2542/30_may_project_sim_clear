###############################################################################
# SDC for pipelined INT8 systolic-array accelerator
# Target top: accel_top
# Technology: 32 nm standard-cell library
###############################################################################

# Update this clock period for your experiment.
# Suggested comparison points: 5.0 ns, 3.0 ns, 2.0 ns, then tighten until WNS < 0.
create_clock -name clk -period 5.000 [get_ports clk]

# Clock quality assumptions. Adjust based on your 32 nm library/flow guidance.
set_clock_uncertainty -setup 0.100 [get_clocks clk]
set_clock_uncertainty -hold  0.050 [get_clocks clk]
set_clock_transition 0.050 [get_clocks clk]

# Reset is asynchronous; do not time it as data.
set_false_path -from [get_ports rst_n]

# Generic IO timing assumptions for block-level synthesis.
set INPUT_PORTS  [remove_from_collection [all_inputs]  [get_ports {clk rst_n}]]
set OUTPUT_PORTS [all_outputs]

set_input_delay  0.200 -clock clk $INPUT_PORTS
set_output_delay 0.200 -clock clk $OUTPUT_PORTS

# Conservative electrical assumptions; replace with library-specific values if needed.
set_max_transition 0.150 [current_design]
set_max_fanout 16 [current_design]
set_load 0.020 $OUTPUT_PORTS

# Optional: uncomment if your lab gives a standard driving cell.
# set_driving_cell -lib_cell <INVX1_OR_BUF_CELL_NAME> $INPUT_PORTS

###############################################################################
# End of SDC
###############################################################################
