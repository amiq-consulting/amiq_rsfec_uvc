// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Base class for Encoder and Decoder
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     19.11.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_BASE
`define __AMIQ_RS_FEC_UVC_BASE

// Workflow:
// 1. Choose all the code parameters (codeword length, symbol size etc)
// 2. Call find_prime_poly() to find a primitive element for building the Galois Field
// 3. Call build_tables() to generate the Look-up Tables for log/anti-log for the chosen GF
// 4. Call compute_generator_poly() to get the generator polynomial for encoding

// IMPORTANT: For the C functions: gfpoly == prim (from the uvc), fcs == fcr, prim == 1

// A virtual class that serves as a base for the encoder and decoder, holding all the GF logic and parameters
virtual class amiq_rs_fec_uvc_base extends uvm_component;

	`uvm_component_utils(amiq_rs_fec_uvc_base)

	`uvm_analysis_imp_decl(_reset_ap)
	`uvm_analysis_imp_decl(_reconfig_ap)

	// The port through which the encoder and decoder receive input items
	uvm_analysis_imp #(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_base) input_ap;
	// The RS FEC base's output port for sending processed items
	uvm_analysis_port #(amiq_rs_fec_uvc_item) output_ap;

	// Analysis port for receiving the reset signal
	uvm_analysis_imp_reset_ap#(bit, amiq_rs_fec_uvc_base) reset_ap;
	// Analysis port for receiving the reconfiguration signal
	uvm_analysis_imp_reconfig_ap#(bit, amiq_rs_fec_uvc_base) reconfig_ap;

	// When this variable becomes 1, the component's FIFOs and running processes will be reset
	bit reset = 0;

	// Handle to the uvc config object to check if coverage is enabled
	amiq_rs_fec_uvc_config_obj uvc_config;

	// Queue for storing the items when they are received
	amiq_rs_fec_uvc_item input_item_q[$];

	// Field generator polynomial coefficients
	int unsigned generator_poly[] = {};

	// Galois Field LUT For Logarithm, log[0] is impossible and unused
	int gf_log[] = {};

	// Galois Field Anti-Log (exponential) LUT
	int gf_exp[] = {};

	// Maximum number in the chosen GF, for SYMBOL_SIZE=8, this will be 255
	int field_charac = 255;

	// Root of the field generator polynomial, used to generate numbers inside the GF
	int unsigned generator = 2;

	// The start of alpha's powers when multiplying the (x + alpha) factors
	int unsigned fcr = 0;

	// Primitive element of the Galois Field, used to generate the LUTs
	int unsigned prim = 0;

	function new(string name = "amiq_rs_fec_uvc_base", uvm_component parent);
		super.new(name, parent);
		reset_ap = new("reset_ap", this);
		reconfig_ap = new("reconfig_ap", this);
	endfunction : new

	// The encoder and decoder will receive an item and push its copy into a FIFO
	virtual function void write(amiq_rs_fec_uvc_item item);
		amiq_rs_fec_uvc_item buffer;
		if (!$cast(buffer, item.clone())) begin
			`uvm_fatal(get_full_name(), "Failed cast!")
		end
		input_item_q.push_back(buffer);
	endfunction : write

	// This function sets the reset variable according to the received reset bit
	function void write_reset_ap(bit reset_bit);
		reset = reset_bit;
	endfunction : write_reset_ap

	// This function is used to reinitialize the RS code parameters for a new configuration
	virtual function void write_reconfig_ap(bit reconfig_bit);
		if (reconfig_bit == 1) begin
			// Reinitialize the GF parameters required for encoding/decoding
			init_rs_parameters(uvc_config.fcr, uvc_config.generator);
		end
	endfunction : write_reconfig_ap

	// Here we get the config object and initialize the RS parameters
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(amiq_rs_fec_uvc_config_obj)::get(this, "", "uvc_config", uvc_config))
			`uvm_fatal(get_full_name(), "Could not get the UVC config object.")

		// Initialize the GF parameters required for encoding/decoding
		init_rs_parameters(uvc_config.fcr, uvc_config.generator);
	endfunction : build_phase

	// This function calls find_prime_poly(), build_tables() and compute_generator_poly()
	function void init_rs_parameters(int unsigned fcr = 0, int unsigned generator = 2);
		this.fcr = fcr;
		this.generator = generator;
		this.field_charac = (2 ** (uvc_config.symbol_size)) - 1;
		this.prim = find_prime_poly(field_charac, uvc_config.symbol_size, generator);

		build_tables(gf_log, gf_exp, this.prim, field_charac, uvc_config.symbol_size, generator);

		compute_generator_poly(generator, fcr, field_charac, uvc_config.nof_parity_symbols, gf_log, gf_exp, generator_poly);

	endfunction : init_rs_parameters

endclass

`endif  // __AMIQ_RS_FEC_UVC_BASE
