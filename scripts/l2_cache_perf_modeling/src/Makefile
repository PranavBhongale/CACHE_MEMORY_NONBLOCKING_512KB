# Point this at your SystemC install (the dir containing include/ and lib-linux64/).
SYSTEMC_HOME ?= /usr/local/systemc

CXX      = g++
CXXFLAGS = -std=c++17 -O2 -Wall -Wno-unused-parameter -I$(SYSTEMC_HOME)/include -I. -pthread
LDFLAGS  = -L$(SYSTEMC_HOME)/lib-linux64 -lsystemc -lm -pthread \
           -Wl,-rpath,$(SYSTEMC_HOME)/lib-linux64

TARGET = tb_l2_cache
SRC    = tb_l2_cache_top.cpp

.PHONY: all run clean test_perf_monitor

all: $(TARGET)

$(TARGET): $(SRC) perf_monitor.h gnuplot_stream.h
	$(CXX) $(CXXFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

run: $(TARGET)
	./$(TARGET)

# Standalone unit test for perf_monitor.h -- no SystemC needed, no DUT
# needed. Good first thing to run after cloning to confirm your toolchain
# works before dealing with the SystemC build.
test_perf_monitor: test_perf_monitor.cpp perf_monitor.h
	$(CXX) -std=c++17 -O2 -Wall -Wextra test_perf_monitor.cpp -o test_perf_monitor
	./test_perf_monitor

clean:
	rm -f $(TARGET) test_perf_monitor