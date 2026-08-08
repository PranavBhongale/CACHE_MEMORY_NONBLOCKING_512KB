##  project tree to understand what is FILE STRUCTURE 
this will give clear idea of what file is where

```
 |---DCACHE_NONBLOCKING / 
 |              |
 |              |---- .sigasi //  this is for sigasi studio
 |              |
 |              |---- build //  this  folder for CMAKE   run CMAKE command in this folder not from the project
 |              |           //  to compile the SystemC  we need cmake and to perform performance modeling
 |              |
 |              |----doccument /
 |              |           |
 |              |           |---drawings/
 |              |           |       |---cache_black_box.drawio.png
 |              |           |       |---cache_connection_to_cpu.drawio.png  
 |              |           |       |---cache_internal_design.drawio.png
 |              |           |       |---combined_cache_design_and_performance_modeling.pdf  // this  is the fast view of 
 |              |           |       |    //  project the ideas and architectural drawings
 |              |           |       |
 |              |           |
 |              |           |---information/     
 |              |           |       |---cache_structure.md  // this file is empty woking on it 
 |              |           |       |---detail project_information.pdf // working on it 
 |              |      
 |              |
 |              |
 |              |----CACHE_BLOCK /
 |              |           |
 |              |           |---RTL/
 |              |           |   |       
 |              |           |   |---DATA_ARRAY /
 |              |           |   |       |---data_array.sv
 |              |           |   |
 |              |           |   |---GLOBAL_CONTROL /
 |              |           |   |       |--- i am working on this 
 |              |           |   |
 |              |           |   |
 |              |           |   |---interfaces /
 |              |           |   |           |
 |              |           |   |           |---buffer.sv
 |              |           |   |           |---interface.md
 |              |           |   |           |---L1_interface.sv
 |              |           |   |           |---l1_l2_top_interface.sv
 |              |           |   |           |---LLC_interface.sv
 |              |           |   |
 |              |           |   |
 |              |           |   |---MSHR_CONTROL_AND_TABLE/
 |              |           |   |           |---MSHR_CONTROL_AND_TABLE.sv // THIS IS NOT COMPLITED I AM WORKING
 |              |           |   |
 |              |           |   |---PKG/
 |              |           |   |   |     
 |              |           |   |   |---pkg.svh
 |              |           |   |   |
 |              |           |   |---SRRIP/
 |              |           |   |       |---srrip_controller.sv
 |              |           |   |
 |              |           |   |---TAG/
 |              |           |   |   |
 |              |           |   |   |---TAG_COMPARE/
 |              |           |   |   |           |---tag_compare.sv
 |              |           |   |   |---TAG_STORE/
 |              |           |   |   |           |---tag_memory.sv
 |              |           |   |   |
 |              |           |   |   |
 |              |           |   |   |
 |              |           |   |
 |              |           |   |---TOP /
 |              |           |   |     |---  TOP FILE IS NOT READY I AM WORKING ON IT 
 |              |           |   |
 |              |           |   |--- information.md
 |              |           |   |
 |              |           |   |
 |              |           |
 |              |           |---testbench /
 |              |           |         |
 |              |           |         |---buffer_tb.sv
 |              |           |         |
 |              |           |         |---srrip_tb.sv
 |              |           |         |
 |              |           |         |---top_l1_interface_tb.sv // verification is not completed yet
 |              |           |         |
 |              |           |         |   
 |              |           |         |---  more files will added in future as project grows
 |              |    
 |              |
 |              |---scripts/
 |              |       |
 |              |       |---golden_model
 |              |       |           |
 |              |       |           |---data_array/
 |              |       |           |           |---data_array.cpp
 |              |       |           |---GLOBAL_CONTROL/
 |              |       |           |           |---global_control_interface.cpp
 |              |       |           |           |---global_control.cpp
 |              |       |           |---interface/
 |              |       |           |           |---L1_interface.cpp
 |              |       |           |           |---l1_l2_TOP_INTERFACE.cpp
 |              |       |           |           |---L1_SIDE_BUFFER.cpp
 |              |       |           |           |---LLC_interface.cpp
 |              |       |           |
 |              |       |           |---MSHR_CONTROL_AND_TABLES/
 |              |       |           |               |---mshr_table_interface.h
 |              |       |           |               |---mshr_table.cpp
 |              |       |           |---SRRIP/
 |              |       |           |       |--- srrip_controller_interface.h
 |              |       |           |       |---srrip_controler.cpp
 |              |       |           |---tag_compare
 |              |       |           |           |---tag_compare_top.h
 |              |       |           |           |---tag_compare.cpp
 |              |       |           |           |
 |              |       |           |---tag_operation/
 |              |       |           |           |---tag_memory_function.cpp
 |              |       |           |           |---tag_memory.h
 |              |       |           |---top/
 |              |       |           |    l2_cache_top.cpp
 |              |       |           |
 |              |       |           |---REPORT.md
 |              |       |           |
 |              |       |
 |              |       |---l2_cache_perf_modeling/
 |              |       |               |
 |              |       |               |---src/
 |              |       |               |   |---gnuplot_stream.h
 |              |       |               |   |---perf_monitor.h
 |              |       |               |   |---tb_l2_cache_top.cpp
 |              |       |               |   |---test_perf_monitor.cpp
 |              |       |               | 
 |              |       |               |---README.md
 |              |       |
 |              |       |---wrapper_function/
 |              |       |               |
 |              |       |               |---L1_interface_wrapper.cpp // working on it 
 |              |       |               |---srrip_wrapper.cpp // completed verification of SRRIP 
 |              |       |     
 |              |       |              
 |              |---waveforms
 |              |       |
 |              |       |  ---  till now there is no any file i will add as verification goes 
 |              |
 |              |
 |              |---CMakeLists.txt  //  all cmake commant are written here
 |              |
 |              |--- makefile   // important 
 |              |
 |              |--- README.MD   // first need to read this 
 |
 ```


