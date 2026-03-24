set projDir "./vivado"
set projName "DOOM 1"
set topName top
set device xc7a35tftg256-1
if {[file exists "$projDir"]} { file delete -force "$projDir" }
create_project $projName "$projDir" -part $device
set_property design_mode RTL [get_filesets sources_1]
set verilogSources [list "./source/alchitry_top.sv" "./source/picorv32.v" "./source/picorv32_soc.v" "./source/bram.v" "./source/ddr3_cache.v" "./source/simple_dual_port_ram.v" "./source/fifo.sv" "./source/simpleuart.v" "./source/pipeline.sv" "./source/ddr_arbiter.sv" "./source/mig_wrapper.sv" "./source/button_conditioner.sv" "./source/edge_detector.sv" "./source/lucid_globals.sv" "./../cores/clk_wiz_0/clk_wiz_0.xci" "./../cores/mig_7series_0/mig_7series_0.xci" ]
import_files -fileset [get_filesets sources_1] -norecurse $verilogSources
set xdcSources [list "./constraint/alchitry.xdc" "./constraint/au_props.xdc" ]
read_xdc $xdcSources
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
update_compile_order -fileset sources_1
launch_runs -runs synth_1 -jobs 24
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 24
wait_on_run impl_1
