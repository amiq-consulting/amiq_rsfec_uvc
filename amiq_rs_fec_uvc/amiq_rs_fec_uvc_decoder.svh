// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Decoder
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_DECODER
`define __AMIQ_RS_FEC_UVC_DECODER

/* Decoder class, extends the uvc base which contains all the GF logic.
 * This component is capable of error detection and correction. */
class amiq_rs_fec_uvc_decoder extends amiq_rs_fec_uvc_base;

    `uvm_component_utils(amiq_rs_fec_uvc_decoder)

    `uvm_analysis_imp_decl(_erasure_ap)

    // The port through which the decoder receives erasure items
    uvm_analysis_imp_erasure_ap #(amiq_rs_fec_uvc_erasure_item, amiq_rs_fec_uvc_decoder) erasure_ap;

    // Erasure item containing the erasure positions in the codeword
    amiq_rs_fec_uvc_erasure_item erasure_item;
    // An erasure item queue
    amiq_rs_fec_uvc_erasure_item eras_item_q[$];

    function new(string name = "amiq_rs_fec_uvc_decoder", uvm_component parent);
        super.new(name, parent);
        input_ap = new("input_ap", this);
        output_ap = new("output_ap", this);
    endfunction : new

    // Set the erasure item with default values (meaning - empty erasure item)
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        erasure_ap = new("erasure_ap", this);

        // Create an initial empty erasure item just in case, we don't want random values at the beginning before the first erasure item
        erasure_item = amiq_rs_fec_uvc_erasure_item::type_id::create("erasure_item");

    endfunction : build_phase

    // The decoder receives an erasure item and saves its copy
    function void write_erasure_ap(amiq_rs_fec_uvc_erasure_item item);
        amiq_rs_fec_uvc_erasure_item clone;
        if (!$cast(clone, item.clone())) begin
            `uvm_fatal(get_full_name(), "Failed casting!")
        end
        eras_item_q.push_back(clone);
    endfunction

    // Run phase where the decoder unpacks received codewords and decodes them
    extern task run_phase(uvm_phase phase);

endclass

task amiq_rs_fec_uvc_decoder::run_phase(uvm_phase phase);
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

                    // This variable holds the result of the decoding: -1 if the codeword is uncorrectable, or the number of errors corrected
                    int nof_errors = 0;

                    // If erasures are enabled, pop an item from the queue, else use the default empty one
                    if ((uvc_config.simulate_channel_erasures == 1) && (uvc_config.enable_error_injector)) begin
                        AMIQ_DECODER_MISSING_ERASURES_CHECK : if (eras_item_q.size() == 0)
                            `uvm_fatal(get_full_name(), "Erasure item queue empty in decoder!")

                        erasure_item = eras_item_q.pop_front();
                    end

                    if (dec_item.size == 0)
                        `uvm_fatal(get_full_name(), "Decoder got empty item!")

                    // Check if the received item has the minimum number of symbols: 1 data sym + the parity symbols
                    if (((dec_item.size * 8) / uvc_config.symbol_size) < (1 + uvc_config.nof_parity_symbols)) begin
                        `uvm_fatal(get_full_name(), "Decoder didn't get enough symbols!")
                    end

                    if (reset == 0) begin
                        amiq_rs_fec_uvc_item dec_output_item = amiq_rs_fec_uvc_item::type_id::create("enc_output_item");
                        int unsigned codeword_q[$];
                        int unsigned corrected_codeword[];
                        int unsigned symbol_array[];
                        int unsigned nof_codewords = 0;
                        // Used to know where to start extracting symbols
                        int unsigned current_index = 0;
                        int unsigned sym_array_size = 0;

                        // Unpack all the symbols from the input item in this array
                        symbol_array = dec_item.unpack_symbols(uvc_config.symbol_size);
                        sym_array_size = symbol_array.size();
                        // Calculate the number of codewords
                        nof_codewords = sym_array_size / uvc_config.codeword_length;

                        /* sym_array_size % env_config.codeword_length gives us how many symbols are at the end
                         * we will increment nof_codewords ONLY if we have enough extra symbols for another (short) codeword
                         * minimum symbols needed: 1 data sym + the parity symbols
                         */
                        nof_codewords += ((sym_array_size % uvc_config.codeword_length) >= (1 + uvc_config.nof_parity_symbols));

                        for (int i = 0; i < nof_codewords; i++) begin

                            // Prepare the codeword buffer, this will contain symbols to form one codeword
                            codeword_q.delete();

                            // If we have enough symbols for a whole codeword, push back the next (codeword_length) symbols
                            if ((current_index + uvc_config.codeword_length) <= sym_array_size) begin
                                for (int j = current_index; j < (current_index + uvc_config.codeword_length); j++) begin
                                    if ((j < sym_array_size) && (j >= 0))
                                        codeword_q.push_back(symbol_array[j]);
                                end
                                current_index += uvc_config.codeword_length;
                            end else begin
                                // If we have a short codeword, push back all the symbols that are left
                                while (current_index < sym_array_size) begin
                                    if ((current_index < sym_array_size) && (current_index >= 0)) begin
                                        codeword_q.push_back(symbol_array[current_index]);
                                        current_index++;
                                    end
                                end
                            end

                            // Decode the codeword only if it has the minimum number of symbols: 1 data sym + the parity symbols
                            if (codeword_q.size() >= (1 + uvc_config.nof_parity_symbols)) begin

                                if (uvc_config.allow_padding == 0) begin
                                    AMIQ_DECODER_PADDING_CHECK : if (codeword_q.size() != uvc_config.codeword_length)
                                        `uvm_fatal(get_full_name(), "Short codewords not allowed!")
                                end

                                if (erasure_item.nof_erasures > 0) begin
                                    nof_errors = decode(codeword_q, uvc_config.symbol_size, corrected_codeword, uvc_config.nof_parity_symbols,
                                        gf_log, gf_exp, erasure_item.erasure_positions_q, uvc_config.fcr, uvc_config.generator);
                                end else begin
                                    nof_errors = decode(codeword_q, uvc_config.symbol_size, corrected_codeword, uvc_config.nof_parity_symbols,
                                        gf_log, gf_exp, {}, uvc_config.fcr, uvc_config.generator);
                                end

                                if (nof_errors == -1) begin
                                    dec_output_item.set_decoding_parameters(0, 0, 1);
                                end else begin
                                    dec_output_item.set_decoding_parameters(1, nof_errors, 0);
                                end

                                dec_output_item.pack_symbols(corrected_codeword, uvc_config.symbol_size);

                                output_ap.write(dec_output_item);
                                uvm_wait_for_nba_region();
                            end
                        end
                    end
                end
            end

            begin
                wait (reset == 1);
                if (p_dec) begin
                    p_dec.kill();
                    input_item_q = {};
                    eras_item_q = {};
                    erasure_item.set_erasures({});
                end
                reset = 0;
            end
        join
    end
endtask : run_phase

`endif  // __AMIQ_RS_FEC_UVC_DECODER
