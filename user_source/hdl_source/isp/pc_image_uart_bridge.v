// PC -> FPGA still-image UART bridge.
//
// Protocol (8-N-1, payload CRC16-CCITT):
//   55 AA 5A A5 01 01 A0 00 5A 00 80 70 seq[3:0]
//   160 x 90 RGB565 payload, little-endian pixel bytes
//   crc16 low byte, crc16 high byte, 0D 0A
//
// The received frame is held in four interleaved dual-port RAM banks.  The
// video side expands each source pixel by 8x and emits a normal 1280x720,
// four-pixel RGB888 AXI stream.  It is intentionally a still-image bridge,
// not a real-time video transport.
module pc_image_uart_bridge #(
    parameter integer IMAGE_WIDTH   = 160,
    parameter integer IMAGE_HEIGHT  = 90,
    parameter integer DISPLAY_WIDTH = 1280,
    parameter integer DISPLAY_HEIGHT= 720,
    parameter integer CLOCK_HZ      = 100000000,
    parameter integer BAUD          = 115200
)(
    input  wire        I_uart_clk,
    input  wire        I_video_clk,
    input  wire        I_rst_n,
    input  wire        I_uart_rx,
    input  wire        I_enable,
    input  wire        I_tready,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    output wire        O_active,
    output reg         O_image_valid,
    // UART-domain counters sampled by the video-domain status panel.
    output reg [15:0]  O_rx_byte_count,
    output reg [15:0]  O_frame_ok_count,
    output reg [15:0]  O_frame_error_count
);

    localparam integer IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam integer BANK_DEPTH   = IMAGE_PIXELS / 4;
    localparam integer PAYLOAD_BYTES= IMAGE_PIXELS * 2;
    localparam integer BIT_TICKS    = (CLOCK_HZ + (BAUD / 2)) / BAUD;
    localparam integer HALF_TICKS   = BIT_TICKS / 2;

    // ---------------------------------------------------------------------
    // UART byte receiver
    // ---------------------------------------------------------------------
    localparam [2:0] RX_IDLE  = 3'd0;
    localparam [2:0] RX_START = 3'd1;
    localparam [2:0] RX_DATA  = 3'd2;
    localparam [2:0] RX_STOP  = 3'd3;

    reg        rx_meta, rx_sync, rx_sync_d;
    reg [2:0]  rx_state;
    reg [15:0] rx_baud_count;
    reg [2:0]  rx_bit_index;
    reg [7:0]  rx_shift;
    reg        rx_byte_valid;
    reg [7:0]  rx_byte;

    always @(posedge I_uart_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rx_meta       <= 1'b1;
            rx_sync       <= 1'b1;
            rx_sync_d     <= 1'b1;
            rx_state      <= RX_IDLE;
            rx_baud_count <= 16'd0;
            rx_bit_index  <= 3'd0;
            rx_shift      <= 8'd0;
            rx_byte_valid <= 1'b0;
            rx_byte       <= 8'd0;
        end else begin
            rx_meta       <= I_uart_rx;
            rx_sync       <= rx_meta;
            rx_sync_d     <= rx_sync;
            rx_byte_valid <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    rx_baud_count <= 16'd0;
                    if (rx_sync_d && !rx_sync) begin
                        rx_state      <= RX_START;
                        rx_baud_count <= HALF_TICKS - 1;
                    end
                end
                RX_START: begin
                    if (rx_baud_count != 0)
                        rx_baud_count <= rx_baud_count - 1'b1;
                    else if (!rx_sync) begin
                        rx_state      <= RX_DATA;
                        rx_bit_index  <= 3'd0;
                        rx_baud_count <= BIT_TICKS - 1;
                    end else begin
                        rx_state <= RX_IDLE;
                    end
                end
                RX_DATA: begin
                    if (rx_baud_count != 0)
                        rx_baud_count <= rx_baud_count - 1'b1;
                    else begin
                        rx_shift[rx_bit_index] <= rx_sync;
                        rx_baud_count <= BIT_TICKS - 1;
                        if (rx_bit_index == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_index <= rx_bit_index + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_baud_count != 0)
                        rx_baud_count <= rx_baud_count - 1'b1;
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

    // ---------------------------------------------------------------------
    // Four-bank dual-port image memory.  Bank n stores pixels n, n+4, ...
    // so four source reads are available in parallel when the format grows.
    // The current scaler only needs one selected bank per output beat.
    // ---------------------------------------------------------------------
    reg        frame_we0, frame_we1, frame_we2, frame_we3;
    reg [11:0] frame_waddr;
    reg [15:0] frame_wdata;
    wire [11:0] frame_raddr;
    wire [15:0] frame_rdata0, frame_rdata1, frame_rdata2, frame_rdata3;

    reg [7:0]  payload_low;
    reg [14:0] payload_count;
    reg [15:0] payload_crc;
    reg [7:0]  received_crc_low;
    reg        packet_crc_ok;
    reg        frame_valid_uart;
    reg        frame_toggle_uart;

    function [15:0] crc16_next;
        input [15:0] crc_in;
        input [7:0]  data_in;
        integer bit_i;
        reg [15:0] value;
        begin
            value = crc_in;
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                if (value[15] ^ data_in[7-bit_i])
                    value = {value[14:0],1'b0} ^ 16'h1021;
                else
                    value = {value[14:0],1'b0};
            end
            crc16_next = value;
        end
    endfunction

    localparam [4:0] P_SYNC0 = 5'd0;
    localparam [4:0] P_SYNC1 = 5'd1;
    localparam [4:0] P_SYNC2 = 5'd2;
    localparam [4:0] P_SYNC3 = 5'd3;
    localparam [4:0] P_VER   = 5'd4;
    localparam [4:0] P_FMT   = 5'd5;
    localparam [4:0] P_W0    = 5'd6;
    localparam [4:0] P_W1    = 5'd7;
    localparam [4:0] P_H0    = 5'd8;
    localparam [4:0] P_H1    = 5'd9;
    localparam [4:0] P_SEQ0  = 5'd10;
    localparam [4:0] P_SEQ1  = 5'd11;
    localparam [4:0] P_SEQ2  = 5'd12;
    localparam [4:0] P_SEQ3  = 5'd13;
    localparam [4:0] P_DATA  = 5'd14;
    localparam [4:0] P_CRC0  = 5'd15;
    localparam [4:0] P_CRC1  = 5'd16;
    localparam [4:0] P_TAIL0 = 5'd17;
    localparam [4:0] P_TAIL1 = 5'd18;
    reg [4:0] packet_state;

    always @(posedge I_uart_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            packet_state    <= P_SYNC0;
            frame_we0       <= 1'b0;
            frame_we1       <= 1'b0;
            frame_we2       <= 1'b0;
            frame_we3       <= 1'b0;
            frame_waddr     <= 12'd0;
            frame_wdata     <= 16'd0;
            payload_low     <= 8'd0;
            payload_count   <= 15'd0;
            payload_crc     <= 16'hFFFF;
            received_crc_low<= 8'd0;
            packet_crc_ok   <= 1'b0;
            frame_valid_uart<= 1'b0;
            frame_toggle_uart <= 1'b0;
            O_rx_byte_count <= 16'd0;
            O_frame_ok_count <= 16'd0;
            O_frame_error_count <= 16'd0;
        end else begin
            frame_we0 <= 1'b0;
            frame_we1 <= 1'b0;
            frame_we2 <= 1'b0;
            frame_we3 <= 1'b0;

            if (rx_byte_valid) begin
                if (O_rx_byte_count != 16'hFFFF)
                    O_rx_byte_count <= O_rx_byte_count + 1'b1;
                case (packet_state)
                    P_SYNC0: packet_state <= (rx_byte == 8'h55) ? P_SYNC1 : P_SYNC0;
                    P_SYNC1: packet_state <= (rx_byte == 8'hAA) ? P_SYNC2 :
                                              ((rx_byte == 8'h55) ? P_SYNC1 : P_SYNC0);
                    P_SYNC2: packet_state <= (rx_byte == 8'h5A) ? P_SYNC3 : P_SYNC0;
                    P_SYNC3: packet_state <= (rx_byte == 8'hA5) ? P_VER : P_SYNC0;
                    P_VER:   packet_state <= (rx_byte == 8'h01) ? P_FMT : P_SYNC0;
                    P_FMT:   packet_state <= (rx_byte == 8'h01) ? P_W0 : P_SYNC0;
                    P_W0:    packet_state <= (rx_byte == IMAGE_WIDTH[7:0]) ? P_W1 : P_SYNC0;
                    P_W1:    packet_state <= (rx_byte == IMAGE_WIDTH[15:8]) ? P_H0 : P_SYNC0;
                    P_H0:    packet_state <= (rx_byte == IMAGE_HEIGHT[7:0]) ? P_H1 : P_SYNC0;
                    P_H1:    begin
                        if (rx_byte == IMAGE_HEIGHT[15:8]) begin
                            payload_count <= 15'd0;
                            payload_crc   <= 16'hFFFF;
                            packet_state  <= P_SEQ0;
                        end else packet_state <= P_SYNC0;
                    end
                    P_SEQ0: packet_state <= P_SEQ1;
                    P_SEQ1: packet_state <= P_SEQ2;
                    P_SEQ2: packet_state <= P_SEQ3;
                    P_SEQ3: packet_state <= P_DATA;
                    P_DATA: begin
                        payload_crc <= crc16_next(payload_crc, rx_byte);
                        if (!payload_count[0]) begin
                            payload_low <= rx_byte;
                        end else begin
                            frame_waddr <= payload_count[14:3];
                            frame_wdata <= {rx_byte, payload_low};
                            case (payload_count[2:1])
                                2'd0: frame_we0 <= 1'b1;
                                2'd1: frame_we1 <= 1'b1;
                                2'd2: frame_we2 <= 1'b1;
                                default: frame_we3 <= 1'b1;
                            endcase
                        end
                        if (payload_count == PAYLOAD_BYTES-1) begin
                            packet_state <= P_CRC0;
                        end else begin
                            payload_count <= payload_count + 1'b1;
                        end
                    end
                    P_CRC0: begin
                        received_crc_low <= rx_byte;
                        packet_state <= P_CRC1;
                    end
                    P_CRC1: begin
                        packet_crc_ok <= ({rx_byte, received_crc_low} == payload_crc);
                        if ({rx_byte, received_crc_low} == payload_crc)
                            packet_state <= P_TAIL0;
                        else begin
                            packet_state <= P_SYNC0;
                            if (O_frame_error_count != 16'hFFFF)
                                O_frame_error_count <= O_frame_error_count + 1'b1;
                        end
                    end
                    P_TAIL0: begin
                        if (rx_byte == 8'h0D)
                            packet_state <= P_TAIL1;
                        else begin
                            packet_state <= P_SYNC0;
                            if (O_frame_error_count != 16'hFFFF)
                                O_frame_error_count <= O_frame_error_count + 1'b1;
                        end
                    end
                    P_TAIL1: begin
                        if ((rx_byte == 8'h0A) && packet_crc_ok) begin
                            frame_valid_uart  <= 1'b1;
                            frame_toggle_uart <= ~frame_toggle_uart;
                            if (O_frame_ok_count != 16'hFFFF)
                                O_frame_ok_count <= O_frame_ok_count + 1'b1;
                        end else if (O_frame_error_count != 16'hFFFF) begin
                            O_frame_error_count <= O_frame_error_count + 1'b1;
                        end
                        packet_state <= P_SYNC0;
                    end
                    default: packet_state <= P_SYNC0;
                endcase
            end
        end
    end

    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12), .DATA_DEPTH_A(BANK_DEPTH),
        .DATA_DEPTH_B(BANK_DEPTH), .MODE("DP"), .REGMODE_A("NOREG"),
        .REGMODE_B("OUTREG"), .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"), .OREGSET_A("RESET"),
        .OREGSET_B("RESET"), .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")) u_image_ram0 (
        .dia(frame_wdata), .dib(16'd0), .addra(frame_waddr), .addrb(frame_raddr),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b1), .clka(I_uart_clk),
        .clkb(I_video_clk), .wea(frame_we0), .web(1'b0), .bea(1'b0), .beb(1'b0),
        .rsta(1'b0), .rstb(1'b0), .doa(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0), .dob(frame_rdata0));

    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12), .DATA_DEPTH_A(BANK_DEPTH),
        .DATA_DEPTH_B(BANK_DEPTH), .MODE("DP"), .REGMODE_A("NOREG"),
        .REGMODE_B("OUTREG"), .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"), .OREGSET_A("RESET"),
        .OREGSET_B("RESET"), .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")) u_image_ram1 (
        .dia(frame_wdata), .dib(16'd0), .addra(frame_waddr), .addrb(frame_raddr),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b1), .clka(I_uart_clk),
        .clkb(I_video_clk), .wea(frame_we1), .web(1'b0), .bea(1'b0), .beb(1'b0),
        .rsta(1'b0), .rstb(1'b0), .doa(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0), .dob(frame_rdata1));

    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12), .DATA_DEPTH_A(BANK_DEPTH),
        .DATA_DEPTH_B(BANK_DEPTH), .MODE("DP"), .REGMODE_A("NOREG"),
        .REGMODE_B("OUTREG"), .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"), .OREGSET_A("RESET"),
        .OREGSET_B("RESET"), .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")) u_image_ram2 (
        .dia(frame_wdata), .dib(16'd0), .addra(frame_waddr), .addrb(frame_raddr),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b1), .clka(I_uart_clk),
        .clkb(I_video_clk), .wea(frame_we2), .web(1'b0), .bea(1'b0), .beb(1'b0),
        .rsta(1'b0), .rstb(1'b0), .doa(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0), .dob(frame_rdata2));

    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(12), .ADDR_WIDTH_B(12), .DATA_DEPTH_A(BANK_DEPTH),
        .DATA_DEPTH_B(BANK_DEPTH), .MODE("DP"), .REGMODE_A("NOREG"),
        .REGMODE_B("OUTREG"), .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"), .ECC_ENCODE("DISABLE"), .ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"), .SSROVERCE("DISABLE"), .OREGSET_A("RESET"),
        .OREGSET_B("RESET"), .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"), .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"), .FILL_ALL("NONE")) u_image_ram3 (
        .dia(frame_wdata), .dib(16'd0), .addra(frame_waddr), .addrb(frame_raddr),
        .cea(1'b1), .ceb(1'b1), .ocea(1'b0), .oceb(1'b1), .clka(I_uart_clk),
        .clkb(I_video_clk), .wea(frame_we3), .web(1'b0), .bea(1'b0), .beb(1'b0),
        .rsta(1'b0), .rstb(1'b0), .doa(), .ecc_sbiterr(), .ecc_dbiterr(),
        .ecc_sbiterrinj('d0), .ecc_dbiterrinj('d0), .dob(frame_rdata3));

    // ---------------------------------------------------------------------
    // Video-domain toggle synchronizers and 8x scaler.
    // ---------------------------------------------------------------------
    reg toggle_sync1, toggle_sync2;
    reg valid_sync1, valid_sync2;
    reg toggle_seen;
    reg enable_d;
    reg display_active;
    reg read_pending;
    reg pending_user, pending_last;
    reg [1:0] pending_bank;
    reg [8:0] display_x_group;
    reg [9:0] display_y;
    reg [1:0] read_bank;
    wire [6:0] source_y = display_y[9:3];
    wire [7:0] source_x = display_x_group[8:1];
    wire [13:0] source_pixel = (source_y * IMAGE_WIDTH) + source_x;

    assign frame_raddr = source_pixel[13:2];

    function [23:0] rgb565_to_rgb888;
        input [15:0] value;
        begin
            rgb565_to_rgb888 = {value[15:11], value[15:13],
                                value[10:5],  value[10:9],
                                value[4:0],   value[4:2]};
        end
    endfunction

    wire [15:0] selected_rgb565 =
        (pending_bank == 2'd0) ? frame_rdata0 :
        (pending_bank == 2'd1) ? frame_rdata1 :
        (pending_bank == 2'd2) ? frame_rdata2 : frame_rdata3;
    wire [23:0] selected_rgb888 = rgb565_to_rgb888(selected_rgb565);

    assign O_active = display_active | read_pending | O_tvalid;

    always @(posedge I_video_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            toggle_sync1   <= 1'b0;
            toggle_sync2   <= 1'b0;
            valid_sync1    <= 1'b0;
            valid_sync2    <= 1'b0;
            toggle_seen    <= 1'b0;
            enable_d       <= 1'b0;
            display_active <= 1'b0;
            O_image_valid  <= 1'b0;
            read_pending   <= 1'b0;
            pending_user   <= 1'b0;
            pending_last   <= 1'b0;
            pending_bank   <= 2'd0;
            display_x_group<= 9'd0;
            display_y      <= 10'd0;
            read_bank      <= 2'd0;
            O_tlast        <= 1'b0;
            O_tuser        <= 1'b0;
            O_tdata        <= 96'd0;
            O_tvalid       <= 1'b0;
        end else begin
            toggle_sync1 <= frame_toggle_uart;
            toggle_sync2 <= toggle_sync1;
            valid_sync1  <= frame_valid_uart;
            valid_sync2  <= valid_sync1;
            enable_d     <= I_enable;

            if (!I_enable) begin
                display_active <= 1'b0;
                read_pending   <= 1'b0;
                O_tvalid       <= 1'b0;
                O_image_valid  <= 1'b0;
            end else if (O_tvalid && !I_tready) begin
                // Hold the registered output while the downstream stream is stalled.
                O_tvalid <= O_tvalid;
            end else begin
                O_tvalid <= read_pending;
                if (read_pending) begin
                    O_tuser <= pending_user;
                    O_tlast <= pending_last;
                    O_tdata <= {selected_rgb888, selected_rgb888,
                                selected_rgb888, selected_rgb888};
                end

                if (!display_active && valid_sync2 &&
                    ((!enable_d) || (toggle_sync2 != toggle_seen))) begin
                    display_active  <= 1'b1;
                    O_image_valid  <= 1'b1;
                    toggle_seen     <= toggle_sync2;
                    display_x_group <= 9'd0;
                    display_y       <= 10'd0;
                end

                if (display_active) begin
                    read_pending <= 1'b1;
                    pending_user <= (display_x_group == 0) && (display_y == 0);
                    pending_last <= (display_x_group == ((DISPLAY_WIDTH/4)-1));
                    pending_bank <= source_pixel[1:0];
                    read_bank    <= source_pixel[1:0];

                    if (display_x_group == ((DISPLAY_WIDTH/4)-1)) begin
                        display_x_group <= 9'd0;
                        if (display_y == DISPLAY_HEIGHT-1) begin
                            display_y       <= 10'd0;
                            // Keep the last complete image as the active
                            // source and continuously replay it for HDMI.
                            display_active   <= O_image_valid;
                        end else begin
                            display_y <= display_y + 1'b1;
                        end
                    end else begin
                        display_x_group <= display_x_group + 1'b1;
                    end
                end else begin
                    read_pending <= 1'b0;
                end
            end
        end
    end
endmodule
