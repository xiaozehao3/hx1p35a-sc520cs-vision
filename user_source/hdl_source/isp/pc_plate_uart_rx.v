module pc_plate_uart_rx #(
    parameter integer CLOCK_HZ  = 100000000,
    parameter integer BAUD      = 115200,
    parameter integer MAX_CHARS = 11
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_rx,
    output reg         O_update_toggle,
    output reg         O_valid,
    output reg  [3:0]  O_length,
    output reg  [87:0] O_chars
);
    localparam integer BIT_TICKS = (CLOCK_HZ + (BAUD / 2)) / BAUD;
    localparam integer HALF_TICKS = BIT_TICKS / 2;
    localparam [2:0] RX_IDLE = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA = 3'd2;
    localparam [2:0] RX_STOP = 3'd3;
    localparam [2:0] PKT_SYNC0 = 3'd0;
    localparam [2:0] PKT_SYNC1 = 3'd1;
    localparam [2:0] PKT_CMD = 3'd2;
    localparam [2:0] PKT_LEN = 3'd3;
    localparam [2:0] PKT_DATA = 3'd4;
    localparam [2:0] PKT_CRC = 3'd5;

    reg [2:0] rx_state;
    reg [15:0] baud_count;
    reg [2:0] bit_index;
    reg [7:0] rx_shift;
    reg [2:0] pkt_state;
    reg [7:0] packet_command;
    reg [3:0] packet_length;
    reg [3:0] packet_index;
    reg [87:0] packet_chars;
    reg [7:0] packet_crc;
    reg rx_meta;
    reg rx_sync;
    reg rx_sync_d;
    reg rx_byte_valid;
    reg [7:0] rx_byte;
    integer char_slot;

    function [7:0] crc8_next;
        input [7:0] crc_in;
        input [7:0] data_in;
        reg [7:0] value;
        integer i;
        begin
            value = crc_in ^ data_in;
            for (i = 0; i < 8; i = i + 1) begin
                if (value[7])
                    value = {value[6:0], 1'b0} ^ 8'h07;
                else
                    value = {value[6:0], 1'b0};
            end
            crc8_next = value;
        end
    endfunction

    function is_supported_char;
        input [7:0] code;
        begin
            is_supported_char =
                ((code >= 8'h1C) && (code <= 8'h1F)) ||
                ((code >= 8'h30) && (code <= 8'h39)) ||
                ((code >= 8'h41) && (code <= 8'h5A)) ||
                ((code >= 8'h80) && (code <= 8'hFF));
        end
    endfunction

    // 8N1 receiver with a half-bit start check and synchronized input.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rx_meta       <= 1'b1;
            rx_sync       <= 1'b1;
            rx_sync_d     <= 1'b1;
            rx_byte_valid <= 1'b0;
            rx_byte       <= 8'd0;
            rx_state      <= RX_IDLE;
            baud_count    <= 16'd0;
            bit_index     <= 3'd0;
            rx_shift      <= 8'd0;
        end else begin
            rx_meta       <= I_rx;
            rx_sync       <= rx_meta;
            rx_sync_d     <= rx_sync;
            rx_byte_valid <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    baud_count <= 16'd0;
                    if (rx_sync_d && !rx_sync) begin
                        rx_state   <= RX_START;
                        baud_count <= HALF_TICKS - 1;
                    end
                end
                RX_START: begin
                    if (baud_count != 0)
                        baud_count <= baud_count - 1'b1;
                    else if (!rx_sync) begin
                        rx_state   <= RX_DATA;
                        bit_index  <= 3'd0;
                        baud_count <= BIT_TICKS - 1;
                    end else begin
                        rx_state <= RX_IDLE;
                    end
                end
                RX_DATA: begin
                    if (baud_count != 0)
                        baud_count <= baud_count - 1'b1;
                    else begin
                        rx_shift[bit_index] <= rx_sync;
                        baud_count <= BIT_TICKS - 1;
                        if (bit_index == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (baud_count != 0)
                        baud_count <= baud_count - 1'b1;
                    else begin
                        if (rx_sync) begin
                            rx_byte       <= rx_shift;
                            rx_byte_valid <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pkt_state       <= PKT_SYNC0;
            packet_command  <= 8'd0;
            packet_length   <= 4'd0;
            packet_index    <= 4'd0;
            packet_chars    <= 88'd0;
            packet_crc      <= 8'd0;
            O_update_toggle <= 1'b0;
            O_valid         <= 1'b0;
            O_length        <= 4'd0;
            O_chars         <= 88'd0;
            char_slot       <= 0;
        end else if (rx_byte_valid) begin
            case (pkt_state)
                PKT_SYNC0: begin
                    pkt_state <= (rx_byte == 8'hA5) ? PKT_SYNC1 : PKT_SYNC0;
                end
                PKT_SYNC1: begin
                    if (rx_byte == 8'h5A)
                        pkt_state <= PKT_CMD;
                    else
                        pkt_state <= (rx_byte == 8'hA5) ? PKT_SYNC1 : PKT_SYNC0;
                end
                PKT_CMD: begin
                    packet_command <= rx_byte;
                    packet_crc <= crc8_next(8'd0, rx_byte);
                    pkt_state <= PKT_LEN;
                end
                PKT_LEN: begin
                    packet_crc <= crc8_next(packet_crc, rx_byte);
                    if (((packet_command == 8'h00) && (rx_byte == 8'd0)) ||
                        ((packet_command == 8'h01) && (rx_byte > 0) &&
                         (rx_byte <= MAX_CHARS))) begin
                        packet_length <= rx_byte[3:0];
                        packet_index <= 4'd0;
                        packet_chars <= 88'd0;
                        if (packet_command == 8'h00)
                            pkt_state <= PKT_CRC;
                        else
                            pkt_state <= PKT_DATA;
                    end else begin
                        pkt_state <= (rx_byte == 8'hA5) ? PKT_SYNC1 : PKT_SYNC0;
                    end
                end
                PKT_DATA: begin
                    packet_crc <= crc8_next(packet_crc, rx_byte);
                    if (is_supported_char(rx_byte)) begin
                        char_slot = MAX_CHARS - 1 - packet_index;
                        packet_chars[char_slot*8 +: 8] <= rx_byte;
                        if (packet_index + 1'b1 == packet_length)
                            pkt_state <= PKT_CRC;
                        else
                            packet_index <= packet_index + 1'b1;
                    end else begin
                        pkt_state <= PKT_SYNC0;
                    end
                end
                PKT_CRC: begin
                    pkt_state <= PKT_SYNC0;
                    if (rx_byte == packet_crc) begin
                        if (packet_command == 8'h00) begin
                            O_valid  <= 1'b0;
                            O_length <= 4'd0;
                            O_chars  <= 88'd0;
                        end else begin
                            O_valid  <= 1'b1;
                            O_length <= packet_length;
                            O_chars  <= packet_chars;
                        end
                        O_update_toggle <= ~O_update_toggle;
                    end
                end
                default: pkt_state <= PKT_SYNC0;
            endcase
        end
    end
endmodule
