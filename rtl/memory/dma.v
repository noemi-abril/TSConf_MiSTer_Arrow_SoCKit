// This module serves direct DRAM-to-device data transfer

// to do
// - probably add the extra 8 bit counter for number of bursts

module dma
(
	// clocks
	input wire clk,
	input wire c2,
	input wire reset,

	// interface
	input  wire [8:0] dmaport_wr,
	output wire dma_act,
	output reg  [15:0] data,
	output wire [ 7:0] wraddr,
	output wire int_start,

	// Z80
	input  wire [7:0] zdata,

	// DRAM interface
	output wire [20:0] dram_addr,
	input  wire [15:0] dram_rddata,
	output wire [15:0] dram_wrdata,
	output wire dram_req,
	output wire dram_rnw,
	input  wire dram_next,

	// SPI interface
	input  wire [7:0] spi_rddata,
	output wire [7:0] spi_wrdata,
	output wire spi_req,
	input  wire spi_stb,

	// IDE interface
	input  wire [15:0] ide_in,
	output wire [15:0] ide_out,
	output wire ide_req,
	output wire ide_rnw,
	input  wire ide_stb,

	// CRAM interface
	output wire cram_we,

	// SFILE interface
	output wire sfile_we
);

// mode:
//  0 - device to RAM (read from device)
//  1 - RAM to device (write to device)

  assign wraddr = d_addr[7:0];

  wire dma_saddrl = dmaport_wr[0];
  wire dma_saddrh = dmaport_wr[1];
  wire dma_saddrx = dmaport_wr[2];
  wire dma_daddrl = dmaport_wr[3];
  wire dma_daddrh = dmaport_wr[4];
  wire dma_daddrx = dmaport_wr[5];
  wire dma_len    = dmaport_wr[6];
  wire dma_launch = dmaport_wr[7];
  wire dma_num    = dmaport_wr[8];

// DRAM
  assign dram_addr = state_rd ? ((!dv_blt || !phase_blt) ? s_addr : d_addr) : d_addr;
  assign dram_wrdata = data;
  assign dram_req = dma_act && state_mem;
  assign dram_rnw = state_rd;

// devices
  localparam DEV_RAM = 3'b0001;
  localparam DEV_BLT1 = 4'b1001;
  localparam DEV_BLT2 = 4'b0110;
  localparam DEV_FIL = 4'b0100;
  localparam DEV_SPI = 3'b010;
  localparam DEV_IDE = 3'b011;
  localparam DEV_CRM = 4'b1100;
  localparam DEV_SFL = 4'b1101;
  localparam DEV_FDD = 4'b0101;

  wire [2:0] dev_bid = device[2:0];   // bidirectional
  wire [3:0] dev_uni = device[3:0];   // unidirectional
  wire dma_wnr = device[3];           // 0 - device to RAM / 1 - RAM to device
  
  wire dv_ram = (dev_uni == DEV_RAM) || (dev_uni == DEV_BLT1) || (dev_uni == DEV_BLT2) || (dev_uni == DEV_FIL);
  wire dv_blt = (dev_uni == DEV_BLT1) || (dev_uni == DEV_BLT2);
  wire dv_fil = (dev_uni == DEV_FIL);
  wire dv_spi = (dev_bid == DEV_SPI);
  wire dv_ide = (dev_bid == DEV_IDE);
  wire dv_crm = (dev_uni == DEV_CRM);
  wire dv_sfl = (dev_uni == DEV_SFL);

  wire dev_req = dma_act && state_dev;
  wire dev_stb = cram_we || sfile_we || ide_int_stb || (spi_int_stb && bsel && dma_act);

  assign cram_we = dev_req && dv_crm && state_wr;
  assign sfile_we = dev_req && dv_sfl && state_wr;

  // SPI
  wire spi_int_stb = dv_spi && spi_stb;
  assign spi_wrdata = {8{state_rd}} | (bsel ? data[15:8] : data[7:0]);  // send FF on read cycles
  assign spi_req = dev_req && dv_spi;
  
  // IDE
  wire ide_int_stb = dv_ide && ide_stb;
  assign ide_out = data;
  assign ide_req = dev_req && dv_ide;
  assign ide_rnw = state_rd;

  // blitter
  wire [15:0] blt_rddata = (dev_uni == DEV_BLT1) ? blt1_rddata : blt2_rddata;

  // Mode 1
  wire [15:0] blt1_rddata = {blt1_data_h, blt1_data_l};
  wire [7:0] blt1_data_h = dma_asz ? blt1_data32 : {blt1_data3, blt1_data2};
  wire [7:0] blt1_data_l = dma_asz ? blt1_data10 : {blt1_data1, blt1_data0};
  wire [7:0] blt1_data32 = |data[15:8] ? data[15:8] : dram_rddata[15:8];
  wire [7:0] blt1_data10 = |data[7:0] ? data[7:0] : dram_rddata[7:0];
  wire [3:0] blt1_data3 = |data[15:12] ? data[15:12] : dram_rddata[15:12];
  wire [3:0] blt1_data2 = |data[11:8] ? data[11:8] : dram_rddata[11:8];
  wire [3:0] blt1_data1 = |data[7:4] ? data[7:4] : dram_rddata[7:4];
  wire [3:0] blt1_data0 = |data[3:0] ? data[3:0] : dram_rddata[3:0];

  // Mode 2
  wire [15:0] blt2_rddata = {blt2_data_1, blt2_data_0};
  wire [7:0] blt2_data_1 = dma_asz ? blt2_8_data1 : {blt2_4_data3, blt2_4_data2};
  wire [7:0] blt2_data_0 = dma_asz ? blt2_8_data0 : {blt2_4_data1, blt2_4_data0};

  localparam msk = 8'd255;

  wire [8:0] sum80 = data[7:0] + dram_rddata[7:0];
  wire [8:0] sum81 = data[15:8] + dram_rddata[15:8];

  wire [4:0] sum40 = data[3:0] + dram_rddata[3:0];
  wire [4:0] sum41 = data[7:4] + dram_rddata[7:4];
  wire [4:0] sum42 = data[11:8] + dram_rddata[11:8];
  wire [4:0] sum43 = data[15:12] + dram_rddata[15:12];

  wire [7:0] blt2_8_data0 = ((sum80 > msk) && dma_opt) ? msk : sum80[7:0];
  wire [7:0] blt2_8_data1 = ((sum81 > msk) && dma_opt) ? msk : sum81[7:0];

  wire [3:0] blt2_4_data0 = ((sum40 > msk[3:0]) && dma_opt) ? msk[3:0] : sum40[3:0];
  wire [3:0] blt2_4_data1 = ((sum41 > msk[3:0]) && dma_opt) ? msk[3:0] : sum41[3:0];
  wire [3:0] blt2_4_data2 = ((sum42 > msk[3:0]) && dma_opt) ? msk[3:0] : sum42[3:0];
  wire [3:0] blt2_4_data3 = ((sum43 > msk[3:0]) && dma_opt) ? msk[3:0] : sum43[3:0];

// data aquiring
  always @(posedge clk)
    if (state_rd)
    begin
      if (dram_next)
        data <= (dv_blt && phase_blt) ? blt_rddata : dram_rddata;

      if (ide_int_stb)
        data <= ide_in;

      if (spi_int_stb)
      begin
        if (bsel)
          data[15:8] <= spi_rddata;
        else
          data[7:0] <= spi_rddata;
      end

    end

// states
  wire state_rd = ~phase;
  wire state_wr = phase;
  wire state_dev = !dv_ram && (dma_wnr ^ !phase);
  wire state_mem = dv_ram || (dma_wnr ^ phase);

// states processing
  wire phase_end = phase_end_ram || phase_end_dev;
  wire phase_end_ram = state_mem && dram_next && !blt_hook;
  wire phase_end_dev = state_dev && dev_stb;
  wire blt_hook = dv_blt && !phase_blt && !phase;
  wire fil_hook = dv_fil && phase;
  wire phase_blt_end = state_mem && dram_next && !phase;

  // blitter cycles:
  //  phase  phase_blt  blt_hook  activity
  //  0    0      1      read src
  //  0    1      0      read dst
  //  1    1      0      write dst

  reg [3:0] device;
  reg dma_salgn;
  reg dma_dalgn;
  reg dma_asz;
  reg phase;        // 0 - read / 1 - write
  reg phase_blt;      // 0 - source / 1 - destination
  reg bsel;        // 0 - lsb / 1 - msb
  reg dma_opt;

  always @(posedge clk)
  if (dma_launch)      // write to DMACtrl - launch of DMA burst
  begin
    dma_opt <= zdata[6];
    dma_salgn <= zdata[5];
    dma_dalgn <= zdata[4];
    dma_asz <= zdata[3];
    device <= {zdata[7], zdata[2:0]};
    phase <= 1'b0;
    phase_blt <= 1'b0;
    bsel <= 1'b0;
  end

  else
  begin
    if (phase_end && !fil_hook)
      phase <= ~phase;
    if (phase_blt_end)
      phase_blt <= ~phase_blt;
    if (spi_int_stb)
      bsel <= ~bsel;
  end


// counter processing
  reg [7:0] b_len;    // length of burst
  reg [7:0] b_num;    // number of bursts
  reg [8:0] n_ctr;    // counter for bursts
  wire [8:0] n_ctr_dec = n_ctr - next_burst;
  assign dma_act = !n_ctr[8];
  reg [7:0] b_ctr;    // counter for cycles in burst

  wire [7:0] b_ctr_next = next_burst ? b_len : b_ctr_dec[7:0];
  wire [8:0] b_ctr_dec = {1'b0, b_ctr[7:0]} - 9'b1;
  wire next_burst = b_ctr_dec[8];

  always @(posedge clk)
    if (reset)
      n_ctr[8] <= 1'b1;

    else if (dma_launch)
    begin
      b_ctr <= b_len;
      n_ctr <= {1'b0, b_num};
    end

    else if (phase && phase_end)    // cycle processed
    begin
      b_ctr <= b_ctr_next;
      n_ctr <= n_ctr_dec;
    end


// loading of burst parameters
  always @(posedge clk)
  begin
    if (dma_len)
      b_len <= zdata;

    if (dma_num)
      b_num <= zdata;
  end


// address processing

  // source
  wire [20:0] s_addr_next = {s_addr_next_h[13:1], s_addr_next_m, s_addr_next_l[6:0]};
  wire [13:0] s_addr_next_h = s_addr[20:7] + s_addr_add_h;
  wire [1:0] s_addr_add_h = dma_salgn ? {next_burst && dma_asz, next_burst && !dma_asz} : {s_addr_inc_l[8], 1'b0};
  wire s_addr_next_m = dma_salgn ? (dma_asz ? s_addr_next_l[7] : s_addr_next_h[0]) : s_addr_inc_l[7];
  wire [7:0] s_addr_next_l = (dma_salgn && next_burst) ? s_addr_r : s_addr_inc_l[7:0];
  wire [8:0] s_addr_inc_l = {1'b0, s_addr[7:0]} + 9'b1;

  reg [20:0] s_addr;    // current source address
  reg [7:0] s_addr_r;   // source lower address

  always @(posedge clk)
    if ((dram_next || dev_stb) && state_rd && (!dv_blt || !phase_blt))      // increment RAM source addr
      s_addr <= s_addr_next;

    else
    begin
      if (dma_saddrl)
      begin
        s_addr[6:0] <= zdata[7:1];
        s_addr_r[6:0] <= zdata[7:1];
      end

      if (dma_saddrh)
      begin
        s_addr[12:7] <= zdata[5:0];
        s_addr_r[7] <= zdata[0];
      end

      if (dma_saddrx)
        s_addr[20:13] <= zdata;
    end

  // destination
  wire [20:0] d_addr_next = {d_addr_next_h[13:1], d_addr_next_m, d_addr_next_l[6:0]};
  wire [13:0] d_addr_next_h = d_addr[20:7] + d_addr_add_h;
  wire [1:0] d_addr_add_h = dma_dalgn ? {next_burst && dma_asz, next_burst && !dma_asz} : {d_addr_inc_l[8], 1'b0};
  wire d_addr_next_m = dma_dalgn ? (dma_asz ? d_addr_next_l[7] : d_addr_next_h[0]) : d_addr_inc_l[7];
  wire [7:0] d_addr_next_l = (dma_dalgn && next_burst) ? d_addr_r : d_addr_inc_l[7:0];
  wire [8:0] d_addr_inc_l = {1'b0, d_addr[7:0]} + 9'b1;

  reg [20:0] d_addr;    // current dest address
  reg [7:0] d_addr_r;   // dest lower address

  always @(posedge clk)
    if ((dram_next || dev_stb) && state_wr)      // increment RAM dest addr
      d_addr <= d_addr_next;
    else
    begin
      if (dma_daddrl)
      begin
        d_addr[6:0] <= zdata[7:1];
        d_addr_r[6:0] <= zdata[7:1];
      end

      if (dma_daddrh)
      begin
        d_addr[12:7] <= zdata[5:0];
        d_addr_r[7] <= zdata[0];
      end

      if (dma_daddrx)
        d_addr[20:13] <= zdata;
    end

  // INT generation
  reg dma_act_r;
  always @(posedge clk)
    dma_act_r <= dma_act && ~reset;

  assign int_start = !dma_act && dma_act_r;

endmodule
