# ===========================================================================
# build_submission.tcl - TD batch build for the submission UI
# Target: SC520CS-compatible MIPI input, 1280x720 HDMI output
# Note: the current camera register table is the official SC500CS 720p table.
# Replace the uics500_cfg table after confirming the SC520CS datasheet.
# ===========================================================================

import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project hx1p35a_sc520cs_vision_ui.al -single_run

puts {==== step 1/6: read_design ====}
elaborate -top design_top_wrapper
read_adc ../user_source/constraints_source/pin.adc
read_sdc hx1p35a_sc520cs_image_system.sdc
read_ip_adc -ip ddr2 -file ../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc
read_ip_adc -ip ddr2 -file ../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc

puts {==== step 2/6: optimize_rtl ====}
insert_debugger
optimize_rtl
report_area -file report_vision_ui_rtl.area

puts {==== step 3/6: optimize_gate ====}
optimize_gate
legalize_phy_inst
update_timing
report_timing_summary -file report_vision_ui_gate.timing

puts {==== step 4/6: place ====}
place
update_timing -mode manhattan
report_timing_summary -file report_vision_ui_place.timing

puts {==== step 5/6: route ====}
route
update_timing -mode final
report_timing_summary -file report_vision_ui_route.timing
report_qor -step route -file report_vision_ui_qor.txt

puts {==== step 6/6: bitgen ====}
bitgen -bit hx1p35a_sc520cs_submission_pc_image_20261025.bit

puts {}
puts "=========== BUILD DONE ==========="
puts "Bitstream: hx1p35a_sc520cs_submission_pc_image_20261025.bit"
exit

