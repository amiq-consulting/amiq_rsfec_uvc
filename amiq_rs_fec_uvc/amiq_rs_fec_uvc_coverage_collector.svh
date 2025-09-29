// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Coverage Collector
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_COVERAGE_COLLECTOR
`define __AMIQ_RS_FEC_UVC_COVERAGE_COLLECTOR

// The component which collects encoder and decoder coverage
class amiq_rs_fec_uvc_coverage_collector extends uvm_component;

    `uvm_component_utils(amiq_rs_fec_uvc_coverage_collector)

    `uvm_analysis_imp_decl(_encoder_input)
    `uvm_analysis_imp_decl(_encoder_output)

    `uvm_analysis_imp_decl(_decoder_input)
    `uvm_analysis_imp_decl(_decoder_output)

    `uvm_analysis_imp_decl(_erasure_ap)
    `uvm_analysis_imp_decl(_reset_ap)

    // The port through which the CC receives input from the encoder
    uvm_analysis_imp_encoder_input#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_coverage_collector) encoder_in_ap;
    // The port through which the CC receives output from the encoder
    uvm_analysis_imp_encoder_output#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_coverage_collector) encoder_out_ap;

    // The port through which the CC receives input from the decoder
    uvm_analysis_imp_decoder_input#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_coverage_collector) decoder_in_ap;
    // The port through which the CC receives output from the decoder
    uvm_analysis_imp_decoder_output#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_coverage_collector) decoder_out_ap;

    // The port for receiving erasure items
    uvm_analysis_imp_erasure_ap#(amiq_rs_fec_uvc_erasure_item, amiq_rs_fec_uvc_coverage_collector) erasure_ap;
    // The port for receiving reset
    uvm_analysis_imp_reset_ap#(bit, amiq_rs_fec_uvc_coverage_collector) reset_ap;

    // Get the uvc config object to check the UVC mode
    amiq_rs_fec_uvc_config_obj uvc_config;

    // The number of codewords recovered during a test by the decoder
    int unsigned nof_recovered_codewords = 0;
    // The total number of codewords that passed through the decoder
    int unsigned total_codewords = 0;
    // The number of codewords which had erasures
    int unsigned nof_cws_with_eras = 0;

    // Set this value as -1 so that the first error injector mode can be sampled correctly
    int error_injector_mode = -1;

    // Save the current configuration to know when it changes
    amiq_rs_fec_uvc_configuration current_config;
    // Set this value as -1 so that we can sample the first configuration
    int prev_config = -1;

    // Save the current codeword length to see if it changes durign the test
    int unsigned current_codeword_length = 0;
    // Save the number of data symbols to see if it changes during the test
    int unsigned current_nof_data_sym = 0;
    // Save the number of parity symbols to see if it changes
    int unsigned current_nof_parity_sym = 0;

    // This bit tells us whether the codeword length changed during a test
    bit cw_len_changed = 0;
    // Whether the number of parity symbols changed during a test
    bit nof_parity_changed = 0;
    // Whether the number of data symbols changed during a test
    bit nof_data_changed = 0;

    // Used to store encoder output items for comparing with the decoder input ones
    amiq_rs_fec_uvc_item encoder_output_q[$];
    // Used to store decoder input items for the decoder_output_cg
    amiq_rs_fec_uvc_item decoder_input_q[$];
    // Used to know the original codewords
    amiq_rs_fec_uvc_item enc_out_for_error_coverage_q[$];
    // Used to know how many erasures there are in a codeword
    amiq_rs_fec_uvc_erasure_item erasure_item;


    // Used to sample decoder_output_cg
    amiq_rs_fec_uvc_item current_enc_out_item;
    // Used to sample decoder_output_cg
    amiq_rs_fec_uvc_item current_dec_in_item;
    // Used for gathering decoder output error correction coverage, the encoder out item symbols will be extracted in this array
    int unsigned current_enc_out_symbols[] = {};
    // Used for gathering decoder output error correction coverage, the decoder in item symbols will be extracted in this array
    int unsigned current_dec_in_symbols[] = {};

    // Used to know where to start extracting symbols in write_decoder_output
    int unsigned current_index = 0;

    // In write_decoder_output, this will be the size of the symbol arrays for the encoder input and decoder input items
    int unsigned sym_array_size = 0;

    // Coverage for the codeword configuration: codeword length, number of parity symbols, number of data symbols
    covergroup codeword_config_cg with function sample(amiq_rs_fec_uvc_configuration cw_config);
        option.per_instance = 1;
        codeword_config_cp : coverpoint cw_config {
            bins rs_255_223 = {RS_255_223};
            bins rs_208_192 = {RS_208_192};
            bins rs_255_239 = {RS_255_239};
            bins rs_528_514 = {RS_528_514};
            bins rs_544_514 = {RS_544_514};
            bins codeword_type_transition[] = (RS_255_223, RS_208_192, RS_255_239, RS_528_514, RS_544_514 =>
                RS_255_223, RS_208_192, RS_255_239, RS_528_514, RS_544_514);
        }
    endgroup : codeword_config_cg

    // Coverage on the differences between encoder output and decoder input
    covergroup encoder_output_decoder_input_cg with function sample(int unsigned percent, int unsigned nof_different_symbols);
        option.per_instance = 1;
        percent_of_erasures_per_word_cp : coverpoint percent {
            bins all[6] = {[0:100]};
        }
        nof_different_symbols_cp : coverpoint nof_different_symbols {
            bins zero = {0};
            bins one = {1};
            bins quarter = {2};
            bins half = {3};
        }
    endgroup : encoder_output_decoder_input_cg

    // Cover whether the configuration changed and which parameters changed
    covergroup configuration_change_cg with function sample(bit cw_len, bit parity, bit data);
        option.per_instance = 1;
        codeword_length_changed_cp : coverpoint cw_len {
            bins yes = {1};
            bins no = {0};
        }
        nof_parity_symbols_changed_cp : coverpoint parity {
            bins yes = {1};
            bins no = {0};
        }
        nof_data_symbols_changed_cp : coverpoint data {
            bins yes = {1};
            bins no = {0};
        }
        config_change_cross : cross codeword_length_changed_cp, nof_parity_symbols_changed_cp, nof_data_symbols_changed_cp;
    endgroup : configuration_change_cg

    // Error injector mode coverage
    covergroup error_inj_mode_cg with function sample(amiq_rs_fec_error_injector_mode mode);
        option.per_instance = 1;
        error_inj_mode_cp : coverpoint mode {
            bins error_number_mode = {ERROR_NUMBER_MODE};
            bins codeword_status_mode = {CODEWORD_STATUS_MODE};
            bins error_freq_mode = {ERROR_FREQ_MODE};
            bins only_erasures_mode = {ONLY_ERASURES_MODE};
            bins user_defined_erasures_mode = {USER_DEFINED_ERASURES_MODE};
        }
    endgroup

    // Cover the number of codewords and symbols in the encoder's input
    covergroup encoder_input_cg() with function sample(int unsigned nof_codewords, int unsigned percent);
        option.per_instance = 1;
        nof_codewords_in_enc_input_cp : coverpoint nof_codewords {
            bins one = {1};
            bins middle[5] = {[2:20]};
            bins many[8] = {[21:100]};
            bins very_many[10] = {[101:200]};
        }
        percent_of_missing_data_symbols_cp : coverpoint percent {
            bins all[6] = {[0:100]};
        }
    endgroup : encoder_input_cg

    // Cover the number of codewords and symbols in the encoder's output
    covergroup encoder_output_cg() with function sample(int unsigned nof_codewords);
        option.per_instance = 1;
        nof_codewords_in_enc_output_cp : coverpoint nof_codewords {
            bins one = {1};
            bins middle[5] = {[2:20]};
            bins many[8] = {[21:100]};
            bins very_many[10] = {[101:200]};
        }
    endgroup : encoder_output_cg

    // Cover the number of codewords in the decoder's input
    covergroup decoder_input_cg() with function sample(int unsigned nof_codewords, int unsigned percent);
        option.per_instance = 1;
        nof_codewords_in_dec_input_cp : coverpoint nof_codewords {
            bins one = {1};
            bins middle[5] = {[2:20]};
            bins many[8] = {[21:100]};
            bins very_many[10] = {[101:200]};
        }
        percent_of_missing_data_symbols_cp : coverpoint percent {
            bins all[6] = {[0:100]};
        }
    endgroup : decoder_input_cg

    // Error correction and detection coverage
    covergroup decoder_output_cg() with function sample(int unsigned codeword_type, int corrected_symbol_position,
            int unsigned nof_corrected_bits, int unsigned nof_corrected_symbols);
        option.per_instance = 1;
        returned_codeword_type_cp : coverpoint codeword_type {
            bins corrected = {0};
            bins uncorrectable = {1};
            bins error_free = {2};
            bins false_corrected = {3};
            bins false_error_free = {4};
            bins codeword_type_transition[] = (0, 1, 2, 3, 4 => 0, 1, 2, 3, 4);
        }
        corrected_symbol_position_cp : coverpoint corrected_symbol_position {
            bins byte_symbols[] = {[0:254]};
            bins ten_bit_symbols_1[5] = {[255:543]};
            bins ten_bit_symbols_2[5] = {[544:(2**10) - 2]};
        }
        nof_corrected_bits_cp : coverpoint nof_corrected_bits {
            bins low[5] = {[0:20]};
            bins med[8] = {[21:100]};
            bins high[6] = {[101:160]};
            bins ten_bit_symbols[5] = {[161:240]};
        }
        nof_corrected_symbols_cp : coverpoint nof_corrected_symbols {
            bins all[] = {[1:16]};
        }
    endgroup : decoder_output_cg

    // Percent of codewords with erasures and recovered codewords
    covergroup decoder_end_of_sim_stats_cg() with function sample(int unsigned percent_of_erasures, int unsigned percent_of_recovered_cws);
        option.per_instance = 1;
        percent_of_erasures_per_test_cp : coverpoint percent_of_erasures {
            bins all[6] = {[0:100]};
        }
        percent_of_recovered_codewords_cp : coverpoint percent_of_recovered_cws {
            bins all[6] = {[0:100]};
        }
    endgroup : decoder_end_of_sim_stats_cg


    function new(string name = "amiq_rs_fec_uvc_coverage_collector", uvm_component parent);
        super.new(name, parent);

        codeword_config_cg = new();
        encoder_output_decoder_input_cg = new();
        configuration_change_cg = new();
        error_inj_mode_cg = new();

        encoder_input_cg = new();
        encoder_output_cg = new();

        decoder_input_cg = new();
        decoder_output_cg = new();
        decoder_end_of_sim_stats_cg = new();

        reset_ap = new("reset_ap", this);
    endfunction

    // Function that creates the input and output ports for connecting to the encoder
    function void create_encoder_ports();
        encoder_in_ap = new("encoder_in_ap", this);
        encoder_out_ap = new("encoder_out_ap", this);
    endfunction :  create_encoder_ports

    // Function that creates the input and output ports for connecting to the decoder
    function void create_decoder_ports();
        decoder_in_ap = new("decoder_in_ap", this);
        decoder_out_ap = new("decoder_out_ap", this);
    endfunction :  create_decoder_ports

    // Here we get the config object from the database and create the ports according to the UVC's mode
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(amiq_rs_fec_uvc_config_obj)::get(this, "", "uvc_config", uvc_config))
            `uvm_fatal(get_full_name(), "Could not get the UVC config object.")

        case (uvc_config.uvc_mode)
            ENC_AND_DEC : begin
                create_encoder_ports();
                create_decoder_ports();
            end
            DECODING : begin
                create_decoder_ports();
            end
            ENCODING : begin
                create_encoder_ports();
            end
            default : begin
                `uvm_fatal(get_full_name(), "UVC MODE NOT SET CORRECTLY!")
            end
        endcase

        // if ((uvc_config.enable_error_injector) && (uvc_config.simulate_channel_erasures))
        erasure_ap = new("erasure_ap", this);

        erasure_item = amiq_rs_fec_uvc_erasure_item::type_id::create("erasure_item");
        current_dec_in_item = amiq_rs_fec_uvc_item::type_id::create("current_dec_in_item");
        current_enc_out_item = amiq_rs_fec_uvc_item::type_id::create("current_enc_out_item");

    endfunction : build_phase

    // This function sets the field current_config according to the uvc's configuration for sampling the config covergroup
    function void set_current_config();
        if ((uvc_config.codeword_length == 255) && (uvc_config.nof_data_symbols == 223))
            current_config = RS_255_223;
        if ((uvc_config.codeword_length == 208) && (uvc_config.nof_data_symbols == 192))
            current_config = RS_208_192;
        if ((uvc_config.codeword_length == 255) && (uvc_config.nof_data_symbols == 239))
            current_config = RS_255_239;
        if ((uvc_config.codeword_length == 528) && (uvc_config.nof_data_symbols == 514))
            current_config = RS_528_514;
        if ((uvc_config.codeword_length == 544) && (uvc_config.nof_data_symbols == 514))
            current_config = RS_544_514;
    endfunction : set_current_config

    // Collect coverage from the encoder's input
    function void write_encoder_input(amiq_rs_fec_uvc_item item);
        int unsigned nof_codewords = 0;
        int unsigned missing_data_symbols = 0;
        int unsigned symbol_array[];
        real percent = 0;

        // If some codewords are not complete, count the extra symbols at the end of the queue
        int unsigned extra_symbols = 0;

        // Check if the configuration changed and if it did, sample it
        set_current_config();
        if (int'(current_config) != prev_config) begin
            codeword_config_cg.sample(current_config);

            // It means that this is the first item, set the current configuration
            if (prev_config == -1) begin
                current_codeword_length = uvc_config.codeword_length;
                current_nof_data_sym = uvc_config.nof_data_symbols;
                current_nof_parity_sym = uvc_config.nof_parity_symbols;
            end

            // Save the configuration
            prev_config = int'(current_config);

        end

        // Modify these fields to know at the end that the configuration changed
        if (uvc_config.codeword_length != current_codeword_length) begin
            cw_len_changed = 1;
            current_codeword_length = uvc_config.codeword_length;
        end

        if (uvc_config.nof_data_symbols != current_nof_data_sym) begin
            nof_data_changed = 1;
            current_nof_data_sym = uvc_config.nof_data_symbols;
        end

        if (uvc_config.nof_parity_symbols != current_nof_parity_sym) begin
            nof_parity_changed = 1;
            current_nof_parity_sym = uvc_config.nof_parity_symbols;
        end

        symbol_array = item.unpack_symbols(uvc_config.symbol_size);

        // Calculate the number of codewords in the input item
        nof_codewords = symbol_array.size() / uvc_config.nof_data_symbols;

        // Calculate the extra symbols at the end, if any
        extra_symbols = symbol_array.size() % uvc_config.nof_data_symbols;

        // If we have a short codeword at the end
        if (extra_symbols != 0) begin
            nof_codewords += 1;
        end

        missing_data_symbols = int'(uvc_config.nof_data_symbols - extra_symbols);

        percent = real'(missing_data_symbols) / real'(uvc_config.nof_data_symbols);

        encoder_input_cg.sample(nof_codewords, int'(percent * 100));

    endfunction : write_encoder_input

    // Collect coverage from the encoder's output
    function void write_encoder_output(amiq_rs_fec_uvc_item item);
        int unsigned nof_codewords = 0;
        int unsigned symbol_array[];
        int unsigned extra_symbols = 0;
        amiq_rs_fec_uvc_item buffer1;
        amiq_rs_fec_uvc_item buffer2;

        if (!$cast(buffer1, item.clone())) begin
            `uvm_fatal(get_full_name(), "Failed cast!")
        end

        if (!$cast(buffer2, item.clone())) begin
            `uvm_fatal(get_full_name(), "Failed cast!")
        end

        encoder_output_q.push_back(buffer1);
        enc_out_for_error_coverage_q.push_back(buffer2);

        symbol_array = item.unpack_symbols(uvc_config.symbol_size);

        // Calculate the number of codewords in the input item
        nof_codewords = symbol_array.size() / uvc_config.codeword_length;

        // Calculate the extra symbols at the end, if any
        extra_symbols = symbol_array.size() % uvc_config.codeword_length;

        // If we have a short codeword at the end
        if (extra_symbols >= (1 + uvc_config.nof_parity_symbols)) begin
            nof_codewords += 1;
        end

        encoder_output_cg.sample(nof_codewords);
    endfunction : write_encoder_output

    // Collect coverage from the decoder's input
    function void write_decoder_input(amiq_rs_fec_uvc_item item);
        int unsigned nof_codewords = 0;
        int unsigned missing_data_symbols = 0;
        int unsigned symbol_array[];
        real percent = 0;

        // If some codewords are not complete, count the extra symbols at the end of the queue
        int unsigned extra_symbols = 0;

        amiq_rs_fec_uvc_item buffer1;
        amiq_rs_fec_uvc_item buffer2;

        if (!$cast(buffer1, item.clone())) begin
            `uvm_fatal(get_full_name(), "Failed cast!")
        end

        if (!$cast(buffer2, item.clone())) begin
            `uvm_fatal(get_full_name(), "Failed cast!")
        end

        decoder_input_q.push_back(buffer1);

        // Check if the configuration changed and if it did, sample it
        set_current_config();
        if (int'(current_config) != prev_config) begin
            codeword_config_cg.sample(current_config);

            // It means that this is the first item, set the current configuration
            if (prev_config == -1) begin
                current_codeword_length = uvc_config.codeword_length;
                current_nof_data_sym = uvc_config.nof_data_symbols;
                current_nof_parity_sym = uvc_config.nof_parity_symbols;
            end

            // Save the configuration
            prev_config = int'(current_config);
        end

        // Modify these fields to know at the end that the configuration changed
        if (uvc_config.codeword_length != current_codeword_length) begin
            cw_len_changed = 1;
            current_codeword_length = uvc_config.codeword_length;
        end

        if (uvc_config.nof_data_symbols != current_nof_data_sym) begin
            nof_data_changed = 1;
            current_nof_data_sym = uvc_config.nof_data_symbols;
        end

        if (uvc_config.nof_parity_symbols != current_nof_parity_sym) begin
            nof_parity_changed = 1;
            current_nof_parity_sym = uvc_config.nof_parity_symbols;
        end

        // If the error injector's mode is different when the decoder receives the item, sample the mode
        if ((uvc_config.enable_error_injector) && (int'(uvc_config.error_injector_mode) != error_injector_mode)) begin
            error_injector_mode = int'(uvc_config.error_injector_mode);
            error_inj_mode_cg.sample(uvc_config.error_injector_mode);
        end

        symbol_array = item.unpack_symbols(uvc_config.symbol_size);

        // Calculate the number of codewords in the input item
        nof_codewords = symbol_array.size() / uvc_config.codeword_length;

        // Calculate the extra symbols at the end, if any
        extra_symbols = symbol_array.size() % uvc_config.codeword_length;

        // If we have a short codeword at the end
        if (extra_symbols >= (1 + uvc_config.nof_parity_symbols)) begin
            nof_codewords += 1;
        end

        missing_data_symbols = int'(uvc_config.codeword_length - extra_symbols);

        percent = real'(missing_data_symbols) / real'(uvc_config.nof_data_symbols);

        decoder_input_cg.sample(nof_codewords, int'(percent * 100));

        encoder_out_decoder_in_sample(buffer2);
    endfunction : write_decoder_input

    // Collect coverage from the decoder's output
    function void write_decoder_output(amiq_rs_fec_uvc_item item);
        int unsigned cw_type;

        amiq_rs_fec_uvc_item dec_in_codeword = amiq_rs_fec_uvc_item::type_id::create("dec_in_codeword");

        // Used for comparing with the output item
        int unsigned encoder_out_cword_q[$] = {};
        int unsigned decoder_in_cword_q[$] = {};

        // Used to extract the decoder out codeword to check how many errors have been corrected
        int unsigned decoder_out_symbols[];

        // Specifies the number of differences between the encoder output codeword and the decoder input one
        int unsigned nof_differences = 0;
        int unsigned nof_erasures = 0;
        // Specifies the number of errors after substracting the number of erasures
        int unsigned nof_errors = 0;
        // Calculates a formula to determine how many errors should be corrected
        int unsigned errors_and_eras_formula = 0;
        // Count the number of corrected bits for collecting coverage
        int unsigned nof_corrected_bits = 0;

        // Count the codewords and the recovered ones for stats at the end of the test
        total_codewords++;
        if (item.uncorrectable == 0) begin
            nof_recovered_codewords++;
        end

        // Sampling logic for decoder_output_cg
        // Check that we either have items in the 2 FIFOs, or the previous ones haven't been exhausted
        if (((decoder_input_q.size()) && (enc_out_for_error_coverage_q.size())) ||
            (current_index < current_dec_in_symbols.size())) begin
            // If the previous items have been exhausted, get new ones
            if ((sym_array_size - current_index) < (1 + uvc_config.nof_parity_symbols)) begin
                current_dec_in_item = decoder_input_q.pop_front();
                current_enc_out_item = enc_out_for_error_coverage_q.pop_front();

                // Reset the symbol index
                current_index = 0;

                // Check for size mismatch
                if (current_dec_in_item.size != current_enc_out_item.size) begin
                    `uvm_fatal(get_full_name(), "Decoder input size not matching encoder output size!")
                end

                current_dec_in_symbols = current_dec_in_item.unpack_symbols(uvc_config.symbol_size);
                current_enc_out_symbols = current_enc_out_item.unpack_symbols(uvc_config.symbol_size);

                sym_array_size = current_dec_in_symbols.size();
            end

            /* Collect coverage on errors */

            // Corrected
            if (item.corrected == 1) begin
                cw_type = 0;
            end else
                //Uncorrectable
                cw_type = 1;

            // Error free
            if ((item.corrected == 1) && (item.nof_corrected_errors == 0)) begin
                cw_type = 2;
            end


            /* Make one codeword from the symbol array */

            // If we have enough symbols for a whole codeword, push back the next (codeword_length) symbols
            if ((current_index + uvc_config.codeword_length) <= sym_array_size) begin
                for (int j = current_index; j < (current_index + uvc_config.codeword_length); j++) begin
                    encoder_out_cword_q.push_back(current_enc_out_symbols[j]);
                    decoder_in_cword_q.push_back(current_dec_in_symbols[j]);
                end
                current_index += uvc_config.codeword_length;
            end else begin
                // If we have a short codeword, push back all the symbols that are left
                while (current_index < sym_array_size) begin
                    encoder_out_cword_q.push_back(current_enc_out_symbols[current_index]);
                    decoder_in_cword_q.push_back(current_dec_in_symbols[current_index]);
                    current_index++;
                end
            end

            // Find out the exact number of erasures and unknown errors
            foreach (erasure_item.erasure_positions_q[i])
                // Only count the erasures that could be inside the item because it could be a short codeword
                if (erasure_item.erasure_positions_q[i] < decoder_in_cword_q.size)
                    nof_erasures++;

            // Calculate the number of errors
            foreach (encoder_out_cword_q[i]) begin
                if (encoder_out_cword_q[i] != decoder_in_cword_q[i])
                    nof_errors++;
            end

            nof_errors = nof_differences - nof_erasures;
            errors_and_eras_formula = (2 * nof_errors) + nof_erasures;

            if ((errors_and_eras_formula >= uvc_config.nof_parity_symbols) && (item.corrected)) begin
                // False error free
                if (item.nof_corrected_errors == 0)
                    cw_type = 4;
                else
                    // False corrected
                    cw_type = 3;
            end

            if (item.corrected) begin
                // Pack the in codeword in an item in order to use bit compare
                dec_in_codeword.pack_symbols(decoder_in_cword_q, uvc_config.symbol_size);

                decoder_out_symbols = item.unpack_symbols(uvc_config.symbol_size);

                nof_corrected_bits = dec_in_codeword.bit_compare(item);

                foreach (decoder_out_symbols[i]) begin
                    if (decoder_out_symbols[i] != decoder_in_cword_q[i])
                        decoder_output_cg.sample(cw_type, i, nof_corrected_bits, item.nof_corrected_errors);
                end
            end else
                // If no symbols have been corrected, sample -1 for the symbol position (it will be ignored)
                decoder_output_cg.sample(cw_type, -1, 0, 0);

        end else
            `uvm_fatal(get_full_name(), "Decoder input queue/ Encoder output queue empty at decoder output!")

    endfunction : write_decoder_output

    // This function counts the number of codewords that had erasures during the test
    function void write_erasure_ap(amiq_rs_fec_uvc_erasure_item item);
        erasure_item = item;
        if (item.nof_erasures) begin
            nof_cws_with_eras += item.nof_cws;
        end
    endfunction : write_erasure_ap

    // This function extracts the necessary information from the encoder's output and the decoder's input for sampling
    function void encoder_out_decoder_in_sample(amiq_rs_fec_uvc_item dec_in_item);
        if (encoder_output_q.size()) begin
            amiq_rs_fec_uvc_item enc_out_item = encoder_output_q.pop_front();
            int unsigned encoder_out_symbols[] = enc_out_item.unpack_symbols(uvc_config.symbol_size);
            int unsigned decoder_in_symbols[] = dec_in_item.unpack_symbols(uvc_config.symbol_size);
            // Used to iterate in the symbol array and extract symbols
            int unsigned current_index = 0;
            int unsigned nof_codewords = 0;
            int unsigned sym_array_size = 0;

            // Used to store the encoder and decoder codewords
            int unsigned encoder_out_cword_q[$];
            int unsigned decoder_in_cword_q[$];

            if (encoder_out_symbols.size() != decoder_in_symbols.size()) begin
                `uvm_fatal(get_full_name(), "Encoder out size not matching decoder in size!")
            end

            sym_array_size = encoder_out_symbols.size();

            // Calculate the number of codewords
            nof_codewords = sym_array_size / uvc_config.codeword_length;
            // Add an extra codeword if we have a short codeword at the end
            nof_codewords += ((sym_array_size % uvc_config.codeword_length) >= (1 + uvc_config.nof_parity_symbols));

            for (int i = 0; i < nof_codewords; i++) begin
                // Prepare the codeword arrays
                encoder_out_cword_q = {};
                decoder_in_cword_q = {};

                // If we have enough symbols for a whole codeword, push back the next (codeword_length) symbols
                if ((current_index + uvc_config.codeword_length) <= sym_array_size) begin
                    for (int j = current_index; j < (current_index + uvc_config.codeword_length); j++) begin
                        encoder_out_cword_q.push_back(encoder_out_symbols[j]);
                        decoder_in_cword_q.push_back(decoder_in_symbols[j]);
                    end
                    current_index += uvc_config.codeword_length;
                end else begin
                    // If we have a short codeword, push back all the symbols that are left
                    while (current_index < sym_array_size) begin
                        encoder_out_cword_q.push_back(encoder_out_symbols[current_index]);
                        decoder_in_cword_q.push_back(decoder_in_symbols[current_index]);
                        current_index++;
                    end
                end

                // Sampling logic
                begin
                    // Differences between encoder output and decoder input
                    int unsigned nof_differences = 0;
                    int unsigned nof_eras = erasure_item.nof_erasures;
                    // Variable used for sampling how many symbols are different: a quarter, half of the symbols
                    int unsigned different_symbols_sampling = 0;
                    // Percent of erasures out of the number of differences
                    real percent_of_eras = 0;

                    // Calculate the number of errors
                    foreach (encoder_out_cword_q[i]) begin
                        nof_differences += (encoder_out_cword_q[i] != decoder_in_cword_q[i]);
                    end

                    if ((nof_eras != 0) && (nof_differences != 0)) begin
                        percent_of_eras = (real'(nof_eras) / real'(nof_differences)) * 100;
                    end else begin
                        percent_of_eras = 0;
                    end

                    if (nof_differences < 2) begin
                        different_symbols_sampling = nof_differences;
                    end else begin
                        // Used to store this result which will be used to figure out what value to sample
                        real temp = real'(nof_differences) / real'(decoder_in_cword_q.size());

                        // A quarter of the symbols are different, pick value 2
                        if ((temp > 0.2) && (temp < 0.3))
                            different_symbols_sampling = 2;
                        else
                            // A half of the symbols are different, pick value 3
                            if ((temp > 0.4) && (temp < 0.6))
                                different_symbols_sampling = 3;
                    end

                    encoder_output_decoder_input_cg.sample(int'(percent_of_eras), different_symbols_sampling);
                end

            end
        end else
            `uvm_fatal(get_full_name(), "Encoder output queue empty at decoder input!")
    endfunction : encoder_out_decoder_in_sample

    // This function resets the coverage collector's fields and queues
    function void write_reset_ap(bit reset);
        if (reset == 1) begin

            encoder_output_q.delete();
            decoder_input_q.delete();
            enc_out_for_error_coverage_q.delete();

            erasure_item.reset_item();
            current_enc_out_item.reset_item();
            current_dec_in_item.reset_item();

            current_index = 0;
            sym_array_size = 0;


            current_enc_out_symbols.delete();
            current_dec_in_symbols.delete();
        end
    endfunction : write_reset_ap

    // Here we calculate the percent of recovered codewords and the percent of codewords with erasures
    function void extract_phase(uvm_phase phase);
        real percent_recovered = real'(nof_recovered_codewords) / real'(total_codewords);
        real percent_eras = real'(nof_cws_with_eras) / real'(total_codewords);

        super.extract_phase(phase);

        decoder_end_of_sim_stats_cg.sample(int'(percent_eras * 100), int'(percent_recovered * 100));
        configuration_change_cg.sample(cw_len_changed, nof_parity_changed, nof_data_changed);
    endfunction : extract_phase

endclass

`endif  // __AMIQ_RS_FEC_UVC_COVERAGE_COLLECTOR
