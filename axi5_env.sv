// =========================================================================
// File Name   : axi5_env.sv
// Description : Parameterized UVM Environment wrapping the AXI5 Master Agent
// =========================================================================

`ifndef AXI5_ENV_SV
`define AXI5_ENV_SV

class axi5_env #(
  parameter int AW = 64, // Address Width
  parameter int DW = 64, // Data Width
  parameter int IW = 4   // ID Tag Width
) extends uvm_env;

  // =====================================================================
  // 1. CLASS PROPERTIES & UTILITIES
  // =====================================================================
  `uvm_component_param_utils(axi5_env #(AW, DW, IW))

  // Component Handles
  axi5_agent      #(AW, DW, IW) m_agent;
  axi5_scoreboard #(AW, DW, IW) m_scb;

  // Configuration Object Handle
  axi5_agt_config m_agt_cfg;

  // =====================================================================
  // 2. CONSTRUCTOR
  // =====================================================================
  function new(string name = "axi5_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  // =====================================================================
  // 3. UVM PHASES
  // =====================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // 1. Check if the configuration object has already been supplied by the test
    if (!uvm_config_db#(axi5_agt_config)::get(this, "", "axi5_agt_config", m_agt_cfg)) begin
      `uvm_info("ENV_CONFIG_WARN", "No agent configuration object found in config_db. Creating a default active config.", UVM_MEDIUM)
      m_agt_cfg = axi5_agt_config::type_id::create("m_agt_cfg");
      m_agt_cfg.is_active = UVM_ACTIVE;
    end

    // 2. Propagate configuration object down to the child agent's scope
    uvm_config_db#(axi5_agt_config)::set(this, "m_agent*", "axi5_agt_config", m_agt_cfg);

    // 3. Build Agent and Scoreboard components
    m_agent = axi5_agent      #(AW, DW, IW)::type_id::create("m_agent", this);
    m_scb   = axi5_scoreboard #(AW, DW, IW)::type_id::create("m_scb", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // 4. Connect the Agent's Monitor Analysis Port to the Scoreboard Import
    m_agent.mon.item_collected_port.connect(m_scb.item_collected_export);

    `uvm_info("AXI5_ENV", "Successfully connected m_agent.mon.item_collected_port to m_scb.item_collected_export.", UVM_LOW)
  endfunction : connect_phase

endclass : axi5_env

`endif // AXI5_ENV_SV
