// =========================================================================
// File Name   : axi5_scoreboard.sv
// Description : Memory-Reference Scoreboard for AMBA AXI5 Verification.
// =========================================================================

`ifndef AXI5_SCOREBOARD_SV
`define AXI5_SCOREBOARD_SV

class axi5_scoreboard #(
  parameter int AW = 64, // Address Width
  parameter int DW = 64, // Data Width
  parameter int IW = 4   // ID Tag Width
) extends uvm_scoreboard;

  // =====================================================================
  // 1. CLASS PROPERTIES & CONFIGURATION
  // =====================================================================
  `uvm_component_param_utils(axi5_scoreboard #(AW, DW, IW))

  // Analysis Import to receive completed packets from the Monitor
  uvm_analysis_imp #(axi5_xtn #(AW, DW, IW), axi5_scoreboard #(AW, DW, IW)) item_collected_export;

  // Golden Reference Memory Model (Sparse Associative Array)
  // Maps Byte Addresses to individual bytes (8-bit data slots)
  protected bit [7:0] golden_memory[bit [AW-1:0]];

  // Diagnostic metrics
  protected int num_writes_checked = 0;
  protected int num_reads_checked  = 0;
  protected int num_mismatches     = 0;

  // =====================================================================
  // 2. CONSTRUCTOR
  // =====================================================================
  function new(string name = "axi5_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_collected_export = new("item_collected_export", this);
  endfunction : new

  // =====================================================================
  // 3. ANALYSIS PORT INTERFACE METHOD (write)
  // =====================================================================
  virtual function void write(axi5_xtn #(AW, DW, IW) tx);
    `uvm_info("SCB_RECV", $sformatf("Scoreboard received transaction from Monitor:\n%s", tx.sprint()), UVM_HIGH);

    if (tx.xact_type == WRITE) begin
      process_write_reference(tx);
    end else begin
      process_read_comparison(tx);
    end
  endfunction : write

  // =====================================================================
  // 4. REFERENCE MEMORY UPDATE METHOD (WRITE)
  // =====================================================================
  protected function void process_write_reference(axi5_xtn #(AW, DW, IW) tx);
    int bytes_per_beat = (1 << tx.size);
    int num_bytes_bus  = (DW / 8);

    // Declarations grouped at the top to satisfy SV scoping rules
    bit [AW-1:0] beat_addr;
    bit [DW-1:0] beat_data;
    bit [(DW/8)-1:0] beat_strb;
    bit [AW-1:0] byte_addr;
    bit [7:0]    byte_val;

    `uvm_info("SCB_WRITE", $sformatf("Processing Write reference update. ID=0x%0h, Addr=0x%0h, Len=%0d", tx.id, tx.addr, tx.len), UVM_MEDIUM);

    for (int beat = 0; beat <= tx.len; beat++) begin
      // Calculate start address offset for this specific beat
      beat_addr = calculate_beat_address(tx, beat);
      beat_data = tx.data[beat];
      beat_strb = tx.strb[beat];

      // Update golden memory byte-by-byte based on active Write Strobes (WSTRB)
      for (int i = 0; i < num_bytes_bus; i++) begin
        if (beat_strb[i]) begin
          byte_addr = beat_addr + i;
          byte_val  = (beat_data >> (i * 8)) & 8'hFF;
          golden_memory[byte_addr] = byte_val;
        end
      end
    end
    num_writes_checked++;
  endfunction : process_write_reference

  // =====================================================================
  // 5. REFERENCE MEMORY COMPARISON METHOD (READ)
  // =====================================================================
  protected function void process_read_comparison(axi5_xtn #(AW, DW, IW) tx);
    int bytes_per_beat = (1 << tx.size);
    int num_bytes_bus  = (DW / 8);
    bit mismatch_found = 1'b0;

    // Declarations grouped at the top to satisfy SV scoping rules
    bit [AW-1:0] beat_addr;
    bit [DW-1:0] observed_data;
    bit [DW-1:0] expected_data;
    bit [DW-1:0] extended_byte; // Used to safely shift 8-bit values into 64-bit arrays
    bit [AW-1:0] byte_addr;
    bit [7:0]    expected_byte;

    `uvm_info("SCB_READ", $sformatf("Comparing Read transaction. ID=0x%0h, Addr=0x%0h, Len=%0d", tx.id, tx.addr, tx.len), UVM_MEDIUM);

    for (int beat = 0; beat <= tx.len; beat++) begin
      beat_addr = calculate_beat_address(tx, beat);
      observed_data = tx.data[beat];

      // Construct the expected data beat from our golden memory model
      expected_data = 0;

      for (int i = 0; i < num_bytes_bus; i++) begin
        byte_addr = beat_addr + i;
        expected_byte = golden_memory.exists(byte_addr) ? golden_memory[byte_addr] : 8'h00; // Default to zero if uninitialized

        // Implicitly cast to larger width before shifting to avoid compiler cast syntax errors
        extended_byte = expected_byte;
        expected_data |= (extended_byte << (i * 8));
      end

      // Compare actual observed data against golden reference values
      if (observed_data !== expected_data) begin
        `uvm_error("AXI5_SCB_MISMATCH", $sformatf(
          "Data mismatch at Beat %0d (Addr: 0x%0h)!\n  Observed: 0x%0h\n  Expected: 0x%0h",
          beat, beat_addr, observed_data, expected_data
        ));
        mismatch_found = 1'b1;
      end
    end

    num_reads_checked++;
    if (mismatch_found) num_mismatches++;
  endfunction : process_read_comparison

  // =====================================================================
  // 6. HELPER ADDRESS GENERATION FUNCTION
  // =====================================================================
  // Mathematically unrolls the addresses for INCR, FIXED, and WRAP burst types
  protected function bit [AW-1:0] calculate_beat_address(axi5_xtn #(AW, DW, IW) tx, int beat);
    int bytes_per_beat = (1 << tx.size);
    int num_bytes_bus  = (DW / 8);

    case (tx.burst_type)
      FIXED: begin
        return tx.addr;
      end

      INCR: begin
        return tx.addr + (beat * bytes_per_beat);
      end

      WRAP: begin
        // Wrapping boundary calculations (AMBA Spec Chapter A3)
        int burst_length_bytes = (tx.len + 1) * bytes_per_beat;
        bit [AW-1:0] wrap_boundary = (tx.addr / burst_length_bytes) * burst_length_bytes;
        bit [AW-1:0] raw_addr      = tx.addr + (beat * bytes_per_beat);

        if (raw_addr >= wrap_boundary + burst_length_bytes) begin
          return raw_addr - burst_length_bytes;
        end else begin
          return raw_addr;
        end
      end

      default: return tx.addr;
    endcase
  endfunction : calculate_beat_address

  // =====================================================================
  // 7. REPORT PHASE
  // =====================================================================
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI5_SCB_REPORT", $sformatf(
      "\n=======================================================\n  AXI5 SCOREBOARD RUN SUMMARY:\n  Writes Monitored: %0d\n  Reads Validated : %0d\n  Data Mismatches : %0d\n=======================================================",
      num_writes_checked, num_reads_checked, num_mismatches
    ), UVM_NONE);
  endfunction : report_phase

endclass : axi5_scoreboard

`endif // AXI5_SCOREBOARD_SV
