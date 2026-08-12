# Top testbench module
TOP_MODULE = buffer_tb

# RTL files
RTL_FILES = CACHE_BLOCK\RTL\interface\buffer.sv

# Testbench file
TB_FILE = CACHE_BLOCK\testbench\buffer_tb.sv

buffer:
	verilator --binary \
	--trace \
	--top-module $(TOP_MODULE) \
	$(RTL_FILES) \
	$(TB_FILE)

run_buffer: buffer
	./obj_dir/V$(TOP_MODULE)

clean_buffer:
	rm -rf obj_dir *.vcd

TOP_INTERFACE_TB = top_l1_interface_tb
RTL_INTERFACE_FILES = CACHE_BLOCK\RTL\interface\buffer.sv\
						CACHE_BLOCK\RTL\interface\L1_interface.sv\
						CACHE_BLOCK\RTL\interface\l1_l2_top_interface.sv\
						CACHE_BLOCK\RTL\PKG\pkg.svh

TB_INTERFACE_FILE = CACHE_BLOCK\testbench\top_l1_interface_tb.sv


interface:
	verilator --binary \
	--trace \
	--top-module $(TOP_INTERFACE_TB) \
	$(RTL_INTERFACE_FILES) \
	$(TB_INTERFACE_FILE)

run_interface: interface 
	./obj_dir/V$(TOP_INTERFACE_TB)

clean_interface:
	rm -rf obj_dir *.vcd


TOP_SRRIP_TB = srrip_tb
RTL_SRRIP_FILES = CACHE_BLOCK/RTL/SRRIP/srrip_controller.sv \
						CACHE_BLOCK/RTL/PKG/pkg.svh

TB_SRRIP_FILE = CACHE_BLOCK/testbench/srrip_tb.sv

srrip:
	verilator \
    --binary \
    --trace \
    --top-module $(TOP_SRRIP_TB) \
    $(RTL_SRRIP_FILES) \
    $(TB_SRRIP_FILE) \
    $(CPP_FILES) \
    $(INC_DIRS) \
    -CFLAGS "-std=c++17 -I$(SYSTEMC_HOME)/include" \
    -LDFLAGS "$(LDFLAGS)"

run_srrip: srrip 
	./obj_dir/V$(TOP_SRRIP_TB)

clean_srrip:
	rm -rf obj_dir *.vcd
#   system c installation path
SYSTEMC_HOME = /c/SystemC/install
CPP_FILES = \
				scripts/wrapper_function/srrip_wrapper.cpp \
				scripts/golden_model/SRRIP/srrip_controller.cpp

INC_DIRS = \
    -ICACHE_BLOCK/SystemC \
    -ICACHE_BLOCK/DPI \
    -I$(SYSTEMC_HOME)/include

LDFLAGS = \
    -L$(SYSTEMC_HOME)/lib \
    -lsystemc



#  interface testbench   makefile

TOP_INTERFACE_TB = top_l1_interface_tb
RTL_INTERFACE_FILES = CACHE_BLOCK/RTL/interface/\buffer.sv\
						CACHE_BLOCK/RTL/interface/L1_interface.sv\
						CACHE_BLOCK/RTL/interface/l1_l2_top_interface.sv\
						CACHE_BLOCK/RTL/PKG/pkg.svh

TB_INTERFACE_FILE = CACHE_BLOCK/testbench/top_l1_interface_tb.sv


interface_golden_model:
	verilator \
    --binary \
    --trace \
    --top-module $(TOP_INTERFACE_TB)\
    $(RTL_INTERFACE_FILES)\
    $(TB_INTERFACE_FILE)\
    $(CPP_FILES_INTERFACE)\
    $(INC_DIRS)\
    -CFLAGS "-std=c++17 -I$(SYSTEMC_HOME)/include"\
    -LDFLAGS "$(LDFLAGS)"

run_interface_golden_model: interface_golden_model
	./obj_dir/V$(TOP_INTERFACE_TB)

clean_interface_golden_model:
	rm -rf obj_dir *.vcd

CPP_FILES_INTERFACE = \
				scripts/wrapper_function/L1_interface_wrapper.cpp \
				scripts/golden_model/interfaces/L1_interface.cpp \
				scripts/golden_model/interfaces/L1_L2_TOP_INTERFACE.cpp \
				scripts/golden_model/interfaces/L1_SIDE_BUFFER.cpp	




CACHE_TOP_TB =   cache_top_tb 

RTL_FILES_TOP = \
		$(wildcard CACHE_BLOCK/RTL/DATA_ARRAY/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/interface/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/MSHR_CONTROL_AND_TABLE/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/SRRIP/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/TAG/TAG_COMPARE/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/TAG/TAG_STORE/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/TOP/*.sv) \
		$(wildcard CACHE_BLOCK/RTL/GLOBAL_CONTROL/* .sv) \

pkg = CACHE_BLOCK/RTL/PKG/pkg.sv


TB_FILE = CACHE_BLOCK/testbench/cache_top_tb.sv

top_module:
	verilator \
    --binary \
    --trace \
	$(pkg) \
    --top-module $(CACHE_TOP_TB)\
    $(RTL_FILES_TOP)\
    $(TB_FILE)

run_cache_top: top_moule
	./obj_dir/V$(CACHE_TOP_TB)

clean_top:
	rm -rf obj_dir *.vcd


		