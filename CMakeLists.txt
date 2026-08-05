cmake_minimum_required(VERSION 3.16)
project(DCACHE_NONBLOCKING CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(DEFINED ENV{SYSTEMC_HOME} AND NOT DEFINED SystemC_ROOT)
    set(SystemC_ROOT "$ENV{SYSTEMC_HOME}")
endif()
set(SystemC_ROOT "${SystemC_ROOT}" CACHE PATH "Path to SystemC install prefix")
if(NOT SystemC_ROOT)
    set(SystemC_ROOT "C:/SystemC/install")
endif()

find_path(SystemC_INCLUDE_DIR NAMES systemc.h PATHS "${SystemC_ROOT}/include")
find_library(SystemC_LIBRARY NAMES systemc SystemC PATHS "${SystemC_ROOT}/lib")

if(NOT SystemC_INCLUDE_DIR OR NOT SystemC_LIBRARY)
    message(FATAL_ERROR "SystemC not found under '${SystemC_ROOT}'.")
endif()

add_library(SystemC::systemc UNKNOWN IMPORTED)
set_target_properties(SystemC::systemc PROPERTIES
    IMPORTED_LOCATION "${SystemC_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${SystemC_INCLUDE_DIR}"
)
add_executable(DCACHE_NONBLOCKING
    scripts/l2_cache_perf_modeling/src/tb_l2_cache_top.cpp
)

target_include_directories(DCACHE_NONBLOCKING PRIVATE
    ${CMAKE_SOURCE_DIR}/cache_memory
    ${CMAKE_SOURCE_DIR}/scripts
    ${CMAKE_SOURCE_DIR}/information
)

target_link_libraries(DCACHE_NONBLOCKING PRIVATE SystemC::systemc)

if(WIN32)
    target_link_libraries(DCACHE_NONBLOCKING PRIVATE
        kernel32 user32 gdi32 winspool shell32 ole32 oleaut32 uuid comdlg32 advapi32
    )
endif()