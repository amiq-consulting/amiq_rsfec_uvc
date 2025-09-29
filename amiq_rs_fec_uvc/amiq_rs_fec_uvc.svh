// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     RS FEC UVC
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC
`define __AMIQ_RS_FEC_UVC
// The main component which instantiates the encoder and decoder
class amiq_rs_fec_uvc extends uvm_agent;

	`uvm_component_utils(amiq_rs_fec_uvc)

	// This port is used by the UVC to drive reset to all components
	uvm_analysis_port#(bit) reset_ap;
	// This port is used to signal the UVC's components to get the new config object when reconfiguring
	uvm_analysis_port#(bit) reconfig_ap;

	// The encoding component
	amiq_rs_fec_uvc_encoder encoder;
	// The decoding component
	amiq_rs_fec_uvc_decoder decoder;
	// A monitor that tracks every transfer inside the UVC
	amiq_rs_fec_uvc_tracker tracker;
	// The UVC's configuration object containing multiple settings
	amiq_rs_fec_uvc_config_obj uvc_config;
	// The component that adds noise to data
	amiq_rs_fec_uvc_error_injector error_injector;
	// The component that collects encoding and decoding coverage
	amiq_rs_fec_uvc_coverage_collector coverage_collector;
	// This component receives encoded input from an RTL, encodes it using its own algorithm and compares the results
	amiq_rs_fec_uvc_encode_checker encode_checker;
	// This component receives noisy data and 3 parameters from an RTL, decodes the data and checks that the parameters are correct
	amiq_rs_fec_uvc_decode_checker decode_checker;

	function new(string name = "amiq_rs_fec_uvc", uvm_component parent);
		super.new(name, parent);
		reset_ap = new("reset_ap", this);
		reconfig_ap = new("reconfig_ap", this);
	endfunction

	// here we create all the agent's components, respecting the settings in the config object
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		// get the config object
		if (!uvm_config_db#(amiq_rs_fec_uvc_config_obj)::get(this, "", "uvc_config", uvc_config))
			`uvm_fatal(get_full_name(), "Could not get the UVC config object.")

		case (uvc_config.uvc_mode)
			ENC_AND_DEC : begin
				encoder = amiq_rs_fec_uvc_encoder::type_id::create("encoder", this);
				decoder = amiq_rs_fec_uvc_decoder::type_id::create("decoder", this);
			end
			ENCODING : encoder = amiq_rs_fec_uvc_encoder::type_id::create("encoder", this);
			DECODING : decoder = amiq_rs_fec_uvc_decoder::type_id::create("decoder", this);
			default : begin
				`uvm_fatal(get_full_name(), "UVC Mode not set correctly!")
			end
		endcase

		if (uvc_config.enable_encode_checker)
			encode_checker = amiq_rs_fec_uvc_encode_checker::type_id::create("encode_checker", this);

		if (uvc_config.enable_decode_checker)
			decode_checker = amiq_rs_fec_uvc_decode_checker::type_id::create("decode_checker", this);

		if (uvc_config.enable_error_injector)
			error_injector = amiq_rs_fec_uvc_error_injector::type_id::create("error_injector", this);

		if (uvc_config.has_coverage)
			coverage_collector = amiq_rs_fec_uvc_coverage_collector::type_id::create("coverage_collector", this);

		tracker = amiq_rs_fec_uvc_tracker::type_id::create("tracker", this);

	endfunction

	// connect the ports to the coverage collector, according to the UVC's modes
	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		case (uvc_config.uvc_mode)
			ENC_AND_DEC : begin

				reconfig_ap.connect(encoder.reconfig_ap);
				reconfig_ap.connect(decoder.reconfig_ap);

				encoder.output_ap.connect(tracker.encoder_out_ap);
				decoder.output_ap.connect(tracker.decoder_out_ap);

				if (uvc_config.enable_error_injector) begin

					tracker.tr_enc_out_ap.connect(error_injector.injector_in_ap);

					error_injector.injector_out_ap.connect(decoder.input_ap);
					error_injector.injector_out_ap.connect(tracker.decoder_in_ap);

					tracker.tr_erasure_ap.connect(decoder.erasure_ap);
				end else begin
					tracker.tr_enc_out_ap.connect(decoder.input_ap);
					tracker.tr_enc_out_ap.connect(tracker.decoder_in_ap);
				end

				if (uvc_config.has_coverage) begin
					tracker.tr_enc_in_ap.connect(coverage_collector.encoder_in_ap);
					tracker.tr_enc_out_ap.connect(coverage_collector.encoder_out_ap);

					tracker.tr_dec_in_ap.connect(coverage_collector.decoder_in_ap);
					tracker.tr_dec_out_ap.connect(coverage_collector.decoder_out_ap);
				end
			end
			ENCODING : begin
				reconfig_ap.connect(encoder.reconfig_ap);

				encoder.output_ap.connect(tracker.encoder_out_ap);

				if (uvc_config.enable_error_injector) begin
					tracker.tr_enc_out_ap.connect(error_injector.injector_in_ap);
				end

				if (uvc_config.has_coverage) begin
					tracker.tr_enc_in_ap.connect(coverage_collector.encoder_in_ap);
					tracker.tr_enc_out_ap.connect(coverage_collector.encoder_out_ap);
				end
			end
			DECODING: begin
				reconfig_ap.connect(decoder.reconfig_ap);

				decoder.output_ap.connect(tracker.decoder_out_ap);

				if (uvc_config.has_coverage) begin
					tracker.tr_dec_in_ap.connect(coverage_collector.decoder_in_ap);
					tracker.tr_dec_out_ap.connect(coverage_collector.decoder_out_ap);
				end
			end
			default : begin
				`uvm_fatal(get_full_name(), "uvc_mode not set correctly!!\n Value should be one of: ENC_AND_DEC, ENCODING, DECODING")
			end
		endcase

		if (uvc_config.enable_error_injector) begin
			error_injector.erasure_ap.connect(tracker.erasure_ap);
			if (uvc_config.has_coverage)
				tracker.tr_erasure_ap.connect(coverage_collector.erasure_ap);
		end


		// RESET CONNECTIONS
		reset_ap.connect(tracker.reset_ap);
		if (uvc_config.has_coverage)
			reset_ap.connect(coverage_collector.reset_ap);
		if (encoder)
			reset_ap.connect(encoder.reset_ap);
		if (decoder)
			reset_ap.connect(decoder.reset_ap);
		if (encode_checker) begin
			reset_ap.connect(encode_checker.reset_ap);
			reconfig_ap.connect(encode_checker.reconfig_ap);
		end
		if (decode_checker) begin
			reset_ap.connect(decode_checker.reset_ap);
			reconfig_ap.connect(decode_checker.reconfig_ap);
		end
		if (error_injector)
			reset_ap.connect(error_injector.reset_ap);
	endfunction : connect_phase

	// This task can be called from outside the UVC to reset all components
	task reset_uvc();
		reset_ap.write(1);
		uvm_wait_for_nba_region();
	endtask : reset_uvc

	// This task sets the new config object, resets the uvc and then signals components that need to recalculate their parameters
	task reconfigure_uvc(amiq_rs_fec_uvc_config_obj new_config);

		// Reset the uvc to have a blank canvas before reconfiguring
		reset_uvc();

		// Set the new config object
		uvc_config.reconfigure(new_config);

		uvc_config.check_constraints();

		// Send the reconfiguration bit to all components so that they can get the new config object
		reconfig_ap.write(1);
		uvm_wait_for_nba_region();
	endtask : reconfigure_uvc

endclass
`endif  // __AMIQ_RS_FEC_UVC
