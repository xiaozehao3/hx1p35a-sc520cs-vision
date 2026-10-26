`timescale 1ns/1ps

module tb_pc_plate_uart_rx;
    localparam integer BIT_NS = 100;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire update_toggle;
    wire plate_valid;
    wire [3:0] plate_length;
    wire [87:0] plate_chars;
    reg [7:0] crc;
    integer i;

    always #5 clk = ~clk;

    pc_plate_uart_rx #(
        .CLOCK_HZ(1000000),
        .BAUD(100000),
        .MAX_CHARS(11)
    ) dut (
        .I_clk(clk),
        .I_rst_n(rst_n),
        .I_rx(uart_rx),
        .O_update_toggle(update_toggle),
        .O_valid(plate_valid),
        .O_length(plate_length),
        .O_chars(plate_chars)
    );

    task send_uart_byte;
        input [7:0] data;
        integer bit_number;
        begin
            uart_rx = 1'b0;
            #(BIT_NS);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                uart_rx = data[bit_number];
                #(BIT_NS);
            end
            uart_rx = 1'b1;
            #(BIT_NS);
        end
    endtask

    task send_crc_data;
        input [7:0] data;
        begin
            send_uart_byte(data);
            crc = dut.crc8_next(crc, data);
        end
    endtask

    task send_sync;
        begin
            send_uart_byte(8'hA5);
            send_uart_byte(8'h5A);
        end
    endtask

    task wait_uart_idle;
        begin
            uart_rx = 1'b1;
            repeat (30) @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        send_sync();
        crc = 8'd0;
        send_crc_data(8'h01);
        send_crc_data(8'd7);
        send_crc_data(8'hD9);
        send_crc_data(8'h41);
        send_crc_data(8'h31);
        send_crc_data(8'h32);
        send_crc_data(8'h33);
        send_crc_data(8'h34);
        send_uart_byte(crc);
        wait_uart_idle();
        if (!plate_valid || (plate_length != 7) ||
            (plate_chars[87:80] != 8'hD9) || (plate_chars[79:72] != 8'h41) ||
            (plate_chars[39:32] != 8'h34)) begin
            $display("FAIL: valid plate packet not received: valid=%b len=%0d chars=%h",
                     plate_valid, plate_length, plate_chars);
            $fatal(1);
        end

        send_sync();
        crc = 8'd0;
        send_crc_data(8'h01);
        send_crc_data(8'd1);
        send_crc_data(8'h42);
        send_uart_byte(crc ^ 8'h01);
        wait_uart_idle();
        if (!plate_valid || (plate_length != 7) || (plate_chars[79:72] != 8'h41)) begin
            $display("FAIL: bad CRC changed the last valid result");
            $fatal(1);
        end

        send_sync();
        crc = 8'd0;
        send_crc_data(8'h00);
        send_crc_data(8'd0);
        send_uart_byte(crc);
        wait_uart_idle();
        if (plate_valid || (plate_length != 0)) begin
            $display("FAIL: clear packet did not clear the plate");
            $fatal(1);
        end

        $display("PASS: UART packet, CRC reject, and clear");
        $finish;
    end
endmodule
