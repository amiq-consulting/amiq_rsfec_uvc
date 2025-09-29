// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Config Object
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_CONFIG_OBJ
`define __AMIQ_RS_FEC_UVC_CONFIG_OBJ

// Object containing configurations for the  UVC
class amiq_rs_fec_uvc_config_obj extends uvm_object;

    `uvm_object_utils(amiq_rs_fec_uvc_config_obj)

    // Enabler for the coverage collector
    bit has_coverage = 1;


    /****** RS Configurations ******/
    int symbol_size        = 8;
    int codeword_length    = 255;
    int nof_data_symbols   = 247;
    int nof_parity_symbols = int'(codeword_length - nof_data_symbols);
    int fcr = 0;
    int generator = 2;
    /*******************************/


    /****** Special UVC configurations ******/
    // This bit tells the UVC whether padding the codewords is allowed or not
    bit allow_padding = 1;
    // This field specifies whether the UVC will have both encoding and decoding, or only one
    amiq_rs_fec_uvc_modes uvc_mode = ENC_AND_DEC;
    // This field specifies whether the encoder and error injector will send the received codewords one by one, or all at once
    amiq_rs_fec_uvc_data_transfer data_transfer_mode = WORD_BY_WORD;
    // Enabler for erasure simulation inside the error injector
    bit simulate_channel_erasures = 1;
    // Enabler for the error injector
    bit enable_error_injector = 1;
    // Enabler for the encode checker
    bit enable_encode_checker = 1;
    // Enabler for the decode checker
    bit enable_decode_checker = 1;
    /****************************************/


    /****** Error injector configurations ******/

    // The error injector's functioning mode
    amiq_rs_fec_error_injector_mode error_injector_mode = ERROR_NUMBER_MODE;

    // This field specifies the minimum number of errors to be inserted in a codeword when in err number mode
    int unsigned min_nof_errors = 0;
    // This field specifies the maximum number of errors to be inserted in a codeword when in err number mode
    int unsigned max_nof_errors = nof_parity_symbols;
    // In error number mode, this is the chance that a generated error will turn into an erasure
    int unsigned erasure_chance = 30;
    // In codeword status mode, this will be the error pattern applied to each codeword
    amiq_rs_fec_uvc_err_inj_cword_type codeword_type = RANDOM;
    // In error frequency mode, this will be the bit flip frequency. 1000 means 1 in 1000 bits is flipped
    int unsigned bit_flip_frequency = 200;

    // This item is used only in USER_DEFINED_ERASURES_MODE
    amiq_rs_fec_uvc_erasure_item user_erasure_item;
    /*******************************************/

    function new(string name = "amiq_rs_fec_uvc_config_obj");
        super.new(name);
    endfunction

    // Function that checks whether all the RS parameters are correct
    virtual function void check_constraints();
        if (nof_parity_symbols % 2)
            `uvm_fatal(get_full_name(), "Number of parity symbols not even!")
        // 2 ** 32 - 1 is the maximum integer and 2 ** 32 overflows, becomes 0 and fails this check
        if (symbol_size < (2 ** 5))
            if (codeword_length >= (2 ** symbol_size))
                `uvm_fatal(get_full_name(), "Codeword is too long!")
    endfunction : check_constraints

    // This function should be used when the user wants to configure a special erasure item
    function void set_user_erasure_item(int unsigned positions[]);
        user_erasure_item = amiq_rs_fec_uvc_erasure_item::type_id::create("user_erasure_item");
        user_erasure_item.set_erasures(positions);
    endfunction : set_user_erasure_item

    // This function reads plusargs from the command line for the uvc's settings
    virtual function void parse_uvc_plusargs();
        string uvc_mode_name = "ENC_AND_DEC";
        string data_transfer_mode_name = "WORD_BY_WORD";
        string error_injector_mode_name = "ERROR_NUMBER_MODE";
        string codeword_type_name = "RANDOM";
        string simulate_channel_erasures_name = "1";

        if (!$value$plusargs("test_has_coverage=%0b", has_coverage))
            has_coverage = default_has_coverage;

        if (!$value$plusargs("test_enable_encode_checker=%0b", enable_encode_checker))
            enable_encode_checker = default_enable_encode_checker;
        if (!$value$plusargs("test_enable_decode_checker=%0b", enable_decode_checker))
            enable_decode_checker = default_enable_decode_checker;

        if (!$value$plusargs("test_enable_error_injector=%0b", enable_error_injector))
            enable_error_injector = default_enable_error_injector;

        if (!$value$plusargs("test_allow_padding=%0b", allow_padding))
            allow_padding = default_allow_padding;

        if ($value$plusargs("test_uvc_mode=%0s", uvc_mode_name)) begin
            case (uvc_mode_name)
                "ENC_AND_DEC" :  begin
                    uvc_mode = ENC_AND_DEC;
                end
                "ENCODING" : begin
                    uvc_mode = ENCODING;
                end
                "DECODING" : begin
                    uvc_mode = DECODING;
                end
                default : begin
                    uvc_mode = ENC_AND_DEC;
                end
            endcase;
        end else
            uvc_mode = default_uvc_mode;

        if ($value$plusargs("test_data_transfer_mode=%0s", data_transfer_mode_name)) begin
            case (data_transfer_mode_name)
                "WORD_BY_WORD" :  begin
                    data_transfer_mode = WORD_BY_WORD;
                end
                "ENTIRE_BATCH" : begin
                    data_transfer_mode = ENTIRE_BATCH;
                end
                "RANDOM" : begin
                    int rand_mode = $urandom_range(1);
                    case (rand_mode)
                        0 : begin
                            data_transfer_mode = WORD_BY_WORD;
                        end
                        1 : begin
                            data_transfer_mode = ENTIRE_BATCH;
                        end
                        default : begin
                            data_transfer_mode = default_data_transfer_mode;
                        end
                    endcase;
                end
                default : begin
                    data_transfer_mode = default_data_transfer_mode;
                end
            endcase;
        end else
            data_transfer_mode = default_data_transfer_mode;

        if ($value$plusargs("test_error_injector_mode=%0s", error_injector_mode_name)) begin
            case (error_injector_mode_name)
                "ERROR_NUMBER_MODE" :  begin
                    error_injector_mode = ERROR_NUMBER_MODE;
                end
                "ERROR_FREQ_MODE" : begin
                    error_injector_mode = ERROR_FREQ_MODE;
                end
                "ONLY_ERASURES_MODE" : begin
                    error_injector_mode = ONLY_ERASURES_MODE;
                end
                "CODEWORD_STATUS_MODE" : begin
                    error_injector_mode = CODEWORD_STATUS_MODE;
                end
                "RANDOM" : begin
                    if (!std::randomize(error_injector_mode)) begin
                        `uvm_fatal(get_full_name(), "Randomization failed!")
                    end
                end
                default : begin
                    error_injector_mode = default_error_injector_mode;
                end
            endcase;
        end else
            error_injector_mode = default_error_injector_mode;

        if ($value$plusargs("test_simulate_channel_erasures=%0s", simulate_channel_erasures_name)) begin
            case (simulate_channel_erasures_name)
                "1" : begin
                    if (error_injector_mode == CODEWORD_STATUS_MODE) begin
                        `uvm_fatal(get_full_name(), "No erasures allowed in CODEWORD STATUS MODE!")
                    end
                    simulate_channel_erasures = 1;
                end
                "0" : begin
                    if ((error_injector_mode == ONLY_ERASURES_MODE) ||
                        (error_injector_mode == USER_DEFINED_ERASURES_MODE)) begin
                        `uvm_fatal(get_full_name(), "Erasures disabled in ONLY ERASURES MODE!!")
                    end
                    simulate_channel_erasures = 0;
                end
                "RANDOM" : begin
                    // When using an exclusively erasures mode, this should always be 1
                    if ((error_injector_mode == ONLY_ERASURES_MODE) ||
                        (error_injector_mode == USER_DEFINED_ERASURES_MODE)) begin
                        simulate_channel_erasures = 1;
                    end else
                        // In these modes, erasures should be disabled
                        if ((error_injector_mode == CODEWORD_STATUS_MODE) ||
                            (error_injector_mode == ERROR_FREQ_MODE)) begin
                            simulate_channel_erasures = 0;
                        end else begin
                            if (!std::randomize(simulate_channel_erasures)) begin
                                `uvm_fatal(get_full_name(), "Failed randomization!")
                            end
                        end
                end
                default : begin
                    `uvm_fatal(get_full_name(), "Simulate channel erasures not set correctly!")
                end
            endcase
        end else
            simulate_channel_erasures = default_simulate_channel_erasures;

        if (!$value$plusargs("test_symbol_size=%0d", symbol_size))
            symbol_size = default_symbol_size;
        if (!$value$plusargs("test_codeword_length=%0d", codeword_length))
            codeword_length = default_codeword_length;
        if (!$value$plusargs("test_nof_data_symbols=%0d", nof_data_symbols))
            nof_data_symbols = default_nof_data_symbols;
        nof_parity_symbols = int'(codeword_length - nof_data_symbols);
        if (!$value$plusargs("test_fcr=%0d", fcr))
            fcr = default_fcr;
        if (!$value$plusargs("test_generator=%0d", generator))
            generator = default_generator;

        if (!$value$plusargs("test_min_nof_errors=%0d", min_nof_errors))
            min_nof_errors = default_min_nof_errors;
        if (!$value$plusargs("test_max_nof_errors=%0d", max_nof_errors))
            max_nof_errors = default_max_nof_errors;
        if (!$value$plusargs("test_erasure_chance=%0d", erasure_chance))
            erasure_chance = default_erasure_chance;

        if ($value$plusargs("test_codeword_type=%0s", codeword_type_name)) begin
            case (codeword_type_name)
                "ERROR_FREE" : begin
                    codeword_type = ERROR_FREE;
                end
                "CORRECTABLE" : begin
                    codeword_type = CORRECTABLE;
                end
                "UNCORRECTABLE" : begin
                    codeword_type = UNCORRECTABLE;
                end
                "CORRUPTED" : begin
                    codeword_type = CORRUPTED;
                end
                "RANDOM" : begin
                    codeword_type = RANDOM;
                end
                default : begin
                    `uvm_fatal(get_full_name(), "Codeword type not set correctly!")
                end
            endcase;
        end else begin
            codeword_type = default_codeword_type;
        end
        if (!$value$plusargs("test_bit_flip_frequency=%0d", bit_flip_frequency))
            bit_flip_frequency = default_bit_flip_frequency;
    endfunction : parse_uvc_plusargs

    /* This function receives a modified config object and changes the current object's fields accordingly
     * (only the fields that can be changed)
     */
    virtual function void reconfigure(amiq_rs_fec_uvc_config_obj new_config);

        symbol_size = new_config.symbol_size;
        codeword_length = new_config.codeword_length;
        nof_data_symbols = new_config.nof_data_symbols;
        nof_parity_symbols = new_config.nof_parity_symbols;

        fcr = new_config.fcr;
        generator = new_config.generator;

        simulate_channel_erasures = new_config.simulate_channel_erasures;

        error_injector_mode = new_config.error_injector_mode;
        min_nof_errors = new_config.min_nof_errors;
        max_nof_errors = new_config.max_nof_errors;
        erasure_chance = new_config.erasure_chance;

        codeword_type = new_config.codeword_type;

        bit_flip_frequency = new_config.bit_flip_frequency;
    endfunction : reconfigure

    // Override this method to make sure the user_erasure_item is always copied correctly
    virtual function void do_copy(uvm_object rhs);
        amiq_rs_fec_uvc_config_obj rhs_config;

        super.do_copy(rhs);

        if (!$cast(rhs_config, rhs)) begin
            `uvm_fatal(get_full_name(), "Cannot cast to uvc config object when copying!!")
        end

        this.has_coverage = rhs_config.has_coverage;

        this.symbol_size = rhs_config.symbol_size;
        this.codeword_length = rhs_config.codeword_length;
        this.nof_data_symbols = rhs_config.nof_data_symbols;
        this.nof_parity_symbols = rhs_config.nof_parity_symbols;
        this.fcr = rhs_config.fcr;
        this.generator = rhs_config.generator;

        this.allow_padding = rhs_config.allow_padding;
        this.uvc_mode = rhs_config.uvc_mode;
        this.data_transfer_mode = rhs_config.data_transfer_mode;
        this.simulate_channel_erasures = rhs_config.simulate_channel_erasures;
        this.enable_decode_checker = rhs_config.enable_decode_checker;
        this.enable_encode_checker = rhs_config.enable_encode_checker;
        this.enable_error_injector = rhs_config.enable_error_injector;

        this.error_injector_mode = rhs_config.error_injector_mode;
        this.min_nof_errors = rhs_config.min_nof_errors;
        this.max_nof_errors = rhs_config.max_nof_errors;
        this.erasure_chance = rhs_config.erasure_chance;

        this.user_erasure_item = amiq_rs_fec_uvc_erasure_item::type_id::create("user_erasure_item");
        this.user_erasure_item.copy(rhs_config.user_erasure_item);
    endfunction : do_copy
endclass

`endif  // __AMIQ_RS_FEC_UVC_CONFIG_OBJ
