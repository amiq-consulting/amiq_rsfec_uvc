// /******************************************************************************
//  * (C) Copyright 2024 AMIQ All Rights Reserved
//  *
//  * NAME:     Galois Field Arithmetics PKG For RS
//  * PROJECT:  Reed-Solomon Forward Error Correction UVC
//  * AUTHOR:   Ioana Zuna
//  * DATE:     28.11.2024
//  *
//  *******************************************************************************/

`ifndef __AMIQ_RS_FEC_UVC_GF_FUNCTIONS_PKG
`define __AMIQ_RS_FEC_UVC_GF_FUNCTIONS_PKG

`include "uvm_macros.svh"

package amiq_rs_fec_uvc_gf_functions_pkg;

    import uvm_pkg::*;

//  ********* PARAMETERS *********  //

// Galois Field LUT For Logarithm, log[0] is impossible and unused
    int pkg_gf_log[];

// Galois Field Anti-Log (exponential) LUT
    int pkg_gf_exp[];

// field_charac -  maximum number in the chosen GF, for SYMBOL_SIZE=8, this will be 255

// generator - root of the field generator polynomial, used to generate numbers inside the GF

// fcr (First Consecutive Root) - the start of alpha's powers when multiplying the (x + alpha) factors

// prim - primitive element of the Galois Field, used to generate the LUTs

    string error_id = "ReedSolomonError";

//  ********* FUNCTIONS *********

// GF Multiplication using Russian Peasant Multiplication Algorithm (if y is odd -> XOR, afterwards left shift x and right shift y)
    function automatic int unsigned gf_mult_no_lut(int unsigned x, int unsigned y, int unsigned prime, int field_charac);
        automatic int unsigned result = 0;
        automatic int unsigned full_charac_value = field_charac + 1;
        while (y) begin
            if (y & 1) begin
                result = result ^ x;
            end
            y >>= 1;
            x <<= 1;
            // If x overflows, XOR with prime
            if ((prime > 0) && (x & full_charac_value))
                x ^= prime;
        end
        return result;
    endfunction : gf_mult_no_lut

// Galois Field Multiplication using pre-computed Look-up Tables
    function automatic int unsigned gf_mul(int unsigned x, int unsigned y, int field_charac,
        int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp);
        if ((x == 0) || (y == 0))
            return 0;
        return gf_exp[(gf_log[x] + gf_log[y]) % field_charac];
    endfunction : gf_mul

// The function that builds the Galois Field Look-up Tables
    function automatic void build_tables(output int gf_log[], output int gf_exp[], input int unsigned prime,
        int field_charac, int unsigned symbol_size, int unsigned generator = 2);
        automatic int unsigned x = 1;
        gf_log = new[2 ** symbol_size];
        gf_exp = new[(2 ** (symbol_size + 1)) - 2];
        // g^255 = g^0 so we skip the last element
        for (int i = 0; i < field_charac; i++) begin
            gf_exp[i] = x;
            gf_log[x] = i;
            x = gf_mult_no_lut(x, generator, prime, field_charac + 1);
        end
        for (int i = field_charac; i < (field_charac * 2); i++) begin
            gf_exp[i] = gf_exp[i - field_charac];
        end
    endfunction : build_tables

// GF Division Function
    function automatic int unsigned gf_div(int unsigned x, int unsigned y, int field_charac,
        int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp);
        if (y == 0)
            `uvm_fatal("GF_Functions_Package: ", "Division by zero forbidden!")
        if (x == 0)
            return 0;
        return gf_exp[(gf_log[x] + field_charac - gf_log[y]) % field_charac];
    endfunction : gf_div

// GF Power function
    function automatic int unsigned gf_pow(int unsigned x, int power, int field_charac,
        int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp);
        int mod_result = (gf_log[x] * power) % field_charac;
        if (mod_result < 0) begin
            mod_result += field_charac;
        end
        return gf_exp[mod_result];
    endfunction : gf_pow

// GF Inverse of a number (1/x)
    function automatic int unsigned gf_inverse(int unsigned x, int field_charac,
        int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp);
        return gf_exp[field_charac - gf_log[x]];
    endfunction : gf_inverse

// This function multiplies (in GF) each coefficient of a polynomial with a scalar
    function automatic void gf_poly_scale(int gf_log[], int gf_exp[],
        int field_charac, int unsigned scalar, inout int unsigned poly[]);
        foreach (poly[i]) begin
            int x = poly[i];
            int y = scalar;

            poly[i] = ((x == 0) || (y == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[y]) % field_charac]);
        end
    endfunction : gf_poly_scale

// Polynomial sum in GF
    function automatic void gf_poly_add(int unsigned poly1[], int unsigned poly2[], output int unsigned sum_poly[]);
        automatic int unsigned poly1_size = poly1.size();
        automatic int unsigned poly2_size = poly2.size();
        automatic int unsigned sum_poly_size = (poly1_size > poly2_size) ? poly1_size : poly2_size;

        sum_poly = new[sum_poly_size];

        for (int i = 0; i < poly1_size; i++)
            sum_poly[i + sum_poly_size - poly1_size] = poly1[i];

        for (int i = 0; i < poly2_size; i++)
            sum_poly[i + sum_poly_size - poly2_size] ^= poly2[i];

    endfunction : gf_poly_add

// Polynomial multiply function in GF
    function automatic void gf_poly_mul(int unsigned poly1[], int unsigned poly2[], int gf_log[] = pkg_gf_log,
        int gf_exp[] = pkg_gf_exp, output int unsigned result_poly[]);
        automatic int unsigned poly1_size = poly1.size();
        automatic int unsigned poly2_size = poly2.size();
        automatic int unsigned result_poly_size = poly1_size + poly2_size - 1;

        int unsigned log_poly1[];

        log_poly1 = new[poly1_size];

        result_poly = new[result_poly_size];

        // Pre-compute log of first poly
        foreach (log_poly1[i])
            log_poly1[i] = gf_log[poly1[i]];

        for (int j = 0; j < poly2_size; j++) begin
            automatic int unsigned current_poly2_elem = poly2[j];
            // log[0] is undefined so we check that the current element is not 0
            if (current_poly2_elem != 0) begin
                automatic int unsigned log_current_poly2_elem = gf_log[current_poly2_elem];

                for (int i = 0; i < poly1_size; i++) begin
                    // Check that poly1[i] is not 0 because log[0] is undefined
                    if (poly1[i] != 0) begin
                        // Compute the sum of the 2 logs and then find the result in the anti-log (exp) LUT, the sum of 2 logs is equal to log(product)
                        result_poly[i + j] ^= gf_exp[log_poly1[i] + log_current_poly2_elem];
                    end
                end
            end
        end

    endfunction : gf_poly_mul

// Function that computes the primitive element which defines the Galois Field
    function automatic int unsigned find_prime_poly(int field_charac, int unsigned symbol_size, int unsigned generator = 2);
        // Check each element and find the first prime poly
        for (int unsigned prim_temp = field_charac; prim_temp < ((field_charac * 2) + 1); prim_temp += 2) begin
            automatic bit seen[] = new[2 ** symbol_size];
            automatic bit conflict = 0;
            automatic int unsigned x = 1;
            // Array that tells us whether each value has been generated
            foreach (seen[i])
                seen[i] = 0;
            for (int i = 0; i < field_charac; i++) begin
                x = gf_mult_no_lut(x, generator, prim_temp, field_charac + 1);
                // If x (alpha) overflows or has been already generated, abort the search
                if ((x > field_charac) || (seen[x])) begin
                    conflict = 1;
                    break;
                end else
                    seen[x] = 1;
            end
            if (conflict == 0) begin
                return prim_temp;
            end
        end
        return 0;
    endfunction : find_prime_poly

// Find a generator polynomial of degree = NOF_PARITY_SYMBOLS
    function automatic void compute_generator_poly(int unsigned generator = 2, int unsigned fcr = 0, int field_charac,
        int unsigned nof_parity_symbols, int gf_log[], int gf_exp[], output int unsigned generator_poly[]);

        // The factors used for calculating the generator poly: (x + alpha**(...))
        int unsigned x_alpha_factors[2];
        // The first element is the coefficient of x, always 1
        x_alpha_factors[0] = 1;

        // The generator polynomial starts as [1]
        generator_poly = new[1];
        generator_poly[0] = 1;

        for (int i = 0; i < nof_parity_symbols; i++) begin
            automatic int unsigned gen_size = generator_poly.size();

            // Buffer to hold the generator poly for multiplying
            int unsigned temp_gen_poly[];
            temp_gen_poly = new[gen_size];

            foreach (generator_poly[i])
                temp_gen_poly[i] = generator_poly[i];

            // Compute the next factor
            x_alpha_factors[1] = gf_pow(generator, i + fcr, field_charac, gf_log, gf_exp);

            gf_poly_mul(temp_gen_poly, x_alpha_factors, gf_log, gf_exp, generator_poly);
        end

    endfunction : compute_generator_poly

// Horner's method for polynomial evaluation
    function automatic void gf_poly_eval(int unsigned poly[], int unsigned x, int field_charac,
        int gf_log[], int gf_exp[], output int unsigned result);
        int unsigned poly_size = poly.size();
        // Initialize result with the first coefficient (the one of the HIGHEST degree -> An)
        result = poly[0];

        // The formula is: result = result * x + poly[i] for each coeff, from index 1
        for (int i = 1; i < poly_size; i++) begin
            // For Galois Field, we use gf_mul() and XOR
            // result = gf_mul(x, result, field_charac, gf_log, gf_exp) ^ poly[i];
            result = ((x == 0) || (result == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[result]) % field_charac]);
            result ^= poly[i];
        end
    endfunction : gf_poly_eval

// Syndromes used for decoding: Evaluate the received message poly at every power of the generator. If all results are 0, the message is error-free.
    function automatic void compute_syndromes(output int unsigned syndromes[], input int unsigned received[], int field_charac, int unsigned nof_parity_symbols,
        int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp, int unsigned fcr = 0, int unsigned generator = 2);

        syndromes = new[nof_parity_symbols];

        for (int i = 0; i < nof_parity_symbols; i++) begin
            automatic int unsigned gf_root_power = gf_pow(generator, i + fcr, field_charac, gf_log, gf_exp);
            gf_poly_eval(received, gf_root_power, field_charac, gf_log, gf_exp, syndromes[i]);
        end

    endfunction : compute_syndromes

// Using the Berlekamp–Massey algorithm, VERY IMPORTANT: The error locator must be reversed before attempting to find its roots!!
    function automatic void find_error_locator_poly(output int unsigned final_error_loc[], input int unsigned syndromes[],
        int unsigned nof_parity_symbols, int field_charac, int gf_log[] = pkg_gf_log,
        int gf_exp[] = pkg_gf_exp, int unsigned erase_locator_q[$] = {}, int unsigned erase_count = 0);
        // Make it a queue in order to dynamically add elements each iteration
        automatic int unsigned error_loc_q[$];
        automatic int unsigned prev_error_loc_q[$];
        automatic int i;
        automatic int error_loc_size = 0;

        // The algorithm iteratively computes the discrepancy
        automatic int unsigned discrepancy;

        // If we have erasures, initialize the error locator with the erase locator to include them
        if (erase_locator_q.size()) begin
            error_loc_q = erase_locator_q;
            prev_error_loc_q = erase_locator_q;
        end else begin
            // Init the polys with 1
            error_loc_q.push_back(1);
            prev_error_loc_q.push_back(1);
        end

        for (int k = 0; k < (nof_parity_symbols - erase_count); k++) begin
            int unsigned error_loc_size = error_loc_q.size();
            i = k + erase_count;
            discrepancy = syndromes[i];

            for (int j = 1; j < error_loc_size; j++) begin
                int x = syndromes[i - j];
                int y = error_loc_q[error_loc_size - (j + 1)];

                discrepancy ^= ((x == 0) || (y == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[y]) % field_charac]);
            end

            prev_error_loc_q.push_back(0);

            if (discrepancy != 0) begin
                automatic int unsigned prev_loc_buffer_q[$];
                automatic int unsigned error_loc_buffer_q[$];

                if (prev_error_loc_q.size() > error_loc_size) begin
                    // Copy the previous error loc in a buffer
                    automatic int unsigned temp_error_loc_q[$];

                    temp_error_loc_q = prev_error_loc_q;

                    // Compute the next error locator by scaling it with the discrepancy (delta)
                    gf_poly_scale(gf_log, gf_exp, field_charac, discrepancy, temp_error_loc_q);

                    prev_error_loc_q = error_loc_q;

                    // Divide the current error locator by delta
                    gf_poly_scale(gf_log, gf_exp, field_charac, gf_inverse(discrepancy, field_charac, gf_log, gf_exp), prev_error_loc_q);

                    error_loc_q = temp_error_loc_q;

                    temp_error_loc_q.delete();
                end

                // Update the error locator with the computed discrepancy
                prev_loc_buffer_q = prev_error_loc_q;

                gf_poly_scale(gf_log, gf_exp, field_charac, discrepancy, prev_loc_buffer_q);
                error_loc_buffer_q = error_loc_q;

                gf_poly_add(error_loc_buffer_q, prev_loc_buffer_q, error_loc_q);
                prev_loc_buffer_q.delete();
            end

        end

        error_loc_size = error_loc_q.size();
        while ((error_loc_size) && (error_loc_q[0] == 0)) begin
            automatic int unsigned buffer;
            buffer = error_loc_q.pop_front();
            error_loc_size--;
        end

        final_error_loc = new[error_loc_q.size()];

        foreach (final_error_loc[i])
            final_error_loc[i] = error_loc_q[i];

        error_loc_q.delete();
        prev_error_loc_q.delete();

    endfunction : find_error_locator_poly

// Chien Search: Evaluate the error locator polynomial at every power of alpha, the generator number
    function automatic bit find_error_poly_roots(int unsigned error_loc[], int unsigned msg_length, output int unsigned error_positions[], input int unsigned generator = 2,
        int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp, int unsigned symbol_size);
        automatic int unsigned error_pos_q[$];
        automatic int field_charac = (2 ** (symbol_size)) - 1;
        // Check all powers of generator to see if they can be roots
        for (int i = 0; i < msg_length; i++) begin
            int unsigned eval_result;
            int unsigned error_loc_size = error_loc.size();
            int unsigned x = gf_exp[(gf_log[generator] * i) % field_charac];
            eval_result = error_loc[0];

            for (int i = 1; i < error_loc_size; i++) begin
                // For Galois Field, we use gf_mul() and XOR
                eval_result = ((x == 0) || (eval_result == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[eval_result]) % field_charac]);
                eval_result ^= error_loc[i];
            end

            // If power i is a root, push it in the queue
            if (eval_result == 0) begin
                error_pos_q.push_back(msg_length - i - 1);
            end
        end

        // Check if the number of errors matches the degree of the locator poly
        if (error_pos_q.size() != (error_loc.size() - 1)) begin
            `uvm_info(error_id,
                $sformatf("Error number not matching! Error locator degree: %0d, nof errors found: %0d",
                    (error_loc.size() - 1), error_pos_q.size()), UVM_DEBUG)
            return 1;
        end

        // Copy the error positions in the output array
        error_positions = new[error_pos_q.size()];
        foreach (error_positions[i])
            error_positions[i] = error_pos_q[i];

        // Free the queue
        error_pos_q.delete();

        return 0;
    endfunction : find_error_poly_roots

// Compute erasure locator polynomial: (2^(erasure_positions[0]) + 1) * ... * (2^(erasure_positions[n]) + 1)
    function automatic void find_erasure_locator_poly(int unsigned erase_positions[], output int unsigned erasure_locator_q[$],
        input int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp, int unsigned generator = 2,
        int field_charac);
        erasure_locator_q.delete();
        // Push back 1 to prepare for multiplying
        erasure_locator_q.push_back(1);
        foreach (erase_positions[i]) begin
            automatic int unsigned erase_pos_buffer_q[$] = erasure_locator_q;
            automatic int unsigned alpha_poly[];
            automatic int unsigned sum_poly[];

            // Prepare the alpha power as a polynomial (1 - x*alpha**i)
            alpha_poly = new[2];
            alpha_poly[0] = gf_pow(generator, erase_positions[i], field_charac, gf_log, gf_exp);
            alpha_poly[1] = 0;

            // Add 1 to the polynomial
            gf_poly_add({1}, alpha_poly, sum_poly);

            // Multiply the erasure locator with the alpha poly
            gf_poly_mul(erase_pos_buffer_q, sum_poly, gf_log, gf_exp, erasure_locator_q);
        end
    endfunction : find_erasure_locator_poly

    /* The error evaluator is the result after slicing the last (nof_parity_symbols) elements
     * from the result of multiplying the syndromes with the error locator. It is later to determine the error magnitude. */
    function automatic void find_error_evaluator(int unsigned syndromes[], int unsigned error_locator[], output int unsigned error_evaluator[],
        input int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp, int unsigned nof_parity_symbols);

        int unsigned remainder[];
        int unsigned remainder_size = 0;

        gf_poly_mul(syndromes, error_locator, gf_log, gf_exp, remainder);

        error_evaluator = new[remainder.size() - (nof_parity_symbols) + 1];

        remainder_size = remainder.size();

        for (int i = nof_parity_symbols; i < remainder_size; i++)
            error_evaluator[i - (nof_parity_symbols)] = remainder[i];

    endfunction : find_error_evaluator

    /* The error magnitude polynomial will be computed using the syndromes, the error locator and the error evaluator.
     * This polynomial will contain the values needed to substract from the input message in order to recover the original data.
     */
    function automatic void correct_codeword(int unsigned codeword_in[], int unsigned syndromes[], int unsigned error_positions[],
        int unsigned nof_parity_symbols, output int unsigned codeword_out[], input int gf_log[] = pkg_gf_log,
        int gf_exp[] = pkg_gf_exp, int unsigned fcr = 0, int unsigned generator = 2, int field_charac);

        automatic int unsigned coef_pos[] = new[error_positions.size()];
        automatic int unsigned erase_loc_q[$];
        automatic int unsigned reversed_syndromes[] = new[syndromes.size()];
        automatic int unsigned error_evaluator[];
        automatic int unsigned reversed_error_evaluator[];
        /* Error location polynomial, computed from the error positions,
         *  these values represent the X values in the lambda polynomial: (1 + X1*x) + (1 + X2*x) +...+ (1 + Xv*x),
         *  where v is the degree of lambda.
         *  These values are needed when computing E (the error poly): its coefficients will be computed using the omega poly and
         *  the derivative of the lambda poly.*/
        automatic int unsigned x_q[$];
        automatic int unsigned x_length;
        /* Error polynomial (the E polynomial), will contain the values to be substracted from the message in order to recover the original.
         * E will have a number of Y coefficients, where Yj = omega(Xj^(-1))/lambda'(Xj^(-1)).
         */
        automatic int unsigned e[] = new[codeword_in.size()];
        // Error evaluator polynomial evaluation -> it is omega(X^(-1)), where omega is the error magnitude polynomial
        automatic int unsigned y;

        // Transform the positions in coefficient form
        foreach (error_positions[i])
            coef_pos[i] = codeword_in.size() - 1 - error_positions[i];

        find_erasure_locator_poly(coef_pos, erase_loc_q, gf_log, gf_exp, generator, field_charac);

        reversed_syndromes = {<<$bits(syndromes[0]){syndromes}};

        find_error_evaluator(reversed_syndromes, erase_loc_q, error_evaluator, gf_log, gf_exp, nof_parity_symbols);

        reversed_error_evaluator = new[error_evaluator.size()];

        reversed_error_evaluator = {<<$bits(error_evaluator[0]){error_evaluator}};

        // Use the error positions to get the error location poly X (Chien Search)
        foreach (coef_pos[i]) begin
            automatic int unsigned l = field_charac + coef_pos[i];
            x_q.push_back(gf_pow(generator, l, field_charac, gf_log, gf_exp));
        end

        x_length = x_q.size();

        // Compute the formal derivative
        // the ith error value is given by error_evaluator(gf_inverse(Xi)) / error_locator_derivative(gf_inverse(Xi))
        foreach (x_q[i]) begin
            automatic int unsigned xi_inv;
            automatic int unsigned err_loc_prime_tmp_q[$];
            automatic int unsigned err_loc_prime;
            // This is the value which should be added to the ith element to correct the error (if any)
            automatic int unsigned magnitude;

            xi_inv = gf_inverse(x_q[i], field_charac, gf_log, gf_exp);

            for (int j = 0; j < x_length; j++) begin
                if (j != i) begin
                    int x = xi_inv;
                    int y = x_q[j];
                    int temp = ((x == 0) || (y == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[y]) % field_charac]);
                    // err_loc_prime_tmp_q.push_back(gf_add_or_sub(1, gf_mul(xi_inv, x_q[j], field_charac, gf_log, gf_exp)));
                    err_loc_prime_tmp_q.push_back(1 ^ temp);
                end
            end

            err_loc_prime = 1;

            foreach (err_loc_prime_tmp_q[i]) begin
                int x = err_loc_prime;
                int y = err_loc_prime_tmp_q[i];

                err_loc_prime = ((x == 0) || (y == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[y]) % field_charac]);
            end

            // Compute the evaluation of the error evaluator polynomial, numerator of the Forney algorithm (errata evaluator evaluated)
            gf_poly_eval(error_evaluator, xi_inv, field_charac, gf_log, gf_exp, y);

            // Adjust to fcr parameter
            y = gf_mul(gf_pow(x_q[i], 1 - fcr, field_charac, gf_log, gf_exp), y, field_charac, gf_log, gf_exp);

            // Err_loc_prime is the divisor and it should not be 0
            if (err_loc_prime == 0)
                `uvm_info(error_id, "Could not find error magnitude, cannot divide by 0 !!", UVM_DEBUG)

            magnitude = gf_div(y, err_loc_prime, field_charac, gf_log, gf_exp);

            // Store the magnitude for the ith position in the magnitude polynomial
            e[error_positions[i]] = magnitude;
        end

        // Finally, correct the message by adding the magnitude polynomial
        gf_poly_add(codeword_in, e, codeword_out);

    endfunction : correct_codeword

// This is the encoding function which uses the Synthetic Division algo to divide the data poly by the generator poly
    function automatic void encode(input int unsigned data_symbols[], int unsigned generator_poly[], int unsigned nof_parity_symbols,
        input int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp, int field_charac, output int unsigned codeword[]);

        automatic int unsigned data_size = data_symbols.size();
        automatic int unsigned gen_size = generator_poly.size();

        codeword = new[data_size + nof_parity_symbols];

        foreach (data_symbols[i])
            codeword[i] = data_symbols[i];

        // Apply the Synthetic Division Algorithm (faster polynomial division)
        for (int i = 0; i < data_size; i++) begin
            automatic int unsigned coef = codeword[i];

            if (coef != 0)
                // In this algorithm, we skip the first element because the generator polynomial is always monic (the coefficient of the element with the highest degree is 1)
                // The first element is only used to normalize the dividend's (data_symbols) coefficients, and here it is always 1
                for (int j = 1; j < gen_size; j++) begin
                    int x = generator_poly[j];
                    int y = int'(coef);
                    // We won't check if an element is 0 because the generator poly will never have 0 in it
                    // XOR is the same as addition in GF
                    // codeword[i + j] ^= gf_mul(generator_poly[j], int'(coef), field_charac, gf_log, gf_exp);
                    codeword[i + j] ^= ((x == 0) || (y == 0)) ? 0 : (gf_exp[(gf_log[x] + gf_log[y]) % field_charac]);
                end
        end

        //After the synthetic division, the codeword will contain the quotient of the division as well
        foreach (data_symbols[i])
            codeword[i] = data_symbols[i];
    endfunction : encode

// Main decoding function, it returns the number of errors, or 0 if the codeword is uncorrectable
    function automatic int decode(int unsigned input_codeword[], int unsigned symbol_size, output int unsigned output_codeword[], input int unsigned nof_parity_symbols,
        input int gf_log[] = pkg_gf_log, int gf_exp[] = pkg_gf_exp, input int unsigned erase_positions[] = {}, int fcr = 0,
        int unsigned generator = 2);

//************* DECLARATIONS *************//
// We use this array to convert the frequency array (erase_positions) into the actual positions
        automatic int unsigned erase_pos_q[$];
        automatic int unsigned syndromes[];
        automatic int unsigned error_loc[];
        automatic int unsigned error_pos[];
        automatic int unsigned reversed_error_loc[];
        automatic bit has_errors = 0;

        automatic int field_charac = (2 ** symbol_size) - 1;

        automatic bit uncorrectable_flag = 0;

// The received codeword may be a short codeword
        automatic int unsigned codeword_size = input_codeword.size();

        // Int buffer for the input codeword
        automatic int unsigned codeword[] = new[codeword_size];
        // Int buffer for the output codeword
        automatic int unsigned corrected_codeword[] = new[codeword_size];

        automatic int unsigned erase_count;

// We are going to reverse the erase positions with this rule:
// erase_pos[i] = n-1-erase_pos[i]
        automatic int unsigned erase_pos_reversed[];

        automatic int unsigned erase_locator_q[$] = {};

//****************************************//

        foreach (input_codeword[i])
            codeword[i] = int'(input_codeword[i]);

        output_codeword = new[codeword_size];

// Add the erase positions
        foreach (erase_positions[i]) begin
            // Check if the erase positions are not outside the codeword
            if (erase_positions[i] < codeword.size()) begin
                erase_pos_q.push_back(erase_positions[i]);
                // Put 0 where there are erasures
                codeword[erase_positions[i]] = 0;
            end
        end

        if (erase_pos_q.size() > nof_parity_symbols) begin
            `uvm_info(error_id, $sformatf("Too many erasures: %0d", erase_pos_q.size()), UVM_DEBUG)
            foreach (output_codeword[i])
                output_codeword[i] = codeword[i];
            return -1;
        end

        foreach (corrected_codeword[i]) begin
            corrected_codeword[i] = codeword[i];
            output_codeword[i] = codeword[i];
        end

        compute_syndromes(syndromes, codeword, field_charac, nof_parity_symbols, gf_log, gf_exp, fcr, generator);

// Check if all syndromes are equal to 0
        foreach (syndromes[i]) begin
            if (syndromes[i]) begin
                has_errors = 1;
                break;
            end
        end

// If all syndromes are 0, the codeword has no noise
        if (has_errors == 0) begin
            return 0;
        end

        if (erase_pos_q.size() != 0) begin
            erase_count = erase_pos_q.size();
            erase_pos_reversed = new[erase_count];
            foreach (erase_pos_q[i])
                erase_pos_reversed[i] = codeword_size - 1 - erase_pos_q[i];

            find_erasure_locator_poly(erase_pos_reversed, erase_locator_q, gf_log, gf_exp, generator, field_charac);
        end

        find_error_locator_poly(error_loc, syndromes, nof_parity_symbols, field_charac, gf_log, gf_exp, erase_locator_q, erase_count);

        if (((((error_loc.size() - 1) - erase_count) * 2) + (erase_count)) > nof_parity_symbols) begin
            `uvm_info(error_id, "Too many errors + erasures to correct!", UVM_DEBUG)
            return -1;
        end

        reversed_error_loc = new[error_loc.size()];
// Explanation: use the streaming operator to reverse the array's elements in bit groups of size equal to the size of one element
        reversed_error_loc = {<<$bits(error_loc[0]){error_loc}};

        uncorrectable_flag = find_error_poly_roots(reversed_error_loc, codeword_size, error_pos, generator, gf_log, gf_exp, symbol_size);

        if (uncorrectable_flag) begin
            foreach (output_codeword[i]) begin
                output_codeword[i] = codeword[i];
            end
            return -1;
        end

// Use the computed values to correct the codeword
        correct_codeword(codeword, syndromes, error_pos, nof_parity_symbols, corrected_codeword, gf_log, gf_exp, fcr, generator, field_charac);

// Compute the syndromes again to check if the codeword was corrected successfully
        compute_syndromes(syndromes, corrected_codeword, field_charac, nof_parity_symbols, gf_log, gf_exp, fcr, generator);

        foreach (syndromes[i]) begin
            if (syndromes[i]) begin
                `uvm_info(error_id, "Could not correct codeword!", UVM_DEBUG)
                foreach (output_codeword[i]) begin
                    output_codeword[i] = codeword[i];
                end
                return -1;
            end
        end

        foreach (corrected_codeword[i])
            output_codeword[i] = corrected_codeword[i];

        return error_pos.size();

    endfunction : decode

endpackage

`endif  // __AMIQ_RS_FEC_UVC_GF_FUNCTIONS_PKG
