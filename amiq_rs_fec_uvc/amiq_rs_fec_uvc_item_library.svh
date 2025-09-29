// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     UVC item library
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     30.10.2024
//  *
//  *******************************************************************************/

`ifndef __AMIQ_RS_FEC_UVC_ITEM_LIBRARY
`define __AMIQ_RS_FEC_UVC_ITEM_LIBRARY

`ifndef AMIQ_RS_FEC_UVC_ITEM
`define AMIQ_RS_FEC_UVC_ITEM

/* How to use: Create a new item and call the set_bytestream() method to set the item's data,
 * then call get_bytestream() or get_uncorrectable() to access the item's information */
class amiq_rs_fec_uvc_item extends uvm_sequence_item;

	// Size of the data queue
	rand int unsigned size;
	// The data containing one or more codewords
	rand byte unsigned data_q[$];

	// This field specifies that the data inside this item (when we have a single codeword) has been corrected
	bit corrected = 0;
	// This field specifies the number of errors that have been corrected in this item (when we have a single codeword)
	int unsigned nof_corrected_errors = 0;

	// A field that says the decoder was unable to correct the codeword
	bit uncorrectable = 0;

	`uvm_object_utils_begin(amiq_rs_fec_uvc_item)
		`uvm_field_int(size, UVM_DEFAULT)
		`uvm_field_queue_int(data_q, UVM_DEFAULT)
		`uvm_field_int(corrected, UVM_DEFAULT)
		`uvm_field_int(nof_corrected_errors, UVM_DEFAULT)
		`uvm_field_int(uncorrectable, UVM_DEFAULT)
	`uvm_object_utils_end

	// Constrain the array to contain data for a maximum amount of codewords
	constraint size_c {
		solve size before data_q;
		size > 0;
	}

	// Constrain the array's size to be equal to the size field
	constraint data_size_c {
		data_q.size() == size;
	}

	function new(string name = "amiq_rs_fec_uvc_item");
		super.new(name);
	endfunction

	// This function returns a string containing the item's data
	function string convert2string();
		foreach (data_q[i]) begin
			convert2string = {convert2string, $sformatf("%0d ", data_q[i])};
		end
	endfunction : convert2string

	/*@param A byte unsigned bytestream[] containing the user's information.
	 * Uses the argument to fill the item's fields: the data array and its size.
	 * @param How many bits there are in a symbol.
	 */
	function void set_bytestream(byte unsigned bytestream[]);
		data_q.delete();

		size = bytestream.size();

		foreach (bytestream[i])
			data_q.push_back(bytestream[i]);

	endfunction : set_bytestream

	// This function sets the 3 decoding parameters that are used by the decode checker
    function void set_decoding_parameters(bit corrected_cw, int unsigned number_of_errors_corrected, bit uncorrectable_cw);
		corrected = corrected_cw;
		nof_corrected_errors = number_of_errors_corrected;
		uncorrectable = uncorrectable_cw;
	endfunction : set_decoding_parameters

	//@param An empty byte unsigned bytestream[] to hold the item's data
	function void get_bytestream(output byte unsigned bytestream[]);
		bytestream = new[size];

		foreach (data_q[i]) begin
			if ((i < bytestream.size()) && (i >= 0))
				bytestream[i] = data_q[i];
		end

	endfunction : get_bytestream

	// Returns whether the codeword in this item is correctable or not
	function bit get_uncorrectable();
		return uncorrectable;
	endfunction : get_uncorrectable

	/* This function receives a symbol size and creates a symbol array by using the data queue.
	 * @param A symbol size in bits.*/
	function amiq_rs_fec_uvc_symbol_array_t unpack_symbols(input int unsigned bits_per_symbol);
		// Variable that keeps track of the bit position
		int bit_pos = 0;
		// Total number of bits in the item
		int total_bits = size * 8;
		// Array in which the created symbols will be stored
		amiq_rs_fec_uvc_symbol_array_t symbol_array;

		// The number of symbols that can be made with the bits we have
		int num_symbols = total_bits / bits_per_symbol;

		symbol_array = {};
		symbol_array = new[num_symbols];

		// Loop through data_q and extract symbols
		for (int i = 0; i < num_symbols; i++) begin
			int unsigned symbol = 0;

			// Extract each bit to put in the symbol
			for (int b = 0; b < bits_per_symbol; b++) begin
				// Determine the byte index in data_q by dividing by 8 (replaced with right shift to be faster)
				int byte_index = bit_pos >> 3;
				// Determine the bit index in the data_q byte
				int bit_index  = 7 - (bit_pos & 3'b111);  // MSB-first

				// Extract the bit and add it to our symbol
				symbol = (symbol << 1) | ((data_q[byte_index] >> bit_index) & 1);

				bit_pos++;
			end

			// Add the created symbol to the array
			symbol_array[i] = symbol;

		end

		return symbol_array;
	endfunction : unpack_symbols

	// This functions receives a symbol array and the number of bits per symbol, and packs the bits inside of the item's bytestream
	function void pack_symbols(amiq_rs_fec_uvc_symbol_array_t symbols, int unsigned bits_per_symbol);
		byte unsigned current_byte = 0;
		int bits_in_current_byte = 0;
		data_q = {};

		foreach (symbols[i]) begin
			int unsigned symbol = symbols[i];

			for (int b = bits_per_symbol - 1; b >= 0; b--) begin
				// Extract the current bit (MSB-first)
				bit bit_val = (symbol >> b) & 1;

				// Add the extracted bit into the current BYTE (MSB-first)
				current_byte = (current_byte << 1) | bit_val;
				bits_in_current_byte++;

				if (bits_in_current_byte == (2 ** 3)) begin
					// Add the completed byte in data_q
					data_q.push_back(current_byte);
					current_byte = 0;
					bits_in_current_byte = 0;
				end
			end
		end

		// If bits_in_current_byte is > 0 (hasn't been reset at the end of a byte) it means we have an incomplete byte, put it on MSB
		if (bits_in_current_byte > 0) begin
			current_byte = current_byte << (8 - bits_in_current_byte);
			data_q.push_back(current_byte);
		end

		size = data_q.size();
	endfunction : pack_symbols

	// Override this function to make sure the data queue is copied correctly always
	virtual function void do_copy(uvm_object rhs);
		amiq_rs_fec_uvc_item rhs_item;
		super.do_copy(rhs);

		if (!$cast(rhs_item, rhs)) begin
			`uvm_fatal(get_full_name(), "Failed to cast item when copying!")
		end

		this.data_q = rhs_item.data_q;
		this.size = rhs_item.size;
		this.corrected = rhs_item.corrected;
		this.nof_corrected_errors = rhs_item.nof_corrected_errors;
		this.uncorrectable = rhs_item.uncorrectable;

	endfunction : do_copy

	// Function that sets the current item's bytestream as null
	function void reset_item();
		this.set_bytestream({});
		this.set_decoding_parameters(0, 0, 0);
	endfunction : reset_item

	// This function returns how many different bits there are between 2 items
	function int bit_compare(amiq_rs_fec_uvc_item item);
		int count = 0;

		if (this.size != item.size) begin
			`uvm_error(get_full_name(), "Sizes not matching in bit_compare()!")
			return -1;
		end else begin
			foreach (this.data_q[i]) begin
				byte unsigned x_or = this.data_q[i] ^ item.data_q[i];
				// Count how many 1s are in the xor result (the number of different bits for this symbol)
				while (x_or) begin
					count += x_or & 1'b1;
					x_or >>= 1;
				end
			end
		end

		return count;

	endfunction : bit_compare

endclass
`endif  // AMIQ_RS_FEC_UVC_ITEM


`ifndef AMIQ_RS_FEC_UVC_ERASURE_ITEM
`define AMIQ_RS_FEC_UVC_ERASURE_ITEM

// This item gives the decoder the information about erasures
class amiq_rs_fec_uvc_erasure_item extends uvm_sequence_item;

	// A queue containing positions in a codeword which contain errors
	rand int unsigned erasure_positions_q[$];

	// The number of errors, it is calculated after the erasure positions have been set
	int nof_erasures = 0;

	// When the UVC is in ENTIRE_BATCH mode, count how many codewords this erasure item applies to
	int nof_cws = 1;

	`uvm_object_utils_begin(amiq_rs_fec_uvc_erasure_item)
		`uvm_field_queue_int(erasure_positions_q, UVM_DEFAULT)
		`uvm_field_int(nof_erasures, UVM_DEFAULT)
	`uvm_object_utils_end

	function new(string name = "amiq_rs_fec_uvc_erasure_item");
		super.new(name);
	endfunction : new

	// This function returns a string containing the erasure positions of the item
	function string convert2string();
		if (erasure_positions_q.size())
			foreach (erasure_positions_q[i]) begin
				convert2string = {convert2string, $sformatf("%0d ", erasure_positions_q[i])};
			end
		else
			convert2string = "";
	endfunction : convert2string

	// After randomizing, we want to check that there is no duplicate erasure position, otherwise we will get errors
	function void post_randomize();
		bit pos_array[];
		int unsigned max = 0;
		int unsigned erasure_pos_size = 0;
		super.post_randomize();

		erasure_pos_size = erasure_positions_q.size();

		if (erasure_pos_size != 0) begin
			// First find out the maximum position in the queue
			foreach (erasure_positions_q[i]) begin
				if (erasure_positions_q[i] > max) begin
					max = erasure_positions_q[i];
				end
			end

			// Create a binary occurrence vector to track every erasure position
			pos_array = new[max + 1];

			for (int i = 0; i < erasure_pos_size; i++) begin
				if ((erasure_positions_q[i] < pos_array.size()) && (erasure_positions_q[i] >= 0)) begin
					// If we find a duplicate, delete it
					if (pos_array[erasure_positions_q[i]] == 1) begin
						erasure_positions_q.delete(i);
						i--;
						erasure_pos_size--;
					end else
						pos_array[erasure_positions_q[i]] = 1;
				end
			end

		end

		count_erasures();
	endfunction : post_randomize

	// Set the erasure positions and count the erasures
	function void set_erasures(int unsigned eras_pos[]);
		erasure_positions_q.delete();
		if (eras_pos.size())
			foreach (eras_pos[i])
				erasure_positions_q.push_back(eras_pos[i]);
		else
			erasure_positions_q.delete();
		count_erasures();
	endfunction : set_erasures

	// Function that counts the number of erasures in the item, it is called in post_randomize, or when we set a new item
	function void count_erasures();
		nof_erasures = erasure_positions_q.size();
	endfunction : count_erasures

	// Function that empties the erasures array and resets the nof_cws field
	function void reset_item();
		this.set_erasures({});
		this.nof_cws = 1;
	endfunction : reset_item

	// Override this method to make sure the erasure positions queue is copied correctly
	virtual function void do_copy(uvm_object rhs);
		amiq_rs_fec_uvc_erasure_item rhs_erasure_item;
		super.do_copy(rhs);

		if (!$cast(rhs_erasure_item, rhs)) begin
			`uvm_fatal(get_full_name(), "Cannot cast erasure item when copying!")
		end

		this.erasure_positions_q = rhs_erasure_item.erasure_positions_q;
		this.nof_cws = rhs_erasure_item.nof_cws;
		this.nof_erasures = rhs_erasure_item.nof_erasures;

	endfunction : do_copy

endclass
`endif  // AMIQ_RS_FEC_UVC_ERASURE_ITEM

`endif  // __AMIQ_RS_FEC_UVC_ITEM_LIBRARY
