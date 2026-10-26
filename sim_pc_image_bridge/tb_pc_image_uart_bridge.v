`timescale 1ns/1ps
module tb_pc_image_uart_bridge;
    localparam integer CLK_HZ = 10_000_000;
    localparam integer BAUD = 1_000_000;
    localparam integer BIT_NS = 1000;

    reg uart_clk = 1'b0;
    reg video_clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire tlast, tuser, tvalid, active, image_valid;
    wire [95:0] tdata;
    wire [15:0] rx_count, ok_count, error_count;

    always #50 uart_clk = ~uart_clk;
    always #50 video_clk = ~video_clk;

    pc_image_uart_bridge #(
        .IMAGE_WIDTH(4), .IMAGE_HEIGHT(2),
        .DISPLAY_WIDTH(32), .DISPLAY_HEIGHT(16),
        .CLOCK_HZ(CLK_HZ), .BAUD(BAUD)
    ) dut (
        .I_uart_clk(uart_clk), .I_video_clk(video_clk), .I_rst_n(rst_n),
        .I_uart_rx(uart_rx), .I_enable(1'b1), .I_tready(1'b1),
        .O_tlast(tlast), .O_tuser(tuser), .O_tdata(tdata),
        .O_tvalid(tvalid), .O_active(active), .O_image_valid(image_valid),
        .O_rx_byte_count(rx_count), .O_frame_ok_count(ok_count),
        .O_frame_error_count(error_count)
    );

    function [15:0] crc16_next;
        input [15:0] crc_in;
        input [7:0] data_in;
        integer b;
        reg [15:0] v;
        begin
            v = crc_in;
            for (b = 0; b < 8; b = b + 1)
                v = (v[15] ^ data_in[7-b]) ? {v[14:0],1'b0} ^ 16'h1021 : {v[14:0],1'b0};
            crc16_next = v;
        end
    endfunction

    task send_bit;
        input bit_value;
        begin
            uart_rx = bit_value;
            #(BIT_NS);
        end
    endtask

    task send_byte;
        input [7:0] value;
        integer b;
        begin
            send_bit(1'b0);
            for (b = 0; b < 8; b = b + 1)
                send_bit(value[b]);
            send_bit(1'b1);
        end
    endtask

    reg [7:0] packet [0:31];
    reg [15:0] crc;
    integer i;
    initial begin
        #500;
        rst_n = 1'b1;
        packet[0]=8'h55; packet[1]=8'hAA; packet[2]=8'h5A; packet[3]=8'hA5;
        packet[4]=8'h01; packet[5]=8'h01; packet[6]=8'h04; packet[7]=8'h00;
        packet[8]=8'h02; packet[9]=8'h00; packet[10]=8'h00; packet[11]=8'h00;
        packet[12]=8'h00; packet[13]=8'h00;
        crc = 16'hFFFF;
        for (i = 0; i < 16; i = i + 1) begin
            packet[14+i] = i;
            crc = crc16_next(crc, i[7:0]);
        end
        packet[30] = crc[7:0];
        packet[31] = crc[15:8];
        for (i = 0; i < 32; i = i + 1)
            send_byte(packet[i]);
        send_byte(8'h0D);
        send_byte(8'h0A);
        #5000;
        $display("rx=%0d ok=%0d err=%0d image_valid=%b active=%b", rx_count, ok_count, error_count, image_valid, active);
        if (rx_count !== 34 || ok_count !== 1 || error_count !== 0 || !image_valid) begin
            $display("FAIL: UART frame was not accepted");
            $fatal(1);
        end
        wait (tvalid && tuser);
        $display("first beat tuser=%b tlast=%b data=%h", tuser, tlast, tdata);
        if (!tuser || tdata !== {4{24'h002000}}) begin
            $display("FAIL: first RGB565 pixel was not replayed as four RGB888 pixels");
            $fatal(1);
        end
        $display("PASS: accepted frame and produced replay stream");
        $finish;
    end
endmodule
