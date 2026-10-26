module PH1P_LOGIC_ERAM #(
    parameter integer DATA_WIDTH_A = 16,
    parameter integer DATA_WIDTH_B = 16,
    parameter integer ADDR_WIDTH_A = 12,
    parameter integer ADDR_WIDTH_B = 12,
    parameter integer DATA_DEPTH_A = 3600,
    parameter integer DATA_DEPTH_B = 3600,
    parameter MODE = "DP",
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "OUTREG",
    parameter WRITEMODE_A = "NORMAL",
    parameter WRITEMODE_B = "NORMAL",
    parameter IMPLEMENT = "20K(FAST)",
    parameter ECC_ENCODE = "DISABLE",
    parameter ECC_DECODE = "DISABLE",
    parameter CLKMODE = "ASYNC",
    parameter SSROVERCE = "DISABLE",
    parameter OREGSET_A = "RESET",
    parameter OREGSET_B = "RESET",
    parameter RESETMODE_A = "ASYNC",
    parameter RESETMODE_B = "ASYNC",
    parameter ASYNC_RESET_RELEASE_A = "ASYNC",
    parameter ASYNC_RESET_RELEASE_B = "ASYNC",
    parameter INIT_FILE = "NONE",
    parameter FILL_ALL = "NONE"
) (
    input  wire [DATA_WIDTH_A-1:0] dia,
    input  wire [DATA_WIDTH_B-1:0] dib,
    input  wire [ADDR_WIDTH_A-1:0] addra,
    input  wire [ADDR_WIDTH_B-1:0] addrb,
    input  wire cea,
    input  wire ceb,
    input  wire ocea,
    input  wire oceb,
    input  wire wea,
    input  wire web,
    input  wire bea,
    input  wire beb,
    input  wire clka,
    input  wire clkb,
    input  wire rsta,
    input  wire rstb,
    output reg [DATA_WIDTH_A-1:0] doa,
    output reg [DATA_WIDTH_B-1:0] dob,
    input  wire [31:0] ecc_sbiterrinj,
    input  wire [31:0] ecc_dbiterrinj,
    output wire ecc_sbiterr,
    output wire ecc_dbiterr
);
    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    integer i;
    initial begin
        for (i = 0; i < DATA_DEPTH_A; i = i + 1)
            mem[i] = {DATA_WIDTH_A{1'b0}};
        doa = {DATA_WIDTH_A{1'b0}};
        dob = {DATA_WIDTH_B{1'b0}};
    end
    always @(posedge clka) begin
        if (rsta)
            doa <= {DATA_WIDTH_A{1'b0}};
        else if (cea && wea)
            mem[addra] <= dia;
    end
    always @(posedge clkb) begin
        if (rstb)
            dob <= {DATA_WIDTH_B{1'b0}};
        else if (ceb && oceb)
            dob <= mem[addrb];
    end
    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;
endmodule
