// =========================================================================
// File Name   : axi5_mon.sv
// Description : Parameterized Passive UVM Monitor for AMBA AXI5 Agent.
// =========================================================================


`ifndef AXI5_MON_SV
`define AXI5_MON_SV

class axi5_mon #(
  parameter int AW = 64,
  parameter int DW = 64,
  parameter int IW = 4
) extends uvm_monitor;

  `uvm_component_param_utils(axi5_mon #(AW, DW, IW))

  virtual axi5_if #(AW, DW, IW) vif;
  uvm_analysis_port #(axi5_xtn #(AW, DW, IW)) item_collected_port;

  // Track active write transactions per ID
  protected axi5_xtn #(AW, DW, IW) pending_aw_q[$];
  protected axi5_xtn #(AW, DW, IW) write_assemblers[bit [IW-1:0]];
  protected int                     write_beat_cnt[bit [IW-1:0]];

  protected axi5_xtn #(AW, DW, IW) waiting_for_b_resp_q[bit [IW-1:0]][$];
  protected axi5_xtn #(AW, DW, IW) waiting_for_r_data_q[bit [IW-1:0]][$];

  function new(string name = "axi5_mon", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi5_if #(AW, DW, IW))::get(this, "", "vif", vif))
      `uvm_fatal("MON_VIF_ERR", "Could not locate virtual interface!");
  endfunction

  virtual task run_phase(uvm_phase phase);
    fork
      monitor_write_address();
      monitor_write_data();
      monitor_write_response();
      monitor_read_address();
      monitor_read_data_and_response();
    join
  endtask

  // Thread: Write Address
  virtual task monitor_write_address();
    axi5_xtn #(AW, DW, IW) tx;
    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.AWVALID && vif.monitor_cb.AWREADY) begin
        tx = axi5_xtn #(AW, DW, IW)::type_id::create("tx_aw");
        tx.id         = vif.monitor_cb.AWID;
        tx.addr       = vif.monitor_cb.AWADDR;
        tx.len        = vif.monitor_cb.AWLEN;
        tx.xact_type  = WRITE;
        pending_aw_q.push_back(tx);
      end
    end
  endtask

  // Thread: Per-ID Write Data Assembler
  virtual task monitor_write_data();
    bit [IW-1:0] wid;
    axi5_xtn #(AW, DW, IW) tx;
    int idx;

    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.WVALID && vif.monitor_cb.WREADY) begin
        // In AXI5, if WID is not present, we assume WDATA follows AW sequence
        // OR use a fixed ID if your bus implementation enforces it.
        // Assuming WID is sampled from the interface:
        wid = vif.monitor_cb.WID;

        if (!write_assemblers.exists(wid)) begin
          if (pending_aw_q.size() > 0) begin
            write_assemblers[wid] = pending_aw_q.pop_front();
            write_beat_cnt[wid] = 0;
            write_assemblers[wid].data   = new[write_assemblers[wid].len + 1];
            write_assemblers[wid].strb   = new[write_assemblers[wid].len + 1];
          end else begin
            `uvm_error("AXI5_MON_W", "WDATA sampled without matching AWID in queue!");
            continue;
          end
        end

        idx = write_beat_cnt[wid];
        write_assemblers[wid].data[idx] = vif.monitor_cb.WDATA;
        write_assemblers[wid].strb[idx] = vif.monitor_cb.WSTRB;

        if (vif.monitor_cb.WLAST) begin
          waiting_for_b_resp_q[wid].push_back(write_assemblers[wid]);
          write_assemblers.delete(wid);
          write_beat_cnt.delete(wid);
        end else begin
          write_beat_cnt[wid]++;
        end
      end
    end
  endtask

  // Thread D: Monitor Write Responses (B)
  virtual task monitor_write_response();
    bit [IW-1:0] resp_id;
    axi5_xtn #(AW, DW, IW) completed_tx;

    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.BVALID && vif.monitor_cb.BREADY) begin
        resp_id = vif.monitor_cb.BID;

        if (waiting_for_b_resp_q.exists(resp_id) && waiting_for_b_resp_q[resp_id].size() > 0) begin
          completed_tx = waiting_for_b_resp_q[resp_id].pop_front();
          completed_tx.bresp = vif.monitor_cb.BRESP;

          // Broadcast fully completed transaction object
          item_collected_port.write(completed_tx);
          `uvm_info("AXI5_MON_B", $sformatf("Write Transaction ID=0x%0h completed with response: %0s", completed_tx.id, completed_tx.bresp), UVM_MEDIUM);

          if (waiting_for_b_resp_q[resp_id].size() == 0) begin
            waiting_for_b_resp_q.delete(resp_id);
          end
        end else begin
          `uvm_error("AXI5_MON_B_ERR", $sformatf("Sampled BVALID for BID=0x%0h on bus but found no matching AW transaction in flight!", resp_id));
        end
      end
    end
  endtask : monitor_write_response

  // =====================================================================
  // 6. READ CHANNEL TRACKING ENGINE (OoO Interleaving Supported)
  // =====================================================================

  // Thread E: Monitor Read Addresses (AR)
  virtual task monitor_read_address();
    axi5_xtn #(AW, DW, IW) tx;

    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.ARVALID && vif.monitor_cb.ARREADY) begin
        tx = axi5_xtn #(AW, DW, IW)::type_id::create("tx_ar");
        tx.id         = vif.monitor_cb.ARID;
        tx.addr       = vif.monitor_cb.ARADDR;
        tx.len        = vif.monitor_cb.ARLEN;
        tx.size       = vif.monitor_cb.ARSIZE;
        tx.burst_type = axi5_burst_e'(vif.monitor_cb.ARBURST);
        tx.xact_type  = READ;

        waiting_for_r_data_q[tx.id].push_back(tx);
        `uvm_info("AXI5_MON_AR", $sformatf("Sampled ARADDR=0x%0h, ID=0x%0h", tx.addr, tx.id), UVM_HIGH);
      end
    end
  endtask : monitor_read_address

  // Thread F: Monitor and Assemble Out-of-Order Read Data (R)
  virtual task monitor_read_data_and_response();
    axi5_xtn #(AW, DW, IW) active_r_assemblers[bit [IW-1:0]];
    int r_beat_cnt[bit [IW-1:0]];
    bit [IW-1:0] rid;
    int idx;

    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.RVALID && vif.monitor_cb.RREADY) begin
        rid = vif.monitor_cb.RID;

        // Fetch corresponding base transaction if this is the starting beat for this RID
        if (!active_r_assemblers.exists(rid)) begin
          if (waiting_for_r_data_q.exists(rid) && waiting_for_r_data_q[rid].size() > 0) begin
            active_r_assemblers[rid] = waiting_for_r_data_q[rid].pop_front();
            r_beat_cnt[rid] = 0;

            // Allocate payload arrays matching the request ARLEN parameter
            active_r_assemblers[rid].data   = new[active_r_assemblers[rid].len + 1];
            active_r_assemblers[rid].rresp  = new[active_r_assemblers[rid].len + 1];
            active_r_assemblers[rid].poison = new[active_r_assemblers[rid].len + 1];
          end else begin
            `uvm_error("AXI5_MON_R_ERR", $sformatf("Read Data beat with RID=0x%0h sampled without a matching AR address request!", rid));
            continue;
          end
        end

        // Sample data beat metrics
        idx = r_beat_cnt[rid];
        active_r_assemblers[rid].data[idx]   = vif.monitor_cb.RDATA;
        active_r_assemblers[rid].rresp[idx]  = vif.monitor_cb.RRESP;
        active_r_assemblers[rid].poison[idx] = vif.monitor_cb.RPOISON; // Catch AXI5 memory read poisoning

        if (vif.monitor_cb.RLAST) begin
          // Safety alignment check
          if (idx != active_r_assemblers[rid].len) begin
            `uvm_warning("AXI5_MON_R_WARN", $sformatf("RLAST asserted on beat %0d, but ARLEN requested %0d beats!", idx+1, active_r_assemblers[rid].len+1));
          end

          // Broadcast completed read transaction
          item_collected_port.write(active_r_assemblers[rid]);
          `uvm_info("AXI5_MON_R", $sformatf("Read Transaction ID=0x%0h complete with %0d beats broadcasted", rid, idx+1), UVM_MEDIUM);

          // Clear tracking registers
          active_r_assemblers.delete(rid);
          r_beat_cnt.delete(rid);
          if (waiting_for_r_data_q[rid].size() == 0) begin
            waiting_for_r_data_q.delete(rid);
          end
        end else begin
          r_beat_cnt[rid]++;
        end
      end
    end
  endtask : monitor_read_data_and_response

endclass : axi5_mon

`endif // AXI5_MON_SV
