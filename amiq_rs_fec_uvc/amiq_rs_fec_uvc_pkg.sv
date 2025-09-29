// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC Package
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/
`ifndef __AMIQ_RS_FEC_UVC_PKG
`define __AMIQ_RS_FEC_UVC_PKG

`include "uvm_macros.svh"

package amiq_rs_fec_uvc_pkg;

	import uvm_pkg::*;
	import amiq_rs_fec_uvc_params_pkg::*;
	import amiq_rs_fec_uvc_gf_functions_pkg::*;

	`include "amiq_rs_fec_uvc_item_library.svh"
	`include "amiq_rs_fec_uvc_config_obj.svh"
	`include "amiq_rs_fec_uvc_coverage_collector.svh"
	`include "amiq_rs_fec_uvc_error_injector.svh"
	`include "amiq_rs_fec_uvc_tracker.svh"
	`include "amiq_rs_fec_uvc_base.svh"
	`include "amiq_rs_fec_uvc_encoder.svh"
	`include "amiq_rs_fec_uvc_encode_checker.svh"
	`include "amiq_rs_fec_uvc_decoder.svh"
	`include "amiq_rs_fec_uvc_decode_checker.svh"
	`include "amiq_rs_fec_uvc.svh"

endpackage

`endif  // __AMIQ_RS_FEC_UVC_PKG
