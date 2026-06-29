// =========================================================================
// File Name   : axi5_drv.sv
// Description : Parameterized UVM Driver for AMBA AXI5 Master Agent.
// =========================================================================

`ifndef AXI5_DRV_SV
`define AXI5_DRV_SV

class axi5_drv #(
  parameter int AW = 64, // Address Width
  parameter int DW = 64, // Data Width
  parameter int IW = 4   // ID Tag Width
) extends uvm_driver #(axi5_xtn #(AW, DW, IW));

  // =====================================================================
  // 1. CLASS PROPERTIES & CONFIGURATION
  // =====================================================================
  `uvm_component_param_utils(axi5_drv #(AW, DW, IW))

  // Virtual Interface to drive pin-level transitions
  virtual axi5_if #(AW, DW, IW) vif;

  // =====================================================================
  // 2. CONSTRUCTOR
  // =====================================================================
  function new(string name = "axi5_drv", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  // =====================================================================
  // 3. UVM PHASES
  // =====================================================================
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Fetch virtual interface configuration
    if (!uvm_config_db#(virtual axi5_if #(AW, DW, IW))::get(this, "", "vif", vif)) begin
      `uvm_fatal("DRV_VIF_ERR", "Could not locate the virtual interface wrapper for the driver!")
    end
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    // 1. Initialize interface signals to secure inactive states on reset
    reset_signals();

    // 2. Main processing loop
    forever begin
      // Wait for reset to clear before accepting items
      wait(vif.ARESETn == 1'b1);

      seq_item_port.get_next_item(req);
      `uvm_info("AXI5_DRV", $sformatf("Processing transaction:\n%s", req.sprint()), UVM_HIGH)

      if (req.xact_type == WRITE) begin
        drive_write(req);
      end else begin
        drive_read(req);
      end

      seq_item_port.item_done();
    end
  endtask : run_phase

  // =====================================================================
  // 4. SIGNALS RESET CONTROLLER (Synchronized to Capital Letters)
  // =====================================================================
  virtual task reset_signals();
    // Drive default inactive states via clocking block outputs to prevent glitches
    vif.driver_cb.AWVALID <= 1'b0;
    vif.driver_cb.WVALID  <= 1'b0;
    vif.driver_cb.BREADY  <= 1'b0;
    vif.driver_cb.ARVALID <= 1'b0;
    vif.driver_cb.RREADY  <= 1'b0;

    vif.driver_cb.AWID    <= '0;
    vif.driver_cb.AWADDR  <= '0;
    vif.driver_cb.AWLEN   <= '0;
    vif.driver_cb.AWSIZE  <= '0;
    vif.driver_cb.AWBURST <= '0;
    vif.driver_cb.AWATOP  <= '0;

    vif.driver_cb.WDATA   <= '0;
    vif.driver_cb.WSTRB   <= '0;
    vif.driver_cb.WLAST   <= 1'b0;
    vif.driver_cb.WPOISON <= 1'b0;

    vif.driver_cb.ARID    <= '0;
    vif.driver_cb.ARADDR  <= '0;
    vif.driver_cb.ARLEN   <= '0;
    vif.driver_cb.ARSIZE  <= '0;
    vif.driver_cb.ARBURST <= '0;
  endtask : reset_signals

  // =====================================================================
  // 5. WRITE TRANSACTION SEQUENCE (PIPELINED & PARALLEL)
  // =====================================================================
  virtual task drive_write(axi5_xtn #(AW, DW, IW) tx);
    // In actual AXI5 hardware, Write Address (AW) and Write Data (W) operate
    // completely independently. We split them into concurrent threads using fork-join.
    fork
      drive_write_address(tx);
      drive_write_data(tx);
    join

    // Once both transactions are launched, wait for the Slave's completion response
    collect_write_response(tx);
  endtask : drive_write

  // AW Channel Thread
  virtual task drive_write_address(axi5_xtn #(AW, DW, IW) tx);
    @(vif.driver_cb);
    vif.driver_cb.AWID    <= tx.id;
    vif.driver_cb.AWADDR  <= tx.addr;
    vif.driver_cb.AWLEN   <= tx.len;
    vif.driver_cb.AWSIZE  <= tx.size;
    vif.driver_cb.AWBURST <= tx.burst_type;
    vif.driver_cb.AWATOP  <= tx.atop; // AXI5 Atomic operations channel mapping
    vif.driver_cb.AWVALID <= 1'b1;

    // SVA compatibility handshake loop
    do begin
      @(vif.driver_cb);
    end while (!vif.driver_cb.AWREADY);

    vif.driver_cb.AWVALID <= 1'b0;
  endtask : drive_write_address

  // W Channel Thread
  virtual task drive_write_data(axi5_xtn #(AW, DW, IW) tx);
    foreach (tx.data[i]) begin
      @(vif.driver_cb);
      vif.driver_cb.WDATA   <= tx.data[i];
      vif.driver_cb.WSTRB   <= tx.strb[i];
      vif.driver_cb.WLAST   <= (i == tx.len) ? 1'b1 : 1'b0;
      vif.driver_cb.WPOISON <= tx.poison[i]; // AXI5 per-beat data poisoning flag
      vif.driver_cb.WVALID  <= 1'b1;

      do begin
        @(vif.driver_cb);
      end while (!vif.driver_cb.WREADY);
    end
    vif.driver_cb.WVALID  <= 1'b0;
    vif.driver_cb.WLAST   <= 1'b0;
  endtask : drive_write_data

  // B Channel Thread
  virtual task collect_write_response(axi5_xtn #(AW, DW, IW) tx);
    vif.driver_cb.BREADY <= 1'b1;

    do begin
      @(vif.driver_cb);
    end while (!vif.driver_cb.BVALID);

    // Capture response data back into UVM Transaction Object for scoreboard evaluation
    tx.bresp = vif.driver_cb.BRESP;
    vif.driver_cb.BREADY <= 1'b0;
  endtask : collect_write_response

  // =====================================================================
  // 6. READ TRANSACTION SEQUENCE
  // =====================================================================
  virtual task drive_read(axi5_xtn #(AW, DW, IW) tx);
    // Phase A: Launch Read Address Request
    @(vif.driver_cb);
    vif.driver_cb.ARID    <= tx.id;
    vif.driver_cb.ARADDR  <= tx.addr;
    vif.driver_cb.ARLEN   <= tx.len;
    vif.driver_cb.ARSIZE  <= tx.size;
    vif.driver_cb.ARBURST <= tx.burst_type;
    vif.driver_cb.ARVALID <= 1'b1;

    do begin
      @(vif.driver_cb);
    end while (!vif.driver_cb.ARREADY);
    vif.driver_cb.ARVALID <= 1'b0;

    // Phase B: Collect and Handshake Read Data Beats
    vif.driver_cb.RREADY <= 1'b1;
    tx.data   = new[tx.len + 1];
    tx.rresp  = new[tx.len + 1];
    tx.poison = new[tx.len + 1];

    for (int i = 0; i <= tx.len; i++) begin
      do begin
        @(vif.driver_cb);
      end while (!vif.driver_cb.RVALID);

      // Sample incoming data payloads synchronously via the clocking block
      tx.data[i]   = vif.driver_cb.RDATA;
      tx.rresp[i]  = vif.driver_cb.RRESP;
      tx.poison[i] = vif.driver_cb.RPOISON; // Capture incoming AXI5 data corruption indicator
    end
    vif.driver_cb.RREADY <= 1'b0;
  endtask : drive_read

endclass : axi5_drv

`endif // AXI5_DRV_SV
