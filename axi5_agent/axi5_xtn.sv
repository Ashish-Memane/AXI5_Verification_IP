// =========================================================================
// File Name   : axi5_xtn.sv
// Description : Parameterized UVM Transaction Item representing an AXI5 Packet
// =========================================================================

`ifndef AXI5_XTN_SV
`define AXI5_XTN_SV

typedef enum bit [1:0] {
  FIXED = 2'b00,
  INCR  = 2'b01,
  WRAP  = 2'b10
} axi5_burst_e;

typedef enum bit {
  READ  = 1'b0,
  WRITE = 1'b1
} axi5_xact_e;

class axi5_xtn #(
  parameter int AW = 64,
  parameter int DW = 64,
  parameter int IW = 4
) extends uvm_sequence_item;

  // =====================================================================
  // 1. TRANSACTION FIELDS
  // =====================================================================
  rand bit [IW-1:0]      id;
  rand bit [AW-1:0]      addr;
  rand bit [7:0]         len;
  rand bit [2:0]         size;
  rand axi5_burst_e      burst_type;
  rand axi5_xact_e       xact_type;

  // Use a large enough width for the strobe to cover any DW;
  // We handle masking in post_randomize to ensure compliance.
  rand bit [DW-1:0]      data[];
  rand bit [DW-1:0]      strb[];

  rand bit [5:0]         atop;
  rand bit               poison[];

  bit [1:0]              bresp;
  bit [1:0]              rresp[];

  // =====================================================================
  // 2. CONSTRAINTS
  // =====================================================================
  constraint c_array_sizes {
    data.size()   == len + 1;
    strb.size()   == len + 1;
    poison.size() == len + 1;
  }

  constraint c_valid_size {
    (1 << size) <= (DW / 8);
  }

  constraint c_wrap_rules {
    if (burst_type == WRAP) {
      len inside {1, 3, 7, 15};
    }
  }

  constraint c_fixed_rules {
    if (burst_type == FIXED) {
      len <= 15;
    }
  }

  constraint c_4kb_boundary {
    if (burst_type == INCR) {
      ((addr & 12'hFFF) + ((len + 1) * (1 << size))) <= 4096;
    }
  }

  // =====================================================================
  // 3. UVM REGISTRATION
  // =====================================================================
  `uvm_object_param_utils_begin(axi5_xtn #(AW, DW, IW))
    `uvm_field_int(id, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(len, UVM_DEFAULT)
    `uvm_field_int(size, UVM_DEFAULT)
    `uvm_field_enum(axi5_burst_e, burst_type, UVM_DEFAULT)
    `uvm_field_enum(axi5_xact_e, xact_type, UVM_DEFAULT)
    `uvm_field_array_int(data, UVM_DEFAULT)
    `uvm_field_array_int(strb, UVM_DEFAULT)
    `uvm_field_int(atop, UVM_DEFAULT)
    `uvm_field_array_int(poison, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axi5_xtn");
    super.new(name);
  endfunction : new

  // =====================================================================
  // 4. POST-RANDOMIZE (Strobe calculation)
  // =====================================================================
  function void post_randomize();
    int bytes_per_beat = (1 << size);
    bit [DW-1:0] mask = '1;

    // Create a base mask for the active bytes
    // Example: if size=4 (4 bytes), mask = 0x000F
    mask = (1 << (bytes_per_beat * 8)) - 1;

    if (xact_type == WRITE) begin
      foreach (strb[i]) begin
        // Shift mask based on start address offset
        strb[i] = mask << ((addr + (i * bytes_per_beat)) % (DW/8) * 8);
      end
    end else begin
      foreach (strb[i]) strb[i] = '0; // Read strobes are typically unused
    end
  endfunction : post_randomize

endclass : axi5_xtn

`endif // AXI5_XTN_SV
