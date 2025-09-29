// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Tracker
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     29.01.2025
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_TRACKER
`define __AMIQ_RS_FEC_UVC_TRACKER

// This component is connected to all the UVC's ports and monitors every transaction
class amiq_rs_fec_uvc_tracker extends uvm_component;

	`uvm_component_utils(amiq_rs_fec_uvc_tracker)

	`uvm_analysis_imp_decl(_encoder_input)
	`uvm_analysis_imp_decl(_encoder_output)

	`uvm_analysis_imp_decl(_decoder_input)
	`uvm_analysis_imp_decl(_decoder_output)

	`uvm_analysis_imp_decl(_erasure_ap)

	`uvm_analysis_imp_decl(_reset_ap)

	/* The tracker's input ports for monitoring the UVC's components,
	 * one for each: encoder in/out, decoder in/out, erasure port */
	uvm_analysis_imp_encoder_input#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_tracker) encoder_in_ap;
	uvm_analysis_imp_encoder_output#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_tracker) encoder_out_ap;
	uvm_analysis_imp_decoder_input#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_tracker) decoder_in_ap;
	uvm_analysis_imp_decoder_output#(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_tracker) decoder_out_ap;
	uvm_analysis_imp_erasure_ap#(amiq_rs_fec_uvc_erasure_item, amiq_rs_fec_uvc_tracker) erasure_ap;
	uvm_analysis_imp_reset_ap#(bit, amiq_rs_fec_uvc_tracker) reset_ap;

	/* The tracker's output ports for sending received items to subscribers,
	 * one for each: encoder in/out, decoder in/out, erasure port */
	uvm_analysis_port#(amiq_rs_fec_uvc_item) tr_enc_in_ap;
	uvm_analysis_port#(amiq_rs_fec_uvc_item) tr_enc_out_ap;
	uvm_analysis_port#(amiq_rs_fec_uvc_item) tr_dec_in_ap;
	uvm_analysis_port#(amiq_rs_fec_uvc_item) tr_dec_out_ap;
	uvm_analysis_port#(amiq_rs_fec_uvc_erasure_item) tr_erasure_ap;

	// Handle to the UVC's config object
	amiq_rs_fec_uvc_config_obj uvc_config;

	/* Timers that increment when an encoder/decoder item is received, and decrement when the output is received.
	 * The test will stop if one of the timers reach a critical value. */
	int unsigned encoder_timer = 0;
	// Timer for the decoder
	int unsigned decoder_timer = 0;

	function new(string name = "amiq_rs_fec_uvc_tracker", uvm_component parent);
		super.new(name, parent);
	endfunction

	// Function that creates the input and output ports for connecting to the encoder
	function void create_encoder_ports();
		encoder_in_ap = new("encoder_in_ap", this);
		encoder_out_ap = new("encoder_out_ap", this);
		tr_enc_in_ap = new("tr_enc_in_ap", this);
		tr_enc_out_ap = new("tr_enc_out_ap", this);
	endfunction :  create_encoder_ports

	// Function that creates the input and output ports for connecting to the decoder
	function void create_decoder_ports();
		decoder_in_ap = new("decoder_in_ap", this);
		decoder_out_ap = new("decoder_out_ap", this);
		tr_dec_in_ap = new("tr_dec_in_ap", this);
		tr_dec_out_ap = new("tr_dec_out_ap", this);
	endfunction :  create_decoder_ports

	// Here we get the config object and create the ports according to the UVC mode
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
				create_encoder_ports();
				create_decoder_ports();
			end
		endcase

		erasure_ap = new("erasure_ap", this);
		tr_erasure_ap = new("tr_erasure_ap", this);

		reset_ap = new("reset_ap", this);
	endfunction : build_phase

	// Count an encoder in item, increment the encoder timer and send the item to subscribers
	function void write_encoder_input(amiq_rs_fec_uvc_item item);
		int unsigned total_nof_bits = item.size * 8;
		int unsigned nof_symbols = total_nof_bits / uvc_config.symbol_size;
		amiq_rs_fec_uvc_item clone;
		if (!$cast(clone, item.clone())) begin
			`uvm_fatal(get_full_name(), "Failed casting!")
		end

		// Add the number of codewords in the item
		encoder_timer += nof_symbols / uvc_config.nof_data_symbols;
		// Add 1 more if we have a short codeword at the end (size not divisible by nof_data_symbols)
		encoder_timer += ((nof_symbols % uvc_config.nof_data_symbols) != 0);

		if (encoder_timer >= TIMEOUT_VALUE)
			`uvm_fatal(get_full_name(), "Encoder timeout!!")

		tr_enc_in_ap.write(clone);
	endfunction : write_encoder_input

	// Count an encoder out item, decrement the encoder timer and send the item to subscribers
	function void write_encoder_output(amiq_rs_fec_uvc_item item);
		int unsigned total_nof_bits = item.size * 8;
		int unsigned nof_symbols = total_nof_bits / uvc_config.symbol_size;
		amiq_rs_fec_uvc_item clone;
		if (!$cast(clone, item.clone())) begin
			`uvm_fatal(get_full_name(), "Failed casting!")
		end

		// Subtract the number of codewords in the item
		encoder_timer -= nof_symbols / uvc_config.codeword_length;
		// Subtract 1 more if we have a short codeword at the end (size not divisible by codeword_length)
		// But ONLY if it has the minimum number of symbols (1 data + parity)
		encoder_timer -= ((nof_symbols % uvc_config.codeword_length) >= (1 + uvc_config.nof_parity_symbols));

		tr_enc_out_ap.write(clone);
	endfunction : write_encoder_output

	// Count a decoder in item, increment the decoder timer and send the item to subscribers
	function void write_decoder_input(amiq_rs_fec_uvc_item item);
		int unsigned total_nof_bits = item.size * 8;
		int unsigned nof_symbols = total_nof_bits / uvc_config.symbol_size;
		amiq_rs_fec_uvc_item clone;

		if (!$cast(clone, item.clone())) begin
			`uvm_fatal(get_full_name(), "Failed casting!")
		end

		// Add the number of codewords in the item
		decoder_timer += nof_symbols / uvc_config.codeword_length;

		// Add 1 more if we have a short codeword at the end (size not divisible by codeword_length)
		// But ONLY if it has the minimum number of symbols (1 data + parity)
		decoder_timer += ((nof_symbols % uvc_config.codeword_length) >= (1 + uvc_config.nof_parity_symbols));


		if (decoder_timer >= TIMEOUT_VALUE) begin
			`uvm_fatal(get_full_name(), "Decoder timeout!!")
		end

		tr_dec_in_ap.write(clone);
	endfunction : write_decoder_input

	// Count a decoder out item, decrement the decoder timer and send the item to subscribers
	function void write_decoder_output(amiq_rs_fec_uvc_item item);
		amiq_rs_fec_uvc_item clone;

		if (!$cast(clone, item.clone())) begin
			`uvm_fatal(get_full_name(), "Failed casting!")
		end
		// The decoder's output is always one codeword
		decoder_timer--;

		tr_dec_out_ap.write(clone);
	endfunction : write_decoder_output

	// Send the received erasure item to subscribers
	function void write_erasure_ap(amiq_rs_fec_uvc_erasure_item item);
		amiq_rs_fec_uvc_erasure_item clone;
		if (!$cast(clone, item.clone())) begin
			`uvm_fatal(get_full_name(), "Failed casting!")
		end
		tr_erasure_ap.write(clone);
	endfunction : write_erasure_ap

	// Count the number of resets for end of run statistics and reset the timers
	function void write_reset_ap(bit reset_bit);
        if (reset_bit == 1) begin
		    encoder_timer = 0;
		    decoder_timer = 0;
        end
	endfunction : write_reset_ap

	// Used to check that encoder & decoder timers are both 0. Otherwise it means items have not exited the UVC
	function void check_phase(uvm_phase phase);
		super.check_phase(phase);
		if (encoder_timer)
			`uvm_fatal(get_full_name(), $sformatf("Encoder timer not 0 at the end! Value: %0d", encoder_timer))
		if (decoder_timer)
			`uvm_fatal(get_full_name(), $sformatf("Decoder timer not 0 at the end! Value: %0d", decoder_timer))
	endfunction : check_phase

endclass
`endif  // __AMIQ_RS_FEC_UVC_TRACKER

