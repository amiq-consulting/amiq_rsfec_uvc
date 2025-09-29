// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     Parameters and types Package
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     13.11.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_PARAMS_PKG
`define __AMIQ_RS_FEC_UVC_PARAMS_PKG

package amiq_rs_fec_uvc_params_pkg;

	/* Each time an item is received, a counter is incremented. Each time the UVC sends an output item, the counter is decremented.
	 * If the counter reaches this value, the test will stop.
	 */
	localparam TIMEOUT_VALUE = 150000;

	/* The UVC's modes that specify which components are instantiated: encoder, decoder or both. */
	typedef enum bit[1:0] {ENCODING = 2'b00, DECODING = 2'b01, ENC_AND_DEC = 2'b10} amiq_rs_fec_uvc_modes;

	/* This type specifies whether the encoder and error injector will send the data word by word, or all at once. */
	typedef enum bit {WORD_BY_WORD = 0, ENTIRE_BATCH = 1} amiq_rs_fec_uvc_data_transfer;

	/* The error injector's modes. */
	typedef enum bit[2:0] {ERROR_NUMBER_MODE = 3'b000, CODEWORD_STATUS_MODE = 3'b001, ERROR_FREQ_MODE = 3'b010,
		ONLY_ERASURES_MODE = 3'b011, USER_DEFINED_ERASURES_MODE = 3'b100} amiq_rs_fec_error_injector_mode;

	/* The UVC's RS configuration, this is used for coverage */
	typedef enum bit[2:0] {RS_255_223 = 3'b000, RS_208_192 = 3'b001, RS_255_239 = 3'b010, RS_528_514 = 3'b011,
		RS_544_514 = 3'b100} amiq_rs_fec_uvc_configuration;

	/* This is used to set the error injector's error pattern when using CODEWORD_STATUS_MODE.
	 * ERROR_FREE means the codeword will have no errors;
	 * CORRECTABLE means the codeword should be corrected;
	 * UNCORRECTABLE Means the codeword shouldn't be corrected;
	 * CORRUPTED Means the codeword will have more than 2t (nof_parity_symbols) errors, which will make the decoding result completely random;
	 * RANDOM means that for each codeword, the error injector will choose randomly one of the above error patterns.
	 */
	typedef enum bit[2:0] {ERROR_FREE = 3'b000, CORRECTABLE = 3'b001, UNCORRECTABLE = 3'b010, CORRUPTED = 3'b011,
		RANDOM = 3'b100} amiq_rs_fec_uvc_err_inj_cword_type;

	// Typedef for a dynamic array, is used so that the item's functions can return a dynamic array containing symbols instead of bytes
	typedef int unsigned amiq_rs_fec_uvc_symbol_array_t[];


	// *** STATIC DEFAULT VALUES FOR ALL SETTINGS *** \\
	static int default_symbol_size = 8;
	static int default_codeword_length = 255;
	static int default_nof_data_symbols = 247;
	static int default_nof_parity_symbols = default_codeword_length - default_nof_data_symbols;

	static int default_fcr = 0;
	static int default_generator = 2;

	static bit default_has_coverage = 1;

	static bit default_enable_error_injector = 1;
	static bit default_simulate_channel_erasures = 1;
	static bit default_enable_encode_checker = 1;
	static bit default_enable_decode_checker = 1;

	static bit default_allow_padding = 1;
	static amiq_rs_fec_uvc_modes default_uvc_mode = ENC_AND_DEC;
	static amiq_rs_fec_uvc_data_transfer default_data_transfer_mode = WORD_BY_WORD;
	static amiq_rs_fec_error_injector_mode default_error_injector_mode = ERROR_NUMBER_MODE;

	static int unsigned default_min_nof_errors = 0;
	static int unsigned default_max_nof_errors = default_nof_parity_symbols;
	static int unsigned default_erasure_chance = 30;
	static amiq_rs_fec_uvc_err_inj_cword_type default_codeword_type = RANDOM;
	static int unsigned default_bit_flip_frequency = 200;
	// ************************************************ \\

endpackage

`endif  // __AMIQ_RS_FEC_UVC_PARAMS_PKG
