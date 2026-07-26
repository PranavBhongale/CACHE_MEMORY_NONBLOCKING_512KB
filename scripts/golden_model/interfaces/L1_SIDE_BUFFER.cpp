#pragma once
#include <systemc.h>

template<typename T, int DEPTH>
SC_MODULE(sync_fifo)
{
    sc_in<bool> clk;
    sc_in<bool> rst_n;

    // INPUT 
    sc_in<bool> in_valid;
    sc_in<T>    in_data;
    sc_out<bool> in_ready;

    // OUTPUT 
    sc_out<bool> out_valid;
    sc_out<T>    out_data;
    sc_in<bool>  out_ready;

private:

    T mem[DEPTH];

    sc_uint<32> wr_ptr;
    sc_uint<32> rd_ptr;
    sc_uint<32> count;

public:

    void fifo_proc()
    {
        if(!rst_n.read())
        {
            wr_ptr = 0;
            rd_ptr = 0;
            count  = 0;

            in_ready.write(true);
            out_valid.write(false);

            return;
        }

        bool push = in_valid.read() && (count < DEPTH);
        bool pop  = out_ready.read() && (count > 0);

        //  PUSH 

        if(push)
        {
            mem[wr_ptr] = in_data.read();
            wr_ptr++;
            if(wr_ptr == DEPTH)
                wr_ptr = 0;
        }
        //  POP 

        if(pop)
        {
            rd_ptr++;
            if(rd_ptr == DEPTH)
                rd_ptr = 0;
        }

        //  COUNT 

        if(push && !pop)
            count++;

        else if(pop && !push)
            count--;

        //  OUTPUT 

        if(count > 0)
        {
            out_valid.write(true);
            out_data.write(mem[rd_ptr]);
        }
        else
        {
            out_valid.write(false);
        }

        in_ready.write(count < DEPTH);
    }

    SC_CTOR(sync_fifo)
    {
        wr_ptr = 0;
        rd_ptr = 0;
        count  = 0;

        SC_METHOD(fifo_proc);

        sensitive << clk.pos();
    }
};
