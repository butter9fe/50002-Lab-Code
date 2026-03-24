set projDir "./vivado"
set projName "Lab04"
set topName top
set device xc7a35tftg256-1
if {[file exists "$projDir"]} { file delete -force "$projDir" }
create_project $projName "$projDir" -part $device
set_property design_mode RTL [get_filesets sources_1]
set verilogSources [list "./source/alchitry_top.sv" "./source/reset_conditioner.sv" "./source/counter.sv" "./source/full_adder.sv" "./source/rca.sv" "./source/registered_rca.sv" "./source/reg_en.sv" "./source/registered_rca_en.sv" "./source/simple_fsm.sv" "./source/edge_detector.sv" "./source/pipeline.sv" "./source/button_conditioner.sv" "./source/rca_tester_datapath.sv" "./source/rca_tester_controlunit.sv" "./source/rca_tester_testvalues.sv" "./source/rca_tester_comparator.sv" "./source/seven_segment_encoder.sv" "./source/lucid_globals.sv" ]
import_files -fileset [get_filesets sources_1] -norecurse $verilogSources
set xdcSources [list "./constraint/alchitry.xdc" "./constraint/au_props.xdc" ]
read_xdc $xdcSources
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE true [get_runs impl_1]
update_compile_order -fileset sources_1
launch_runs -runs synth_1 -jobs 24
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 24
wait_on_run impl_1
