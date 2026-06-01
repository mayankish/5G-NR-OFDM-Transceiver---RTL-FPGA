# ----------------------------------------------------------------------------
# nexys_a7.xdc — Constraints for OFDM Transceiver on Digilent Nexys A7-100T
#
# Maps:
#   clk          → 100 MHz on-board oscillator (E3)
#   rst_n        → CPU_RESET button, active low (C12)
#   start_frame  → BTNC button (N17)
#   mode         → SW0 switch (J15)
#   bits_in[3:0] → SW4..SW1 (V10, U11, U12, H6)
#   bits_in_valid→ SW5 (T5)
#   bits_in_ready→ LD0 (H17)
#   bits_out[3:0]→ LD4..LD1 (V14, V12, T15, K15)
#   bits_out_valid → LD5 (P14)
#   frame_done   → LD15 (V11)
#   symbol_start → LD14 (U13)
#
# (Switches and LEDs let you smoke-test the design after programming the
#  board with a single PSS frame, even without USB-UART hookup.)
# ----------------------------------------------------------------------------

# 100 MHz clock
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# Reset (CPU_RESET, active low)
set_property -dict { PACKAGE_PIN C12  IOSTANDARD LVCMOS33 } [get_ports rst_n]

# Buttons
set_property -dict { PACKAGE_PIN N17  IOSTANDARD LVCMOS33 } [get_ports start_frame]

# Switches
set_property -dict { PACKAGE_PIN J15  IOSTANDARD LVCMOS33 } [get_ports mode]
set_property -dict { PACKAGE_PIN H6   IOSTANDARD LVCMOS33 } [get_ports {bits_in[0]}]
set_property -dict { PACKAGE_PIN U12  IOSTANDARD LVCMOS33 } [get_ports {bits_in[1]}]
set_property -dict { PACKAGE_PIN U11  IOSTANDARD LVCMOS33 } [get_ports {bits_in[2]}]
set_property -dict { PACKAGE_PIN V10  IOSTANDARD LVCMOS33 } [get_ports {bits_in[3]}]
set_property -dict { PACKAGE_PIN T5   IOSTANDARD LVCMOS33 } [get_ports bits_in_valid]

# LEDs
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports bits_in_ready]
set_property -dict { PACKAGE_PIN K15  IOSTANDARD LVCMOS33 } [get_ports {bits_out[0]}]
set_property -dict { PACKAGE_PIN T15  IOSTANDARD LVCMOS33 } [get_ports {bits_out[1]}]
set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports {bits_out[2]}]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {bits_out[3]}]
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports bits_out_valid]
set_property -dict { PACKAGE_PIN V11  IOSTANDARD LVCMOS33 } [get_ports frame_done]
set_property -dict { PACKAGE_PIN U13  IOSTANDARD LVCMOS33 } [get_ports symbol_start]

# nbits_out — leave unconstrained, removed in synth if no pin assigned
# Use create_generated_clock or set_input_delay/set_output_delay if you wire
# any of these to an external synchronous interface.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
