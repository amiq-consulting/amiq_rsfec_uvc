// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     Error Injector
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_ERROR_INJECTOR
`define __AMIQ_RS_FEC_UVC_ERROR_INJECTOR

// This component receives codewords and injects errors and erasures into them. It is configurable.
class amiq_rs_fec_uvc_error_injector extends uvm_component;

    `uvm_component_utils(amiq_rs_fec_uvc_error_injector)

    `uvm_analysis_imp_decl(_reset_ap)
    // The port through which the error injector receives the reset signal
    uvm_analysis_imp_reset_ap #(bit, amiq_rs_fec_uvc_error_injector) reset_ap;
    // The bit that triggers the killing of the main thread in the run phase
    bit reset = 0;

    // The error injector's input port
    uvm_analysis_imp #(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_error_injector) injector_in_ap;
    // The error injector's output port
    uvm_analysis_port #(amiq_rs_fec_uvc_item) injector_out_ap;

    // We use this port to send erasure info to the decoder
    uvm_analysis_port #(amiq_rs_fec_uvc_erasure_item) erasure_ap;

    // Get the config object in order to choose the error injector mode
    amiq_rs_fec_uvc_config_obj uvc_config;

    // Queue to hold input items
    amiq_rs_fec_uvc_item item_q[$];

    // Erasure item containing the erasure positions in the codeword, it will be randomized and send to the decoder
    amiq_rs_fec_uvc_erasure_item erasure_item;

    // The process variable that kills the try_generate_erasures() task
    process p_gen_eras;
    // The process variable that kills the error_number_mode() task
    process p_err_no;
    // The process variable that kills the new_erasure_item() task
    process p_new_eras;

    function new(string name = "amiq_rs_fec_error_injector", uvm_component parent);
        super.new(name, parent);
        injector_in_ap = new("injector_in_ap", this);
        injector_out_ap = new("injector_out_ap", this);
        reset_ap = new("reset_ap", this);
    endfunction

    // Here we get the config object and generate an empty erasure item if erasures are enabled
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(amiq_rs_fec_uvc_config_obj)::get(this, "", "uvc_config", uvc_config))
            `uvm_fatal(get_full_name(), "Could not get the uvc config object.")

        erasure_ap = new("erasure_ap", this);

        erasure_item = amiq_rs_fec_uvc_erasure_item::type_id::create("erasure_item");
        erasure_item.set_erasures({});
    endfunction

    // The function that triggers the reset and kills al processes
    function void write_reset_ap(bit reset_bit);
        reset = reset_bit;
        if (reset_bit) begin
            item_q.delete();
            erasure_item.set_erasures({});
            if (p_err_no)
                p_err_no.kill();
            if (p_gen_eras)
                p_gen_eras.kill();
            if (p_new_eras)
                p_new_eras.kill();
        end
    endfunction : write_reset_ap

    // Put the received data into a FIFO
    function void write(amiq_rs_fec_uvc_item item);
        amiq_rs_fec_uvc_item buffer;
        if (!$cast(buffer, item.clone())) begin
            `uvm_fatal(get_full_name(), "Failed cast!")
        end
        item_q.push_back(buffer);
    endfunction : write

    // The error injector pops an item from the queue, extracts the symbols and begins inserting errors according to the chosen mode
    virtual task run_phase(uvm_phase phase);
        process p_run_phase;
        super.run_phase(phase);
        forever begin
            fork
                forever begin : main_thread
                    p_run_phase = process::self();

                    wait (item_q.size() != 0); begin


                        // Used only in ENTIRE_BATCH transfer mode so that erasures are generated only once for each item
                        bit first_codeword = 1;
                        /* This is used to count how many codewords there are in a single item.
                         * This information is used in ENTIRE_BATCH mode for collecting erasure coverage */
                        int unsigned nof_codewords_in_item = 0;

                        amiq_rs_fec_uvc_item item = item_q.pop_front();
                        amiq_rs_fec_uvc_item output_item = amiq_rs_fec_uvc_item::type_id::create("output_item");

                        // Check if the received item has the minimum number of symbols: 1 data sym + the parity symbols
                        if (((item.size * 8) / uvc_config.symbol_size) < (1 + uvc_config.nof_parity_symbols)) begin
                            `uvm_fatal(get_full_name(), "Error injector didn't get enough symbols!")
                        end

                        if (item.size == 0)
                            `uvm_fatal(get_full_name(), "Error Injector got empty item!")

                        if (reset == 0) begin
                            int unsigned codeword_q[$];
                            // Used in ENTIRE_BATCH mode
                            int unsigned codeword_array_q[$];
                            int unsigned symbol_array[];
                            int unsigned nof_codewords = 0;
                            // Used to know where to start extracting symbols
                            int unsigned current_index = 0;
                            int unsigned sym_array_size = 0;

                            // Unpack all the symbols from the input item in this array
                            symbol_array = item.unpack_symbols(uvc_config.symbol_size);

                            // In this mode, the error injector will use all symbols at once regardless of data transfer mode
                            if (uvc_config.error_injector_mode == ERROR_FREQ_MODE) begin
                                amiq_rs_fec_uvc_item buffer;
                                flip_bits_by_frequency(symbol_array);
                                output_item.pack_symbols(symbol_array, uvc_config.symbol_size);

                                if (!$cast(buffer, output_item.clone())) begin
                                    `uvm_fatal(get_full_name(), "Failed cast!")
                                end

                                injector_out_ap.write(buffer);

                                uvm_wait_for_nba_region();
                            end else begin

                                sym_array_size = symbol_array.size();
                                // Calculate the number of codewords
                                nof_codewords = sym_array_size / uvc_config.codeword_length;

                                /* sym_array_size % env_config.codeword_length gives us how many symbols are at the end
                                 * we will increment nof_codewords ONLY if we have enough extra symbols for another (short) codeword
                                 * minimum symbols needed: 1 data sym + the parity symbols
                                 */
                                nof_codewords += ((sym_array_size % uvc_config.codeword_length) >= (1 + uvc_config.nof_parity_symbols));

                                if (uvc_config.data_transfer_mode == ENTIRE_BATCH) begin
                                    /* nof_codewords_in_item will be used to set the erasure item's field that is used for coverage,
                                     * to see how many codewords had erasures */
                                    nof_codewords_in_item = nof_codewords;
                                end

                                for (int i = 0; i < nof_codewords; i++) begin

                                    codeword_q = {};

                                    // If we have enough symbols for a whole codeword, push back the next (codeword_length) symbols
                                    if ((current_index + uvc_config.codeword_length) <= sym_array_size) begin
                                        for (int j = current_index; j < (current_index + uvc_config.codeword_length); j++) begin
                                            if ((j < sym_array_size) && (j >= 0)) begin
                                                codeword_q.push_back(symbol_array[j]);
                                            end
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

                                    // Inject errors only if it has the minimum number of symbols: 1 data sym + the parity symbols
                                    if (codeword_q.size() >= (1 + uvc_config.nof_parity_symbols)) begin

                                        /* In entire batch mode, we will generate a single erasure item for the whole batch of codewords.
                                         * We will do this at the start of the item (the first codeword). After that, we will apply those erasures
                                         * to all the codewords.
                                         * !!! THIS ONLY APPLIES IF THE ERROR INJECTOR'S MODE IS !NOT! USER_DEFINED_ERASURES !!!
                                         */
                                        if (uvc_config.error_injector_mode != USER_DEFINED_ERASURES_MODE) begin
                                            if ((uvc_config.data_transfer_mode == ENTIRE_BATCH) && (first_codeword == 1) && (uvc_config.simulate_channel_erasures)) begin
                                                try_generate_erasures(codeword_q, nof_codewords_in_item);
                                            end
                                        end

                                        // Call a different task according to the error injector's mode
                                        case (uvc_config.error_injector_mode)
                                            /* In this mode, if we have data_transfer_mode == ENTIRE_BATCH,
                                             * we will apply a single erasure item to all the codewords, if erasures are enabled.
                                             */
                                            ERROR_NUMBER_MODE : begin
                                                if (uvc_config.data_transfer_mode == ENTIRE_BATCH) begin
                                                    if (first_codeword == 0) begin
                                                        if (uvc_config.simulate_channel_erasures) begin
                                                            apply_erasures(codeword_q, erasure_item.erasure_positions_q);
                                                        end
                                                    end
                                                    inject_number_of_errors(codeword_q);
                                                end else
                                                    inject_number_of_errors(codeword_q, uvc_config.simulate_channel_erasures);
                                            end

                                            CODEWORD_STATUS_MODE : begin
                                                inject_by_codeword_status(codeword_q);
                                            end

                                            ONLY_ERASURES_MODE : begin
                                                if (uvc_config.data_transfer_mode == WORD_BY_WORD)
                                                    try_generate_erasures(codeword_q);
                                                else begin
                                                    if (first_codeword == 0)
                                                        apply_erasures(codeword_q, erasure_item.erasure_positions_q);
                                                end
                                            end

                                            USER_DEFINED_ERASURES_MODE : begin
                                                if (uvc_config.user_erasure_item == null)
                                                    `uvm_fatal(get_full_name(), "User erasure item not defined!")

                                                // Apply the user's erasures to the codeword and then send the erasures item to subscribers
                                                apply_erasures(codeword_q, uvc_config.user_erasure_item.erasure_positions_q);

                                                // When in ENTIRE_BATCH, send only ONE erasure item which applies to all codewords inside the item
                                                if ((first_codeword == 1) || (uvc_config.data_transfer_mode == WORD_BY_WORD)) begin
                                                    new_erasure_item(uvc_config.user_erasure_item.erasure_positions_q);
                                                    first_codeword = 0;
                                                end
                                            end

                                            default : begin
                                                `uvm_fatal(get_full_name(), "Error injector mode not set correctly!")
                                            end
                                        endcase

                                        // Send a single codeword, or append multiple ones to a single item
                                        if ((uvc_config.data_transfer_mode == WORD_BY_WORD) && (reset == 0)) begin
                                            amiq_rs_fec_uvc_item buffer;
                                            output_item.pack_symbols(codeword_q, uvc_config.symbol_size);

                                            if (!$cast(buffer, output_item.clone())) begin
                                                `uvm_fatal(get_full_name(), "Failed cast!")
                                            end
                                            injector_out_ap.write(buffer);

                                            uvm_wait_for_nba_region();
                                        end else begin
                                            foreach (codeword_q[i]) begin
                                                codeword_array_q.push_back(codeword_q[i]);
                                            end
                                        end
                                        first_codeword = 0;

                                    end
                                end
                                if (uvc_config.data_transfer_mode == ENTIRE_BATCH) begin
                                    amiq_rs_fec_uvc_item buffer;
                                    output_item.pack_symbols(codeword_array_q, uvc_config.symbol_size);
                                    if (!$cast(buffer, output_item.clone())) begin
                                        `uvm_fatal(get_full_name(), "Failed cast!")
                                    end
                                    injector_out_ap.write(buffer);
                                    uvm_wait_for_nba_region();
                                end

                            end
                        end
                    end
                end

                begin
                    wait (reset == 1);
                    if (p_run_phase) begin
                        p_run_phase.kill();
                    end
                    reset = 0;
                end
            join
        end
    endtask : run_phase

    /* Generates a new erasure item with a randomized chance between 0 and 100.
     * The item is generated if the chance is higher than 50%.
     * @param nof_codewords is used in ENTIRE_BATCH mode to set a field inside the new erasure item, which says how many
     * codewords it applies to. It is used for collecting coverage.
     */
    task try_generate_erasures(inout int unsigned codeword[], input int unsigned nof_codewords = 1);
        // This variable will be randomized to determine whether to generate a new erasure item or not
        bit probability = 0;

        p_gen_eras = process::self();

        // Generate a random bit
        probability = bit'($urandom_range(1));

        // Randomize a new erasure item if probability is higher than 50%
        if (probability == 1) begin
            erasure_item = amiq_rs_fec_uvc_erasure_item::type_id::create("erasure_item");

            if (!erasure_item.randomize() with {
                        erasure_positions_q.size() >= uvc_config.min_nof_errors;
                        erasure_positions_q.size() <= uvc_config.max_nof_errors;
                        foreach (erasure_positions_q[i])
                            erasure_positions_q[i] < codeword.size();
                    })
                `uvm_fatal(get_full_name(), "Failed to randomize erasure item!")

            // Insert errors in those positions
            apply_erasures(codeword, erasure_item.erasure_positions_q);

            erasure_item.nof_cws = nof_codewords;

            erasure_ap.write(erasure_item);
            uvm_wait_for_nba_region();

        end else begin
            // If an erasure item was previously generated but not now, it also applies to the current codeword
            if (erasure_item != null) begin
                // Insert errors in the same positions if we don't generate a new erasure item
                apply_erasures(codeword, erasure_item.erasure_positions_q);
                new_erasure_item(erasure_item.erasure_positions_q, nof_codewords);
            end
        end
    endtask : try_generate_erasures

    /* Generate a number of errors for the received codeword.
     * @param The codeword in which to inject errors
     * @param Whether or not erasures should be injected
     * @param Min and max number of errors. These are only used when this function is called internally in other error injector modes.
     * When using ERROR NUMBER MODE, the error injector will use the values in the uvc_config.
     */
    task inject_number_of_errors(inout int unsigned codeword[], input bit generate_erasures = 0, int min_errors = -1, int max_errors = -1);
        // The number of errors to be added to a codeword
        int unsigned nof_errors = 0;
        int unsigned codeword_size = codeword.size();

        // Queue to store erasure locations in (if enabled)
        int unsigned erasure_pos_q[$];

        // Position array used to not generate the same position twice
        bit err_pos[] = new[codeword_size];

        p_err_no = process::self();

        if (uvc_config.error_injector_mode == ERROR_NUMBER_MODE) begin
            // Generate a random number
            nof_errors = $urandom_range(uvc_config.max_nof_errors, uvc_config.min_nof_errors);

            /* In ENTIRE_BATCH, when erasures are enabled, the erasure item will be generated first.
             * We need to make sure that the number of erasures + unknown errors respects the min and max nof errors from uvc_config.
             */
            if ((uvc_config.data_transfer_mode == ENTIRE_BATCH) && (uvc_config.simulate_channel_erasures == 1)) begin
                /* Check how many erasures apply to the current codeword.
                 * If the total number of errors is over the limit, lower nof_errors. */
                int unsigned nof_erasures = 0;
                foreach (erasure_item.erasure_positions_q[i]) begin
                    if (erasure_item.erasure_positions_q[i] < codeword.size()) begin
                        nof_erasures++;
                    end
                end

                // Generate a new number of errors that satisfies the error number range
                while (((nof_errors + nof_erasures) > uvc_config.max_nof_errors) || ((nof_errors + nof_erasures) < uvc_config.min_nof_errors)) begin
                    nof_errors = $urandom_range(uvc_config.max_nof_errors - nof_erasures);
                end
            end
        end else begin
            // When this task is called in other modes, use the parameter values
            nof_errors = $urandom_range(max_errors, min_errors);
        end

        // Check that the user didn't supply a wrong number of errors
        if (nof_errors > codeword_size) begin
            `uvm_error(get_full_name(), $sformatf("Error number (%0d) larger than array size (%0d)!", nof_errors, codeword_size))
            return;
        end

        for (int i = 0; i < nof_errors; i++) begin
            int unsigned error_value;
            int unsigned position;
            // Used to know whether the symbol should be injected or not
            bit apply_error = 1;

            // Generate a random number in the chosen Galois Field
            error_value = $urandom_range((2 ** uvc_config.symbol_size) - 1, 1);

            // Generate a position that hasn't been chosen yet
            do begin
                position = $urandom_range(codeword_size - 1);
            end while (err_pos[position]);

            err_pos[position] = 1;

            // In this mode, extra caution is taken because one erasure item applies to the whole item
            if (uvc_config.data_transfer_mode == ENTIRE_BATCH) begin
                if (uvc_config.simulate_channel_erasures) begin
                    /* This queue will be empty unless the generated error position will match an erasure position,
                     * in which case an error should not be injected twice */
                    int unsigned find_buffer_q[$];
                    find_buffer_q = erasure_item.erasure_positions_q.find with (item == position);
                    // If the generated position is already an erasure, don't add any values to it
                    if (find_buffer_q.size() > 0) begin
                        apply_error = 0;
                        /* Decrement i because otherwise this error will be skipped and we will have fewer errors
                         * in the codeword than intended.
                         */
                        i--;
                    end
                end
            end

            if (apply_error) begin
                codeword[position] ^= error_value;
            end

            // If generate_erasures is enabled, compare a random chance with the erasure_chance, and mark the error as an erasure if needed
            if (generate_erasures) begin
                int unsigned erasure_probability = $urandom_range(100);
                if (erasure_probability <= uvc_config.erasure_chance) begin
                    erasure_pos_q.push_back(position);
                end
            end
        end

        // Generate a new erasure item based on the erasure positions
        if (generate_erasures) begin
            new_erasure_item(erasure_pos_q);
        end

    endtask : inject_number_of_errors

    // Adds errors in a codeword in the positions specified by a position list
    function void apply_erasures(inout int unsigned codeword[], input int unsigned erasure_pos[]);
        foreach (erasure_pos[i])
            if (erasure_pos[i] < codeword.size()) begin
                codeword[erasure_pos[i]] ^= $urandom_range(((2 ** uvc_config.symbol_size ) - 1), 1);
            end
    endfunction : apply_erasures

    /* Generates a set erasure item, not a random one.
     * apply_erasures() should be called as well, in addition to this one.
     * @param A dynamic array containing the erasure positions to be put in the item.
     * @param nof_codewords is used in ENTIRE_BATCH mode to set a field inside the new erasure item, which says how many
     * codewords it applies to. It is used for collecting coverage.
     */
    task new_erasure_item(int unsigned erasure_pos[], int unsigned nof_codewords = 1);
        amiq_rs_fec_uvc_erasure_item e_item = amiq_rs_fec_uvc_erasure_item::type_id::create("e_item");

        p_new_eras = process::self();


        e_item.set_erasures(erasure_pos);

        e_item.nof_cws = nof_codewords;

        erasure_ap.write(e_item);
        uvm_wait_for_nba_region();
    endtask :  new_erasure_item

    // Inject errors based on the desired codeword type (error pattern): correctable, uncorrectable, error-free etc
    task inject_by_codeword_status(inout int unsigned codeword[]);
        int min_nof_errors = 0;
        int max_nof_errors = 0;
        amiq_rs_fec_uvc_err_inj_cword_type cword_type;

        // If the type chosen is RANDOM, randomize the codeword type for each codeword: error-free, correctable etc
        if (uvc_config.codeword_type == RANDOM) begin
            do begin
                if (!std::randomize(cword_type)) begin
                    `uvm_fatal(get_full_name(), "Failed randomization!")
                end
                /* If the new value is "RANDOM", randomize it again in order to get one of the other values for this
                 * typedef: error-free, correctable etc.
                 */
            end while (cword_type == RANDOM);
        end else begin
            cword_type = uvc_config.codeword_type;
        end

        case (cword_type)
            // No errors
            ERROR_FREE : begin
                min_nof_errors = 0;
                max_nof_errors = 0;
            end
            // 0 < errors < t
            CORRECTABLE : begin
                min_nof_errors = 0;
                max_nof_errors = (uvc_config.nof_parity_symbols / 2) - 1;
            end
            // t < errors < 2t
            UNCORRECTABLE : begin
                min_nof_errors = uvc_config.nof_parity_symbols / 2;
                max_nof_errors = uvc_config.nof_parity_symbols;
            end
            // 2t < errors < size
            CORRUPTED : begin
                min_nof_errors = uvc_config.nof_parity_symbols + 1;
                max_nof_errors = codeword.size();
            end
            default : begin
                `uvm_fatal(get_full_name(), "Codeword type not set correctly!")
            end
        endcase

        // Don't use erasures in this mode because they might change the chosen type of codeword
        inject_number_of_errors(codeword, 0, min_nof_errors, max_nof_errors);

    endtask : inject_by_codeword_status

    /* We count the number of bits in the bytestream and, based on the error frequency,
     * we calculate how many bits should be flipped. After that, the calculated number
     * of bits is flipped, in random positions, similar to <inject_number_of_errors>.
     */
    task flip_bits_by_frequency(inout int unsigned bytestream[], input int unsigned symbol_size = uvc_config.symbol_size,
        int unsigned bit_flip_frequency = uvc_config.bit_flip_frequency);
        int unsigned size = bytestream.size();
        int unsigned nof_bits = size * symbol_size;
        // We find the required number of flipped bits by dividing the total number of bits with the frequency
        int unsigned nof_flipped_bits = nof_bits / bit_flip_frequency;

        // Create a position array to know which bits have been flipped
        bit err_pos[] = new[nof_bits];

        for (int i = 0; i < nof_flipped_bits; i++) begin
            // Generate a random bit index inside [0, nof_bits - 1]
            int unsigned bit_index;
            int unsigned sym_index;

            // Use int because bit[] size has to be static, it is 1 at first, then shifted
            int unsigned bit_mask = 1;

            // Generate a bit index that hasn't been chosen yet, by looking in the err_pos array
            do begin
                // Choose a random bit from all the bits in the bytestream
                bit_index = $urandom_range(nof_bits - 1);
                // Check in the err pos array to see if the chosen bit had already been chosen before, in which case choose another bit position
            end while (err_pos[bit_index] == 1);

            // Mark the index as 1 so that there won't be another error on the same bit
            err_pos[bit_index] = 1;

            // Find the symbol containing that bit, using uvc_config.symbol_size
            sym_index = bit_index / uvc_config.symbol_size;

            /* Create a bit mask of the same size as the symbol, with a 1 on the chosen bit position.
             * bit_index % symbol_size will give us the bit position inside the symbol, from left to right.
             * We need the position from right to left in order to left shift the bit mask.
             */
            bit_mask <<= symbol_size - (bit_index % symbol_size) - 1;

            // XOR the symbol with the mask
            bytestream[sym_index] ^= bit_mask;
        end
    endtask : flip_bits_by_frequency
endclass

`endif  // __AMIQ_RS_FEC_UVC_ERROR_INJECTOR
