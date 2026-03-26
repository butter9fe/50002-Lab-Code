set projDir "./vivado"
set projName "Lab05"
set topName top
set device xc7a35tftg256-1
if {[file exists "$projDir"]} { file delete -force "$projDir" }
create_project $projName "$projDir" -part $device
set_property design_mode RTL [get_filesets sources_1]
set verilogSources [list "./source/alchitry_top.sv" "./source/reset_conditioner.sv" "./source/edge_detector.sv" "./source/bit_reverse.sv" "./source/alu.sv" "./source/adder.sv" "./source/boolean.sv" "./source/compare.sv" "./source/fa.sv" "./source/rca.sv" "./source/shifter.sv" "./source/tester_manual_alu.sv" "./source/tester_manual_fsm.sv" "./source/pipeline.sv" "./source/button_conditioner.sv" "./source/mux2to1.sv" "./source/mux4to1.sv" "./source/x_bit_left_shifter.sv" "./source/left_shifter.sv" "./source/multiplier.sv" "./source/partial_product.sv" "./source/reg_en.sv" "./source/counter.sv" "./source/tester_auto_comparator.sv" "./source/tester_auto_controlunit.sv" "./source/tester_auto_datapath.sv" "./source/tester_auto_testvalues.sv" "./source/tester_auto_alu.sv" "./source/seven_segment_encoder.sv" "./source/lucid_globals.sv" ]
import_files -fileset [get_filesets sources_1] -norecurse $verilogSources
set xdcSources [list "./constraint/alchitry.xdc" "./constraint/au_props.xdc" ]
read_xdc $xdcSources
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
update_compile_order -fileset sources_1
launch_runs -runs synth_1 -jobs 24
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 24
wait_on_run impl_1
