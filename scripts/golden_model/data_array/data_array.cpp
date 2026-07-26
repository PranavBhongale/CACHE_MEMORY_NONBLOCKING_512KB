#ifndef DATA_ARRAY_H
#define DATA_ARRAY_H

#include <systemc.h>
//==============================================================
// L2 Cache Data Array (with per-line VALID and DIRTY bits)
//
// Cache Size : 512 KB
// Line Size  : 64 Bytes (512 bits)
// Ways       : 4
// Sets       : 2048
//
// Total Lines = 2048 x 4 = 8192
//
//==============================================================
static const unsigned CACHE_SETS = 2048;
static const unsigned CACHE_WAYS = 4;
static const unsigned LINE_BITS  = 512;

SC_MODULE(data_array)
{
    // Clock / Reset
    sc_in<bool> clk;
    sc_in<bool> rst_n;     // active-low synchronous reset (clears valid/dirty)

    // Read Port
    sc_in<bool> rd_en;
    sc_in<sc_uint<11>> rd_set;
    sc_in<sc_uint<2>>  rd_way;

    sc_out<sc_biguint<LINE_BITS>> rd_data;
    sc_out<bool>                  rd_valid;
    sc_out<bool>                  rd_dirty;

    // Write Port
    sc_in<bool> wr_en;
    sc_in<sc_uint<11>> wr_set;
    sc_in<sc_uint<2>>  wr_way;

    sc_in<sc_biguint<LINE_BITS>> wr_data;
    sc_in<bool>                  wr_valid;   // new valid state to store
    sc_in<bool>                  wr_dirty;   // new dirty state to store

private:

    // Memory Array
    sc_biguint<LINE_BITS> mem[CACHE_SETS][CACHE_WAYS];
    bool                  valid[CACHE_SETS][CACHE_WAYS];
    bool                  dirty[CACHE_SETS][CACHE_WAYS];

public:
    // Read (combinational)
    void read_process()
    {
        if(rd_en.read())
        {
            unsigned s = rd_set.read().to_uint();
            unsigned w = rd_way.read().to_uint();

            rd_data.write(mem[s][w]);
            rd_valid.write(valid[s][w]);
            rd_dirty.write(dirty[s][w]);
        }
        // if rd_en == 0, outputs simply hold their previous value
    }

    // Write (synchronous, with reset)
    void write_process()
    {
        if(!rst_n.read())
        {
            // clear valid/dirty for every line on reset
            for(unsigned s=0; s<CACHE_SETS; s++)
            {
                for(unsigned w=0; w<CACHE_WAYS; w++)
                {
                    valid[s][w] = false;
                    dirty[s][w] = false;
                }
            }
            return;
        }

        if(wr_en.read())
        {
            unsigned s = wr_set.read().to_uint();
            unsigned w = wr_way.read().to_uint();

            mem[s][w]   = wr_data.read();
            valid[s][w] = wr_valid.read();
            dirty[s][w] = wr_dirty.read();
        }
    }

    // Constructor
    SC_CTOR(data_array)
    {
       
        for(unsigned s=0; s<CACHE_SETS; s++)
        {
            for(unsigned w=0; w<CACHE_WAYS; w++)
            {
                mem[s][w]   = 0;
                valid[s][w] = false;
                dirty[s][w] = false;
            }
        }

        // Combinational Read
        SC_METHOD(read_process);
        sensitive
            << rd_en
            << rd_set
            << rd_way;

        // Synchronous Write (+ reset)
        SC_METHOD(write_process);
        sensitive << clk.pos();
    }
};


#endif
