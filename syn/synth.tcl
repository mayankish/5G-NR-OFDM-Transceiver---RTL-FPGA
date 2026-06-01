# ----------------------------------------------------------------------------
# synth.tcl — Vivado non-project synthesis of the OFDM transceiver
#
# Usage:
#   vivado -mode batch -source synth.tcl
#
# Produces:
#   syn/build/ofdm_transceiver_synth.dcp
#   syn/build/utilization_synth.rpt
#   syn/build/timing_synth.rpt
#
# Notes:
#   * Targets Nexys A7-100T (XC7A100T-1CSG324C). Edit `set part` for a
#     different board.
#   * This is a SYNTH-ONLY run for resource estimates; a full
#     synth+place+route flow lives in synth_impl.tcl.
# ----------------------------------------------------------------------------

set proj_root  [file normalize [file join [file dirname [info script]] ..]]
set rtl_dir    [file join $proj_root rtl]
set syn_dir    [file join $proj_root syn]
set build_dir  [file join $syn_dir build]
file mkdir $build_dir

set part   "xc7a100tcsg324-1"
set top    "ofdm_transceiver"

puts "INFO: synth.tcl using part=$part top=$top"
puts "INFO: rtl_dir=$rtl_dir"

# --- Read sources
set v_files [list \
    [file join $rtl_dir common complex_mult.v]   \
    [file join $rtl_dir common twiddle_rom.v]    \
    [file join $rtl_dir common fft64_engine.v]   \
    [file join $rtl_dir tx     qam_mapper.v]     \
    [file join $rtl_dir tx     subcarrier_mapper.v] \
    [file join $rtl_dir tx     cp_insert.v]      \
    [file join $rtl_dir tx     pss_gen.v]        \
    [file join $rtl_dir tx     ofdm_tx_top.v]    \
    [file join $rtl_dir rx     pss_correlator.v] \
    [file join $rtl_dir rx     cp_remove.v]      \
    [file join $rtl_dir rx     chan_est_ls.v]    \
    [file join $rtl_dir rx     zf_equalizer.v]   \
    [file join $rtl_dir rx     qam_demap.v]      \
    [file join $rtl_dir rx     ofdm_rx_top.v]    \
    [file join $rtl_dir top    ofdm_transceiver.v] \
]
read_verilog -sv $v_files

# .mem files referenced by $readmemh need to be on the include path
set_property include_dirs [list [file join $rtl_dir tx] [file join $rtl_dir rx]] [current_fileset]

# Constraints
read_xdc [file join $syn_dir nexys_a7.xdc]

# --- Synthesise
synth_design -top $top -part $part -flatten_hierarchy rebuilt
write_checkpoint -force [file join $build_dir ${top}_synth.dcp]

# --- Reports
report_utilization -file [file join $build_dir utilization_synth.rpt] -hierarchical
report_timing_summary -file [file join $build_dir timing_synth.rpt]

# --- Console summary
report_utilization -hierarchical
puts "INFO: done. Reports in $build_dir"
