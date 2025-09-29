// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Encode Checker
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     20.03.2025
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_ENCODE_CHECKER
`define __AMIQ_RS_FEC_UVC_ENCODE_CHECKER

// This component receives encoded input from an RTL, encodes it using its own algorithm and compares the results
class amiq_rs_fec_uvc_encode_checker extends amiq_rs_fec_uvc_base;

	`uvm_component_utils(amiq_rs_fec_uvc_encode_checker)

	function new(string name = "amiq_rs_fec_uvc_encode_checker", uvm_component parent);
		super.new(name, parent);
		input_ap = new("input_ap", this);
	endfunction : new

	// The encoder's run_phase waits for the queue to contain an item, then begins processing it
	extern virtual task run_phase(uvm_phase phase);

endclass : amiq_rs_fec_uvc_encode_checker

task amiq_rs_fec_uvc_encode_checker::run_phase(uvm_phase phase);
	// Process variable used to kill item processing when reset comes
	process p_enc;

	super.run_phase(phase);

	forever begin
		// Wait for the item queue to have items
		fork
			forever begin : encoding_thread

				p_enc = process::self();

				wait (input_item_q.size() != 0); begin

					amiq_rs_fec_uvc_item enc_item = input_item_q.pop_front();

					if (enc_item.size > 0) begin
						if (reset == 0) begin
							int unsigned input_symbols[];
							int unsigned codeword[];
							int unsigned data_buffer[];

							// Extract the data symbols from the item and encode them again
							input_symbols = enc_item.unpack_symbols(uvc_config.symbol_size);

							data_buffer = new[input_symbols.size() - uvc_config.nof_parity_symbols];

							foreach (data_buffer[i]) begin
								if ((i < input_symbols.size()) && (i >= 0)) begin
									data_buffer[i] = input_symbols[i];
								end
							end

							encode(data_buffer, generator_poly, uvc_config.nof_parity_symbols, gf_log, gf_exp, field_charac, codeword);

							// Check that each parity symbol matches, parity symbols are at the end of the codeword
							for (int i = 0; i < uvc_config.nof_parity_symbols; i++) begin
								AMIQ_ENCODE_DATA_MISMATCH_CHECK : if (input_symbols[input_symbols.size() - uvc_config.nof_parity_symbols + i] !=
										codeword[codeword.size() - uvc_config.nof_parity_symbols + i]) begin
									`uvm_fatal(get_full_name(), "Received data not encoded correctly!")
								end
							end
						end
					end else
						`uvm_fatal(get_full_name(), "Encode checker got empty item!")

				end
			end

			begin
				wait (reset == 1);
				if (p_enc) begin
					p_enc.kill();
					input_item_q = {};
				end
				reset = 0;
			end

		join
	end

endtask : run_phase

`endif  // __AMIQ_RS_FEC_UVC_ENCODE_CHECKER
