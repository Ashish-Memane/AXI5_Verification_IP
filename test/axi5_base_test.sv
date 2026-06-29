// =========================================================================
// File Name   : axi5_base_test.sv
// Description : UVM Test Component for AMBA AXI5 Verification.
//               Contains the parameterized environment setup (Base Test)
//               and the non-parameterized callable tests for command line.
// =========================================================================

`ifndef AXI5_BASE_TEST_SV
`define AXI5_BASE_TEST_SV

// =====================================================================
// 1. PARAMETERIZED BASE TEST (Handles Environment Setup)
// =====================================================================
class axi5_base_test #(
  parameter int AW = 64, // Address Width
  parameter int DW = 64, // Data Width
  parameter int IW = 4   // ID Tag Width
) extends uvm_test;

  `uvm_component_param_utils(axi5_base_test #(AW, DW, IW))

  // Environment and Config Handles
  axi5_env        #(AW, DW, IW) m_env;
  axi5_agt_config               m_cfg;
  virtual axi5_if #(AW, DW, IW) vif;

  function new(string name = "axi5_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual axi5_if #(AW, DW, IW))::get(this, "", "vif", vif)) begin
      `uvm_fatal("TEST_VIF_ERR", "Could not locate virtual interface (vif) inside top-level config DB!")
    end

    uvm_config_db#(virtual axi5_if #(AW, DW, IW))::set(this, "m_env*", "vif", vif);

    m_cfg = axi5_agt_config::type_id::create("m_cfg");
    m_cfg.is_active = UVM_ACTIVE; // Active Master Mode

    uvm_config_db#(axi5_agt_config)::set(this, "m_env*", "axi5_agt_config", m_cfg);
    m_env = axi5_env #(AW, DW, IW)::type_id::create("m_env", this);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
  endtask : run_phase

endclass : axi5_base_test


// =====================================================================
// 2. SANITY TEST (Write-after-Read Loop)
// =====================================================================
class axi5_sanity_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_sanity_test)

  function new(string name = "axi5_sanity_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_sanity_seq #(64, 64, 4) seq = axi5_sanity_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Sanity Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Sanity Test");
  endtask
endclass : axi5_sanity_test


// =====================================================================
// 3. RANDOMIZED BURST TEST
// =====================================================================
class axi5_rand_burst_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_rand_burst_test)

  function new(string name = "axi5_rand_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_rand_burst_seq #(64, 64, 4) seq = axi5_rand_burst_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Random Burst Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Random Burst Test");
  endtask
endclass : axi5_rand_burst_test


// =====================================================================
// 4. NARROW TRANSFER TEST
// =====================================================================
class axi5_narrow_transfer_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_narrow_transfer_test)

  function new(string name = "axi5_narrow_transfer_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_narrow_transfer_seq #(64, 64, 4) seq = axi5_narrow_transfer_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Narrow Transfer Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Narrow Transfer Test");
  endtask
endclass : axi5_narrow_transfer_test


// =====================================================================
// 5. UNALIGNED ADDRESS TEST
// =====================================================================
class axi5_unaligned_addr_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_unaligned_addr_test)

  function new(string name = "axi5_unaligned_addr_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_unaligned_addr_seq #(64, 64, 4) seq = axi5_unaligned_addr_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Unaligned Address Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Unaligned Address Test");
  endtask
endclass : axi5_unaligned_addr_test


// =====================================================================
// 6. WRAP BURST TEST
// =====================================================================
class axi5_wrap_burst_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_wrap_burst_test)

  function new(string name = "axi5_wrap_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_wrap_burst_seq #(64, 64, 4) seq = axi5_wrap_burst_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Wrap Burst Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Wrap Burst Test");
  endtask
endclass : axi5_wrap_burst_test


// =====================================================================
// 7. AXI5 ATOMIC OPERATIONS TEST
// =====================================================================
class axi5_atomic_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_atomic_test)

  function new(string name = "axi5_atomic_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_atomic_seq #(64, 64, 4) seq = axi5_atomic_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Atomic Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Atomic Test");
  endtask
endclass : axi5_atomic_test


// =====================================================================
// 8. DATA POISONING TEST
// =====================================================================
class axi5_poison_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_poison_test)

  function new(string name = "axi5_poison_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_poison_seq #(64, 64, 4) seq = axi5_poison_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Data Poisoning Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Data Poisoning Test");
  endtask
endclass : axi5_poison_test


// =====================================================================
// 9. OUT OF ORDER PIPELINE STRESS TEST
// =====================================================================
class axi5_out_of_order_test extends axi5_base_test #(64, 64, 4);
  `uvm_component_utils(axi5_out_of_order_test)

  function new(string name = "axi5_out_of_order_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi5_out_of_order_seq #(64, 64, 4) seq = axi5_out_of_order_seq #(64, 64, 4)::type_id::create("seq");
    phase.raise_objection(this, "Starting Out-Of-Order Test");
    seq.start(m_env.m_agent.sqr);
    #100ns;
    phase.drop_objection(this, "Finishing Out-Of-Order Test");
  endtask
endclass : axi5_out_of_order_test

`endif // AXI5_BASE_TEST_SV
