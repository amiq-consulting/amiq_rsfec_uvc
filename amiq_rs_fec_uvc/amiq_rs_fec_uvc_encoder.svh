// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Encoder
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_ENCODER
`define __AMIQ_RS_FEC_UVC_ENCODER

// Encoder class, extends the uvc base which contains all the GF logic
class amiq_rs_fec_uvc_encoder extends amiq_rs_fec_uvc_base;

	`uvm_component_utils(amiq_rs_fec_uvc_encoder)

	function new(string name = "amiq_rs_fec_uvc_encoder", uvm_component parent);
		super.new(name, parent);
		input_ap = new("input_ap", this);
		output_ap = new("output_ap", this);
	endfunction : new

	// The encoder's run_phase waits for the queue to contain an item, then begins processing it
	task run_phase(uvm_phase phase);
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
								amiq_rs_fec_uvc_item enc_output_item = amiq_rs_fec_uvc_item::type_id::create("enc_output_item");
								int unsigned codeword[];
								int unsigned data_buffer_q[$];
								// Used in ENTIRE_BATCH mode
								int unsigned codeword_q[$];
								int unsigned symbol_array[];
								int unsigned nof_codewords = 0;
								// Used to know where to start extracting symbols
								int unsigned current_index = 0;
								int unsigned sym_array_size = 0;

								// Unpack all the symbols from the input item in this array
								symbol_array = enc_item.unpack_symbols(uvc_config.symbol_size);
								sym_array_size = symbol_array.size();
								// Calculate the number of codewords
								nof_codewords = sym_array_size / uvc_config.nof_data_symbols;
								// Add an extra codeword if we have a short codeword at the end
								nof_codewords += ((sym_array_size % uvc_config.nof_data_symbols) != 0);

								for (int i = 0; i < nof_codewords; i++) begin
									// Prepare the data buffer, this will contain data symbols to form one codeword
									data_buffer_q.delete();

									// If we have enough symbols for a whole codeword, push back the next (nof_data_symbols) symbols
									if ((current_index + uvc_config.nof_data_symbols) <= sym_array_size) begin
										for (int j = current_index; j < (current_index + uvc_config.nof_data_symbols); j++) begin
											if ((j < sym_array_size) && (j >= 0))
												data_buffer_q.push_back(symbol_array[j]);
										end
										current_index += uvc_config.nof_data_symbols;
									end else begin
										// If we have a short codeword, push back all the symbols that are left
										while (current_index < sym_array_size) begin
											if ((current_index < sym_array_size) && (current_index >= 0)) begin
												data_buffer_q.push_back(symbol_array[current_index]);
												current_index++;
											end
										end
									end

									if (uvc_config.allow_padding == 0) begin
										AMIQ_ENCODER_PADDING_CHECK : assert (data_buffer_q.size() == uvc_config.nof_data_symbols)
										    else
											`uvm_fatal(get_full_name(), "Short codewords not allowed!")
									end

									encode(data_buffer_q, generator_poly, uvc_config.nof_parity_symbols, gf_log, gf_exp, field_charac, codeword);

									// If we are in WORD_BY_WORD mode, send one codeword
									if (uvc_config.data_transfer_mode == WORD_BY_WORD) begin
										amiq_rs_fec_uvc_item buffer;
										enc_output_item.pack_symbols(codeword, uvc_config.symbol_size);
										if (!$cast(buffer, enc_output_item.clone())) begin
											`uvm_fatal(get_full_name(), "Failed cast!")
										end

										output_ap.write(buffer);
										uvm_wait_for_nba_region();
									end else begin
										// Otherwise, append it to the codeword queue to send later
										foreach (codeword[i]) begin
											codeword_q.push_back(codeword[i]);
										end
									end
								end

								if ((uvc_config.data_transfer_mode == ENTIRE_BATCH) && (reset == 0)) begin
									amiq_rs_fec_uvc_item buffer;
									enc_output_item.pack_symbols(codeword_q, uvc_config.symbol_size);
									if (!$cast(buffer, enc_output_item.clone())) begin
										`uvm_fatal(get_full_name(), "Failed cast!")
									end
									output_ap.write(buffer);
									uvm_wait_for_nba_region();
								end
							end

						end else
							`uvm_fatal(get_full_name(), "Encoder got empty item!")
					end
				end

				begin
					wait (reset == 1);

					if (p_enc) begin
						p_enc.kill();
						input_item_q.delete();
					end

					reset = 0;
				end

			join
		end

	endtask : run_phase

endclass : amiq_rs_fec_uvc_encoder

`endif  // __AMIQ_RS_FEC_UVC_ENCODER
