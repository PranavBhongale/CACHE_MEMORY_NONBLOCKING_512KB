#pragma once
#include <systemc.h>
#include "L1_interface.cpp"
#include "L1_SIDE_BUFFER.cpp"


template<int REQ_DEPTH = MSHR_ENTRIES, int RESP_DEPTH = MSHR_ENTRIES>
SC_MODULE(l1_l2_top) {
    sc_in<bool> clk;
    sc_in<bool> rst_n;

    // L1I client port (pass-through to the arbiter)
    sc_in<l2_req_t>   i_req;
    sc_out<bool>      i_req_ready;
    sc_out<l2_resp_t> i_resp;
    sc_in<bool>       i_resp_ready;

    //  L1D client port (pass-through to the arbiter) 
    sc_in<l2_req_t>   d_req;
    sc_out<bool>      d_req_ready;
    sc_out<l2_resp_t> d_resp;
    sc_in<bool>       d_resp_ready;

    //  L2-facing port: this is the buffered interface to L2
    sc_out<bool>         l2_req_valid;
    sc_out<l2_if_req_t>  l2_req;
    sc_in<bool>          l2_req_ready;

    sc_in<bool>          l2_resp_valid;
    sc_in<l2_if_resp_t>  l2_resp;
    sc_out<bool>         l2_resp_ready;

    //  Submodules 
    l1_l2_arbiter*             arb;
    sync_fifo<l2_if_req_t,  REQ_DEPTH>*  req_fifo;
    sync_fifo<l2_if_resp_t, RESP_DEPTH>* resp_fifo;

    //  Internal glue signals: arbiter <-> req_fifo (in side)
    sc_signal<bool>         arb2fifo_req_valid;
    sc_signal<l2_if_req_t>  arb2fifo_req_data;
    sc_signal<bool>         fifo2arb_req_ready;

    //  Internal glue signals: resp_fifo (out side) <-> arbiter 
    sc_signal<bool>          fifo2arb_resp_valid;
    sc_signal<l2_if_resp_t>  fifo2arb_resp_data;
    sc_signal<bool>          arb2fifo_resp_ready;

    void build() {
        arb = new l1_l2_arbiter("arb");
        arb->clk(clk);
        arb->rst_n(rst_n);

        // L1I / L1D ports pass straight through to the arbiter.
        arb->i_req(i_req);
        arb->i_req_ready(i_req_ready);
        arb->i_resp(i_resp);
        arb->i_resp_ready(i_resp_ready);

        arb->d_req(d_req);
        arb->d_req_ready(d_req_ready);
        arb->d_resp(d_resp);
        arb->d_resp_ready(d_resp_ready);

        // Arbiter's L2-facing request output -> req_fifo input side.
        arb->l2_req_valid(arb2fifo_req_valid);
        arb->l2_req(arb2fifo_req_data);
        arb->l2_req_ready(fifo2arb_req_ready);

        // Arbiter's L2-facing response input <- resp_fifo output side.
        arb->l2_resp_valid(fifo2arb_resp_valid);
        arb->l2_resp(fifo2arb_resp_data);
        arb->l2_resp_ready(arb2fifo_resp_ready);

        //  Request-path buffer: arbiter -> L2
        req_fifo = new sync_fifo<l2_if_req_t, REQ_DEPTH>("req_fifo");
        req_fifo->clk(clk);
        req_fifo->rst_n(rst_n);

        req_fifo->in_valid(arb2fifo_req_valid);
        req_fifo->in_data(arb2fifo_req_data);
        req_fifo->in_ready(fifo2arb_req_ready);

        req_fifo->out_valid(l2_req_valid);
        req_fifo->out_data(l2_req);
        req_fifo->out_ready(l2_req_ready);   // driven by L2, outside this module

        //  Response-path buffer: L2 -> arbiter
        resp_fifo = new sync_fifo<l2_if_resp_t, RESP_DEPTH>("resp_fifo");
        resp_fifo->clk(clk);
        resp_fifo->rst_n(rst_n);

        resp_fifo->in_valid(l2_resp_valid);  // driven by L2, outside this module
        resp_fifo->in_data(l2_resp);
        resp_fifo->in_ready(l2_resp_ready);

        resp_fifo->out_valid(fifo2arb_resp_valid);
        resp_fifo->out_data(fifo2arb_resp_data);
        resp_fifo->out_ready(arb2fifo_resp_ready);
    }

    SC_CTOR(l1_l2_top) : arb(nullptr), req_fifo(nullptr), resp_fifo(nullptr) {
        build();
    }

    ~l1_l2_top() {
        delete arb;
        delete req_fifo;
        delete resp_fifo;
    }
};

