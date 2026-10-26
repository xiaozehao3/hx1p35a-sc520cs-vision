`timescale 1ns/1ps

module tb_osd_char_rom_dp;
    reg clk = 1'b0;
    reg en = 1'b0;
    reg [7:0] char_a = 8'd0;
    reg [7:0] char_b = 8'd0;
    reg [3:0] row = 4'd0;
    wire [15:0] bits_a;
    wire [15:0] bits_b;
    wire [15:0] ref_a;
    wire [15:0] ref_b;
    integer code;
    integer y;
    integer checks = 0;

    always #5 clk = ~clk;

    osd_char_rom_dp dut (
        .I_clk(clk), .I_en(en),
        .I_char_a(char_a), .I_char_b(char_b), .I_row(row),
        .O_bits_a(bits_a), .O_bits_b(bits_b)
    );

    osd_char_lib ref_rom_a (
        .I_char(char_a), .I_row(row), .O_row_bits(ref_a)
    );

    osd_char_lib ref_rom_b (
        .I_char(char_b), .I_row(row), .O_row_bits(ref_b)
    );

    initial begin
        for (code = 0; code < 256; code = code + 1) begin
            for (y = 0; y < 16; y = y + 1) begin
                @(negedge clk);
                en = 1'b1;
                char_a = code[7:0];
                char_b = code[7:0] ^ 8'hA5;
                row = y[3:0];
                @(posedge clk);
                #1;
                checks = checks + 2;
                if (bits_a !== ref_a || bits_b !== ref_b) begin
                    $display("Mismatch code=%02h row=%0d A=%04h/%04h B=%04h/%04h",
                             char_a, row, bits_a, ref_a, bits_b, ref_b);
                    $fatal(1);
                end
            end
        end
        en = 1'b0;
        $display("PASS: %0d synchronous glyph-row comparisons", checks);
        $finish;
    end
endmodule
