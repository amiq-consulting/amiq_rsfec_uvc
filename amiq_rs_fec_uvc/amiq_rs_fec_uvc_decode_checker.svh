// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Decode Checker
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     26.03.2025
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_DECODE_CHECKER
`define __AMIQ_RS_FEC_UVC_DECODE_CHECKER


// This component receives noisy data and 3 parameters from an RTL, decodes the data and checks that the parameters are correct
class amiq_rs_fec_uvc_decode_checker extends amiq_rs_fec_uvc_base;

    `uvm_component_utils(amiq_rs_fec_uvc_decode_checker)

    function new(string name = "amiq_rs_fec_uvc_decode_checker", uvm_component parent);
        super.new(name, parent);
        input_ap = new("input_ap", this);
    endfunction : new

    // Run phase where the decoder unpacks received codewords and decodes them
    extern task run_phase(uvm_phase phase);

endclass

task amiq_rs_fec_uvc_decode_checker::run_phase(uvm_phase phase);
    // Process variable used to kill item processing when reset comes
    process p_dec;

    super.run_phase(phase);

    forever begin
        fork
            forever begin : decoding_thread

                p_dec = process::self();

                // Wait for the item queue to have items
                wait (input_item_q.size() != 0); begin


                    amiq_rs_fec_uvc_item dec_item = input_item_q.pop_front();

                    int unsigned corrected_codeword[];
                    int unsigned codeword_q[$];

                    // This variable holds the result of the decoding: -1 if the codeword is uncorrectable, or the number of errors corrected
                    int nof_errors = 0;

                    if (dec_item.size > 0) begin

                        // Check if the received item has the minimum number of symbols: 1 data sym + the parity symbols
                        if (((dec_item.size * 8) / uvc_config.symbol_size) < (1 + uvc_config.nof_parity_symbols)) begin
                            `uvm_fatal(get_full_name(), "Decode checker didn't get enough symbols!")
                        end

                        if (reset == 0) begin

                            codeword_q = dec_item.unpack_symbols(uvc_config.symbol_size);

                            nof_errors = decode(codeword_q[0:(uvc_config.codeword_length - 1)], uvc_config.symbol_size, corrected_codeword,
                                uvc_config.nof_parity_symbols, gf_log, gf_exp);

                            if (nof_errors == -1) begin

                                AMIQ_DECODE_UNCORRECTABLE_MISMATCH_CHECK : if (!((dec_item.corrected == 0) && (dec_item.nof_corrected_errors == 0) &&
                                    (dec_item.uncorrectable == 1))) begin
                                    string error = "The provided parameters (corrected_cw, number_of_errors_corrected, uncorrectable_cw) are wrong!\
                            \nThey should be 0, 0, 1, but instead they are: %0b %0d %0b";
                                    `uvm_fatal(get_full_name(), $sformatf(error, dec_item.corrected, dec_item.nof_corrected_errors, dec_item.uncorrectable))
                                end

                            end else begin

                                AMIQ_DECODE_CORRECTED_MISMATCH_CHECK : if (!((dec_item.corrected == 1) && (dec_item.nof_corrected_errors == nof_errors) &&
                                    (dec_item.uncorrectable == 0))) begin

                                    string error = "The provided parameters (corrected_cw, number_of_errors_corrected, uncorrectable_cw) are wrong!\
                            \nThey should be 1, %0d, 0, but instead they are: %0b, %0d, %0b";

                                    `uvm_fatal(get_full_name(), $sformatf(error,
                                            nof_errors, dec_item.corrected, dec_item.nof_corrected_errors, dec_item.uncorrectable))
                                end
                            end

                            corrected_codeword = {};

                        end
                    end else
                        `uvm_fatal(get_full_name(), "Decode checker got empty item!")
                end
            end

            begin
                wait (reset == 1);
                if (p_dec) begin
                    p_dec.kill();
                    input_item_q = {};
                end
                reset = 0;
            end
        join
    end
endtask : run_phase

`endif  // __AMIQ_RS_FEC_UVC_DECODE_CHECKER
