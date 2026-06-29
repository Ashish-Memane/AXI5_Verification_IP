// =========================================================================
// File Name   : axi5_sequencer.sv
// Description : Parameterized Sequencer for the AMBA AXI5 Master Agent.
// =========================================================================

`ifndef AXI5_SEQUENCER_SV
`define AXI5_SEQUENCER_SV

class axi5_sequencer #(
  parameter int AW = 64, // Address Width
  parameter int DW = 64, // Data Width
  parameter int IW = 4   // ID Tag Width
) extends uvm_sequencer #(axi5_xtn #(AW, DW, IW));

  // =====================================================================
  // 1. CLASS PROPERTIES & UTILITIES
  // =====================================================================
  `uvm_component_param_utils(axi5_sequencer #(AW, DW, IW))

  // =====================================================================
  // 2. CONSTRUCTOR
  // =====================================================================
  function new(string name = "axi5_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

endclass : axi5_sequencer

`endif // AXI5_SEQUENCER_SV
