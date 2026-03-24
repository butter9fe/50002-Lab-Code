set_property SRC_FILE_INFO {cfile:{/home/stardust/Sharedspace/School/Term 4/Computational structures/DOOM 1/cores/clk_wiz_0/clk_wiz_0.xdc} rfile:../../../../clk_wiz_0/clk_wiz_0.xdc id:1 order:EARLY scoped_inst:inst} [current_design]
current_instance inst
set_property src_info {type:SCOPED_XDC file:1 line:54 export:INPUT save:INPUT read:READ} [current_design]
set_input_jitter [get_clocks -of_objects [get_ports clk_in]] 0.100
