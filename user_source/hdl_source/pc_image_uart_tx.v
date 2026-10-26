//------------------------------------------------------------------------------
// pc_image_uart_tx.v
//
// K2 打开后，从算法输出流抓取一帧 1280x720 图像，按 8x8 采样为
// 160x90 RGB565，并通过 100 MHz 时钟域的 UART 发送给上位机。
//
// 串口参数：2,000,000 baud，8 数据位、无校验、1 停止位（8N1）。
// 帧格式：
//   55 AA 5A A5 01 01
//   width[15:0] height[15:0] payload_len[15:0] frame_seq[31:0]
//   payload（160*90 个 RGB565 像素，低字节在前）
//   crc16-ccitt（只对 payload 计算，低字节在前）
//   0D 0A
//
// 图像采集时钟和 UART 时钟分离。frame_ready_toggle / ack_toggle 使用
// toggle 握手，保证 UART 发送期间不会覆盖帧缓存。
//------------------------------------------------------------------------------
module pc_image_uart_tx #(
    parameter integer SRC_WIDTH      = 1280,
    parameter integer SRC_HEIGHT     = 720,
    parameter integer OUT_WIDTH      = 160,
    parameter integer OUT_HEIGHT     = 90,
    parameter integer UART_CLOCK_HZ  = 100000000,
    parameter integer UART_BAUD      = 2000000
) (
    input  wire        I_video_clk,
    input  wire        I_uart_clk,
    input  wire        I_rst_n,
    input  wire        I_enable,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    output reg         O_uart_tx
);

    localparam integer IMAGE_PIXELS = OUT_WIDTH * OUT_HEIGHT;
    localparam integer SAMPLE_X_STEP = SRC_WIDTH / OUT_WIDTH;
    localparam integer SAMPLE_Y_STEP = SRC_HEIGHT / OUT_HEIGHT;
    localparam integer UART_DIV = (UART_CLOCK_HZ + (UART_BAUD / 2)) / UART_BAUD;

    // The current project uses a 1280x720 stream packed as four RGB888 pixels
    // per 96-bit beat.  These widths keep the design bounded if the sensor
    // parameters are changed later.
    localparam integer SRC_X_W = 12;
    localparam integer SRC_Y_W = 10;
    localparam integer PIXEL_ADDR_W = 14;

    // One 160x90 RGB565 frame = 28,800 bytes.  The write side is clocked by
    // the camera/algorithm stream and the read side is clocked by 100 MHz.
    reg [15:0] frame_mem [0:IMAGE_PIXELS-1]; /* fehdl force_ram=1, ram_style="bram_fast" */
    // Synchronous read port encourages embedded dual-clock RAM inference.
    reg [15:0] tx_pixel_data;
    always @(posedge I_uart_clk) begin
        tx_pixel_data <= frame_mem[tx_pixel_index];
    end

    function [15:0] rgb565_from_rgb888;
        input [7:0] r;
        input [7:0] g;
        input [7:0] b;
        begin
            rgb565_from_rgb888 = {r[7:3], g[7:2], b[7:3]};
        end
    endfunction

    // -------------------------------------------------------------------------
    // Video clock domain: sample every eighth pixel and every eighth line.
    // The stream contains four pixels per beat, so x advances by four for
    // every valid beat.  Only beats whose first pixel is x=0,8,16,... are used.
    // -------------------------------------------------------------------------
    reg                  capture_active;
    reg [SRC_X_W-1:0]   src_x;
    reg [SRC_Y_W-1:0]   src_y;
    reg [PIXEL_ADDR_W-1:0] capture_index;
    reg                  frame_ready_toggle;

    reg                  ack_video_ff1;
    reg                  ack_video_ff2;
    reg                  enable_video_d;

    // ack_toggle is generated in the UART clock domain and synchronized here.
    reg                  ack_toggle;

    always @(posedge I_video_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            capture_active  <= 1'b0;
            src_x           <= {SRC_X_W{1'b0}};
            src_y           <= {SRC_Y_W{1'b0}};
            capture_index   <= {PIXEL_ADDR_W{1'b0}};
            frame_ready_toggle <= 1'b0;
            ack_video_ff1   <= 1'b0;
            ack_video_ff2   <= 1'b0;
            enable_video_d  <= 1'b0;
        end else begin
            ack_video_ff1  <= ack_toggle;
            ack_video_ff2  <= ack_video_ff1;
            enable_video_d <= I_enable;

            // Disabling K2 aborts the next capture.  If a frame is already
            // being transmitted, the UART side finishes the current byte and
            // then returns to idle; the next frame can be captured normally.
            if (!I_enable) begin
                capture_active <= 1'b0;
            end else if (I_tvalid) begin
                // tuser is asserted with the first beat of a new frame.
                if (I_tuser) begin
                    src_x <= 4;
                    src_y <= {SRC_Y_W{1'b0}};

                    // A new frame can be captured only after the UART side has
                    // acknowledged the previously transmitted frame.
                    if (ack_video_ff2 == frame_ready_toggle) begin
                        capture_active <= 1'b1;
                        capture_index  <= {{(PIXEL_ADDR_W-1){1'b0}},1'b1};
                        frame_mem[0]   <= rgb565_from_rgb888(
                            I_tdata[95:88], I_tdata[87:80], I_tdata[79:72]);
                    end else begin
                        capture_active <= 1'b0;
                    end
                end else if (capture_active) begin
                    // Select y=0,8,16,... and x=0,8,16,... .
                    if (src_y[2:0] == 3'b000 && src_x[2:0] == 3'b000) begin
                        if (capture_index < IMAGE_PIXELS) begin
                            frame_mem[capture_index] <= rgb565_from_rgb888(
                                I_tdata[95:88], I_tdata[87:80], I_tdata[79:72]);
                            if (capture_index < IMAGE_PIXELS-1)
                                capture_index <= capture_index + 1'b1;
                        end
                    end

                    if (I_tlast) begin
                        src_x <= {SRC_X_W{1'b0}};
                        if (src_y == SRC_HEIGHT-1) begin
                            // The last sampled line is y=712.  The end marker
                            // for y=719 is used as the frame-complete point.
                            capture_active    <= 1'b0;
                            frame_ready_toggle <= ~frame_ready_toggle;
                        end else begin
                            src_y <= src_y + 1'b1;
                        end
                    end else begin
                        src_x <= src_x + 4;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // UART clock domain CDC synchronizers.
    // -------------------------------------------------------------------------
    reg ready_uart_ff1;
    reg ready_uart_ff2;
    reg enable_uart_ff1;
    reg enable_uart_ff2;

    always @(posedge I_uart_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ready_uart_ff1  <= 1'b0;
            ready_uart_ff2  <= 1'b0;
            enable_uart_ff1 <= 1'b0;
            enable_uart_ff2 <= 1'b0;
        end else begin
            ready_uart_ff1  <= frame_ready_toggle;
            ready_uart_ff2  <= ready_uart_ff1;
            enable_uart_ff1 <= I_enable;
            enable_uart_ff2 <= enable_uart_ff1;
        end
    end

    // -------------------------------------------------------------------------
    // CRC16-CCITT, polynomial 0x1021, initial value 0xFFFF.
    // -------------------------------------------------------------------------
    function [15:0] crc16_ccitt_next;
        input [15:0] crc_in;
        input [7:0]  data_in;
        integer bit_i;
        reg [15:0] crc_work;
        begin
            crc_work = crc_in;
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                if (crc_work[15] ^ data_in[7-bit_i])
                    crc_work = {crc_work[14:0],1'b0} ^ 16'h1021;
                else
                    crc_work = {crc_work[14:0],1'b0};
            end
            crc16_ccitt_next = crc_work;
        end
    endfunction

    // -------------------------------------------------------------------------
    // UART frame scheduler.
    // -------------------------------------------------------------------------
    localparam [4:0] ST_IDLE    = 5'd0;
    localparam [4:0] ST_HDR1    = 5'd1;
    localparam [4:0] ST_HDR2    = 5'd2;
    localparam [4:0] ST_HDR3    = 5'd3;
    localparam [4:0] ST_HDR4    = 5'd4;
    localparam [4:0] ST_HDR5    = 5'd5;
    localparam [4:0] ST_HDR6    = 5'd6;
    localparam [4:0] ST_HDR7    = 5'd7;
    localparam [4:0] ST_HDR8    = 5'd8;
    localparam [4:0] ST_HDR9    = 5'd9;
    localparam [4:0] ST_HDR10   = 5'd10;
    localparam [4:0] ST_HDR11   = 5'd11;
    localparam [4:0] ST_HDR12   = 5'd12;
    localparam [4:0] ST_HDR13   = 5'd13;
    localparam [4:0] ST_HDR14   = 5'd14;
    localparam [4:0] ST_HDR15   = 5'd15;
    localparam [4:0] ST_PAYLOAD = 5'd16;
    localparam [4:0] ST_CRC0    = 5'd17;
    localparam [4:0] ST_CRC1    = 5'd18;
    localparam [4:0] ST_TAIL0   = 5'd19;
    localparam [4:0] ST_TAIL1   = 5'd20;

    reg [4:0]  tx_state;
    reg        tx_byte_phase;
    reg [13:0] tx_pixel_index;
    reg [15:0] tx_crc;
    reg [31:0] frame_sequence;
    reg [31:0] tx_sequence_latched;
    reg        frame_sent_toggle;

    reg        uart_active;
    reg [5:0]  uart_baud_count;
    reg [3:0]  uart_bit_index;
    reg [7:0]  uart_shift;

    reg        schedule_valid;
    reg [7:0]  schedule_byte;
    reg [4:0]  schedule_next_state;

    // Combinational byte selection.  A one-clock gap between UART bytes is
    // intentional; it is negligible at 2 Mbaud and makes the scheduler easy
    // to verify on a logic analyzer.
    always @(*) begin
        schedule_valid     = 1'b0;
        schedule_byte      = 8'h00;
        schedule_next_state = tx_state;

        if (!uart_active && enable_uart_ff2) begin
            case (tx_state)
                ST_IDLE: begin
                    if (ready_uart_ff2 != frame_sent_toggle) begin
                        schedule_valid      = 1'b1;
                        schedule_byte       = 8'h55;
                        schedule_next_state = ST_HDR1;
                    end
                end
                ST_HDR1: begin schedule_valid=1'b1; schedule_byte=8'hAA; schedule_next_state=ST_HDR2;  end
                ST_HDR2: begin schedule_valid=1'b1; schedule_byte=8'h5A; schedule_next_state=ST_HDR3;  end
                ST_HDR3: begin schedule_valid=1'b1; schedule_byte=8'hA5; schedule_next_state=ST_HDR4;  end
                ST_HDR4: begin schedule_valid=1'b1; schedule_byte=8'h01; schedule_next_state=ST_HDR5;  end
                ST_HDR5: begin schedule_valid=1'b1; schedule_byte=8'h01; schedule_next_state=ST_HDR6;  end
                ST_HDR6: begin schedule_valid=1'b1; schedule_byte=8'hA0; schedule_next_state=ST_HDR7;  end
                ST_HDR7: begin schedule_valid=1'b1; schedule_byte=8'h00; schedule_next_state=ST_HDR8;  end
                ST_HDR8: begin schedule_valid=1'b1; schedule_byte=8'h5A; schedule_next_state=ST_HDR9;  end
                ST_HDR9: begin schedule_valid=1'b1; schedule_byte=8'h00; schedule_next_state=ST_HDR10; end
                ST_HDR10:begin schedule_valid=1'b1; schedule_byte=8'h80; schedule_next_state=ST_HDR11; end
                ST_HDR11:begin schedule_valid=1'b1; schedule_byte=8'h70; schedule_next_state=ST_HDR12; end
                ST_HDR12:begin schedule_valid=1'b1; schedule_byte=tx_sequence_latched[7:0];   schedule_next_state=ST_HDR13; end
                ST_HDR13:begin schedule_valid=1'b1; schedule_byte=tx_sequence_latched[15:8];  schedule_next_state=ST_HDR14; end
                ST_HDR14:begin schedule_valid=1'b1; schedule_byte=tx_sequence_latched[23:16]; schedule_next_state=ST_HDR15; end
                ST_HDR15:begin schedule_valid=1'b1; schedule_byte=tx_sequence_latched[31:24]; schedule_next_state=ST_PAYLOAD; end
                ST_PAYLOAD: begin
                    schedule_valid = 1'b1;
                    if (!tx_byte_phase)
                        schedule_byte = tx_pixel_data[7:0];
                    else
                        schedule_byte = tx_pixel_data[15:8];
                    schedule_next_state = ST_PAYLOAD;
                end
                ST_CRC0: begin schedule_valid=1'b1; schedule_byte=tx_crc[7:0];  schedule_next_state=ST_CRC1;  end
                ST_CRC1: begin schedule_valid=1'b1; schedule_byte=tx_crc[15:8]; schedule_next_state=ST_TAIL0; end
                ST_TAIL0:begin schedule_valid=1'b1; schedule_byte=8'h0D; schedule_next_state=ST_TAIL1; end
                ST_TAIL1:begin schedule_valid=1'b1; schedule_byte=8'h0A; schedule_next_state=ST_IDLE;  end
                default: begin schedule_valid=1'b0; schedule_next_state=ST_IDLE; end
            endcase
        end
    end

    // UART transmitter.  Output idles high.  Each byte is sent as:
    // start(0), data bit 0..7, stop(1).
    always @(posedge I_uart_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tx_state            <= ST_IDLE;
            tx_byte_phase       <= 1'b0;
            tx_pixel_index      <= 14'd0;
            tx_crc              <= 16'hFFFF;
            frame_sequence      <= 32'd0;
            tx_sequence_latched <= 32'd0;
            frame_sent_toggle   <= 1'b0;
            ack_toggle          <= 1'b0;
            uart_active         <= 1'b0;
            uart_baud_count     <= 6'd0;
            uart_bit_index      <= 4'd0;
            uart_shift          <= 8'd0;
            O_uart_tx           <= 1'b1;
        end else begin
            if (uart_active) begin
                if (uart_baud_count == UART_DIV-1) begin
                    uart_baud_count <= 6'd0;
                    if (uart_bit_index == 4'd9) begin
                        uart_active <= 1'b0;
                        O_uart_tx   <= 1'b1;
                    end else begin
                        uart_bit_index <= uart_bit_index + 1'b1;
                        if (uart_bit_index == 4'd0)
                            O_uart_tx <= uart_shift[0];
                        else if (uart_bit_index < 4'd8)
                            O_uart_tx <= uart_shift[uart_bit_index];
                        else
                            O_uart_tx <= 1'b1;
                    end
                end else begin
                    uart_baud_count <= uart_baud_count + 1'b1;
                end
            end else begin
                O_uart_tx <= 1'b1;

                // Stop scheduling new frames immediately after K2 is cleared.
                // If a byte is currently active, it is completed above.
                if (!enable_uart_ff2) begin
                    tx_state          <= ST_IDLE;
                    frame_sent_toggle <= ready_uart_ff2;
                    ack_toggle        <= ready_uart_ff2;
                    tx_byte_phase     <= 1'b0;
                    tx_pixel_index    <= 14'd0;
                end else if (schedule_valid) begin
                    uart_active     <= 1'b1;
                    uart_baud_count <= 6'd0;
                    uart_bit_index  <= 4'd0;
                    uart_shift      <= schedule_byte;
                    O_uart_tx       <= 1'b0;
                    tx_state        <= schedule_next_state;

                    if (tx_state == ST_IDLE) begin
                        tx_sequence_latched <= frame_sequence;
                        frame_sequence      <= frame_sequence + 1'b1;
                        tx_crc              <= 16'hFFFF;
                        tx_pixel_index     <= 14'd0;
                        tx_byte_phase      <= 1'b0;
                    end else if (tx_state == ST_PAYLOAD) begin
                        tx_crc <= crc16_ccitt_next(tx_crc, schedule_byte);
                        if (!tx_byte_phase) begin
                            tx_byte_phase <= 1'b1;
                        end else begin
                            tx_byte_phase <= 1'b0;
                            if (tx_pixel_index == IMAGE_PIXELS-1) begin
                                tx_pixel_index <= 14'd0;
                                tx_state        <= ST_CRC0;
                            end else begin
                                tx_pixel_index <= tx_pixel_index + 1'b1;
                            end
                        end
                    end

                    // The last byte of the tail means the complete frame is
                    // safely out of the UART.  Release the capture buffer.
                    if (tx_state == ST_TAIL1) begin
                        frame_sent_toggle <= ready_uart_ff2;
                        ack_toggle        <= ready_uart_ff2;
                    end
                end
            end
        end
    end

endmodule

