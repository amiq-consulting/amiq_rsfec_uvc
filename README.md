# Implementation of a UVC for Reed-Solomon Codes

This repository provides a Universal Verification Component (UVC) for Reed-Solomon encoding and decoding, with error injection features, implemented using the Universal Verification Methodology (UVM). It includes support for any codeword configuration across any symbol size (from 3 bits per symbol to over 12 bits per symbol).

## Features

* RS encoding and decoding for any codeword configuration (e.g. RS(255, 223), RS(208, 192), RS(528, 514\) etc.) and for short codewords.  
* Error injection within a dedicated component (Error Injector) with different types (unknown errors and erasures), numbers and patterns of errors.  
* Communication with a verification environment through UVM analysis ports and dedicated tasks for reset and reconfiguration.  
* A standalone software package with all the Galois Field functions needed for encoding and decoding that can be used without instantiating the UVC.

## Integration and Usage

The UVC was developed using UVM 1.1d and tested in multiple simulators such as Xcelium and Questa.

The amiq\_rs\_fec\_uvc\_pkg.sv package can be imported inside the verification environment using: 

```
import amiq_rs_fec_uvc_pkg::*;
```

Afterwards, the UVC can be instantiated using:

```
amiq_rs_fec_uvc rs_fec_uvc;
rs_fec_uvc = amiq_rs_fec_uvc::type_id::create("rs_fec_uvc", this);
```

The UVC can be configured using an *amiq\_rs\_fec\_uvc\_config\_obj* configuration object. The defined options can be set manually or through the use of command line arguments (plusargs) like this:

```
+test_has_coverage=1
+test_enable_encode_checker=0
+test_uvc_mode=ENC_AND_DEC
```

All of the UVC’s settings are described below:

| Option | Description | Type |
| :---: | :---: | :---: |
| symbol\_size | The size (in bits) of one symbol. Default is 8\. | int |
| codeword\_length | The number of symbols in a codeword (data+parity): *n*. Default is 255\. | int |
| nof\_data\_symbols | The number of symbols in the codeword which will be data symbols: *k*. The remaining will be the number of parity symbols. Default is 247\. | int |
| fcr | First consecutive root \- the start of alpha’s powers when multiplying the (x \+ alpha) factors. It is usually 0\. | int |
| generator | This number (usually 2\) is used to generate all numbers inside the Galois Field (the numbers are the generator’s powers). | int |
| has\_coverage | Enabler for collecting coverage. Default is 1\. | bit |
| enable\_encode\_checker | Enabler for the encode checker. Default is 1\. | bit |
| enable\_decode\_checker | Enabler for the decode checker. Default is 1\. | bit |
| uvc\_mode | This option specifies which of the UVC’s RS components (encoder, decoder) will be instantiated. By default, both will be instantiated. | Enum: {ENCODING, DECODING, ENC\_AND\_DEC} |
| allow\_padding | Whether the UVC can receive short codewords or not. Default is 1\. | bit |
| data\_transfer\_mode | This option describes the UVC’s transfer mode: whether the encoder and error injector will send the received data codeword by codeword, or if they will send the entire item at once. It has 2 values: WORD\_BY\_WORD and ENTIRE\_BATCH. Default is WORD\_BY\_WORD. | Enum: {WORD\_BY\_WORD, ENTIRE\_BATCH} |
| enable\_error\_injector | Enabler for the error injector. Default is 1\. | bit |
| error\_injector\_mode | This option is for choosing what mode the error injector will be operating in. The default is Error Number Mode. | Enum: {ERROR\_NUMBER\_MODE, CODEWORD\_STATUS\_MODE, ERROR\_FREQUENCY\_MODE, ONLY\_ERASURES\_MODE, USER\_DEFINED\_ERASURES\_MODE} |
| simulate\_channel\_erasures | When this is enabled, the error injector will also simulate erasures. The way it inserts erasures depends on its operating mode. Default is 1 | bit |
| min\_nof\_errors | The minimum number of errors to be injected into a codeword when the Error Injector is in ERROR\_NUMBER\_MODE. Default is 0\. | int |
| max\_nof\_errors | The maximum number of errors to be injected into a codeword when the Error Injector is in ERROR\_NUMBER\_MODE. Default is 8\. | int |
| erasure\_chance | Every error injected in ERROR\_NUMBER\_MODE has a chance equal to this number to become an erasure if erasures are enabled. Default is 30%. | int (Represents a percent 0-100) |
| codeword\_type | The “type” each codeword will be in CODEWORD\_STATUS\_MODE. Default is RANDOM. | Enum: {ERROR\_FREE, CORRECTABLE, UNCORRECTABLE, CORRUPTED, RANDOM} |
| bit\_flip\_frequency | The frequency of flipped bits in ERROR\_FREQUENCY\_MODE. Default is 200 (1 flipped bit in every 200 bits). | int |
| user\_erasure\_item | An erasure item containing a list of erasure positions that apply to every codeword. This *list* should be provided to the UVC using the config object function *set\_user\_erasure\_item*() which takes a dynamic array of erasure positions as an argument. It **must** be provided in USER\_DEFINED\_ERASURES\_MODE, otherwise it is not needed. | amiq\_rs\_fec\_uvc\_erasure\_item |

The UVC can receive input data wrapped in an input item, *amiq\_rs\_fec\_uvc\_item*, with the following fields:

* byte unsigned data\_q: an array of bytes;  
* int unsigned size: the size of the data field,

which can be set using the method *set\_bytestream().*

The decoder sends out a single codeword wrapped in an output item of type *amiq\_rs\_fec\_uvc\_item* which contains either the corrected data, or the same data that it received if it was uncorrectable, along with 3 parameters:

* bit corrected: 1 if the codeword was corrected and 0 otherwise;  
* int unsigned nof\_corrected\_errors: the number of corrected errors if the codeword wasn’t uncorrectable;  
* bit uncorrectable: 1 if the codeword was uncorrectable and 0 otherwise.

The UVC contains 2 components that can validate an RTL’s behavior: Encode Checker and Decode Checker.

The Encode Checker is a component similar to the Encoder. It receives encoded data from an RTL, extracts the data symbols, computes the parity symbols and compares the resulting codeword to the one received from the RTL. If they are different, it will raise an error. This component receives amiq\_rs\_fec\_uvc\_item.

Similarly to the Encode Checker, this component receives a potentially noisy codeword from an RTL and 3 parameters from the decoding process: corrected\_cw (which is 1 if the codeword was corrected by the RTL and 0 otherwise), number\_of\_errors\_corrected and uncorrectable\_cw (which is 1 if the RTL was unabled to correct the codeword and 0 otherwise). The Decode Checker processes the received codeword and compares the results with the 3 parameters. If they are different, it will raise an error. All of this information is inside an amiq\_rs\_fec\_uvc\_item, which contains all the fields mentioned.

The UVC can be reset at any time like this:

```
rs_fec_uvc.reset_uvc();
```

And reconfigured like this, by providing a new configuration object with different settings:

```
rs_fec_uvc.reconfigure_uvc(new_uvc_config_object);
```

Note: you **cannot** change settings that enable/disable any of the UVC’s components. Other settings that cannot be changed: allow\_padding, data\_transfer\_mode.

## Ports

The Encoder, Decoder, Encode Checker, Decode Checker each inherit the same class and have the following input and output ports:

```
uvm_analysis_imp #(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_base) input_ap;
uvm_analysis_port #(amiq_rs_fec_uvc_item) output_ap;
```

The Error Injector has the following ports, one for input items, one for output items, and one for sending out erasure items (when erasures are enabled):

```
uvm_analysis_imp #(amiq_rs_fec_uvc_item, amiq_rs_fec_uvc_error_injector) injector_in_ap;
uvm_analysis_port #(amiq_rs_fec_uvc_item) injector_out_ap;
uvm_analysis_port #(amiq_rs_fec_uvc_erasure_item) erasure_ap;
```

By default, the Error Injector’s input port is connected to the Encoder’s output port and the Error Injector’s output and erasure ports are connected to the Decoder.

The Encoder’s input port and the Decoder’s output port **must** be connected when they are enabled. The same applies to the Encode and Decode Checkers.

## Using the software package

The encoding and decoding functions can be used without instantiating the UVC. The steps to doing this are the following:

1. Import *amiq\_rs\_fec\_uvc\_gf\_functions\_pkg* in your environment;  
2. Have the following variables declared and ready to be used:  
   1. **int unsigned generator\_poly\[\]** \-\> this will store the generator polynomial for the Galois Field  
   2. **int gf\_log\[\]** \-\> this is the LUT used for the logarithmic function inside GF  
   3. **int gf\_exp\[\]** \-\> LUT used for the exponential function inside GF  
   4. **int field\_charac** \-\> the largest number in the GF, (2^symbol\_size) \- 1  
   5. **int unsigned generator** \-\> the starting number, *usually it is 2*  
   6. **int unsigned fcr** \-\> this is usually 0  
   7. **int unsigned prim** \-\> used to generate the 2 LUTs  
3. Run *prim \=* *find\_prime\_poly()* with the parameters:  
   1. *field\_charac*  
   2. *symbol\_size*  
   3. *generator*  
4. Call the function *build\_tables()* with the parameters:  
   1. *gf\_log*  
   2. *gf\_exp*  
   3. *prim*  
   4. *field\_charac*  
   5. *symbol\_size*  
   6. *generator*  
5. Call the function *compute\_generator\_poly()* with the parameters:  
   1. *generator*  
   2. *fcr*  
   3. *field\_charac*  
   4. *The number of parity symbols*  
   5. *gf\_log*  
   6. *gf\_exp*  
   7. *generator\_poly*

After following these steps, the Galois Field parameters are initialized and you can call the functions *encode()* and *decode().*

**Encode()** must be called with the following parameters:

* A data symbol array (max 1 codeword)  
* generator\_poly  
* The number of parity symbols  
* gf\_log  
* gf\_exp  
* field\_charac  
* An empty array which will store the codeword obtained

**Example:**

```
encode(data_buffer_q, generator_poly, uvc_config.nof_parity_symbols, gf_log, gf_exp, field_charac, codeword);
```

**Decode()** returns \-1 if the codeword is uncorrectable, or the number of errors corrected and must be called with the following parameters:

* A codeword array  
* symbol\_size  
* An empty array which will store the corrected codeword  
* The number of parity symbols  
* gf\_log  
* gf\_exp  
* *Optional: an array containing a list of erasure positions (default is {})*  
* *Optional: fcr (default value is 0\)*  
* *Optional: generator (default value is 2\)*

**Example:**

```
nof_errors = decode(codeword_q, uvc_config.symbol_size, corrected_codeword, uvc_config.nof_parity_symbols, gf_log, gf_exp, erasure_item.erasure_positions_q);
```

**Or:**

```
nof_errors = decode(codeword_q, uvc_config.symbol_size, corrected_codeword, uvc_config.nof_parity_symbols, gf_log, gf_exp, {}, 1, 3);
```

After any reconfiguration in which the symbol size, codeword length or number of data symbols changes, steps 2-5 **must** be repeated to reflect the new codeword configuration. *Note: when reconfiguring the UVC, these steps are repeated automatically by the UVC.*

## Validation

The encoding and decoding algorithms have been validated using [Phil Karn’s C/C++ RS-FEC library (libfec)](https://github.com/ka9q/libfec) and MatLab RS functions from the [Communications Toolbox](https://www.mathworks.com/help/comm/error-detection-and-correction.html?s_tid=CRUX_lftnav).
