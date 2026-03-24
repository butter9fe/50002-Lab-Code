set_property PACKAGE_PIN N14 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
# clk => 100000000Hz
create_clock -period 10.0 -name clk_0 -waveform {0.000 5.0} [get_ports clk]
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks clk_0]

set_property PACKAGE_PIN P6 [get_ports {rst_n}]
set_property IOSTANDARD LVCMOS33 [get_ports {rst_n}]

set_property PACKAGE_PIN K13 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN K12 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN L14 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN L13 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

set_property PACKAGE_PIN M16 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN M14 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN M12 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN N16 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

set_property PACKAGE_PIN P15 [get_ports {usb_rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {usb_rx}]

set_property PACKAGE_PIN P16 [get_ports {usb_tx}]
set_property IOSTANDARD LVCMOS33 [get_ports {usb_tx}]

set_property PACKAGE_PIN E2 [get_ports {vga_r}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r}]

set_property PACKAGE_PIN A2 [get_ports {vga_g}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g}]

set_property PACKAGE_PIN E1 [get_ports {vga_b}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b}]

set_property PACKAGE_PIN F3 [get_ports {vga_hs}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_hs}]

set_property PACKAGE_PIN F4 [get_ports {vga_vs}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_vs}]

set_property PACKAGE_PIN C6 [get_ports {io_button[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_button[0]}]

set_property PACKAGE_PIN C7 [get_ports {io_button[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_button[1]}]

set_property PACKAGE_PIN A7 [get_ports {io_button[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_button[2]}]

set_property PACKAGE_PIN B7 [get_ports {io_button[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_button[3]}]

set_property PACKAGE_PIN P11 [get_ports {io_button[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {io_button[4]}]

