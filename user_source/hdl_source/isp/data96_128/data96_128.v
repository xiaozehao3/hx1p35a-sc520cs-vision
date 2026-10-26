// Pack four RGB888 beats (96 bits each) into three contiguous 128-bit beats.
//
// Input ordering is {pixel0,pixel1,pixel2,pixel3}, with each pixel 24 bits.
// Output ordering is byte-contiguous so video_out can split the stream into
// 24-bit pixels without seeing the demosaic padding bytes.
module data_96bit_to_128bit (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire         I_96b_frame_start,
    input  wire         I_96b_valid,
    input  wire [95:0]  I_96b_data,
    input  wire         I_96b_tlast,

    output reg          O_128b_frame_start,
    output reg          O_128b_valid,
    output reg  [127:0] O_128b_data,
    output reg          O_128b_tlast
);

    reg [95:0] S_data_1d;
    reg        S_frame_start_1d;
    reg [1:0]  S_count;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_data_1d          <= 96'd0;
            S_frame_start_1d  <= 1'b0;
            S_count            <= 2'd0;
            O_128b_frame_start <= 1'b0;
            O_128b_valid       <= 1'b0;
            O_128b_data        <= 128'd0;
            O_128b_tlast       <= 1'b0;
        end else begin
            O_128b_frame_start <= 1'b0;
            O_128b_valid       <= 1'b0;
            O_128b_tlast       <= 1'b0;

            if (I_96b_valid) begin
                case (S_count)
                    2'd0: begin
                        // First beat of a 4-beat packing group.
                        S_data_1d         <= I_96b_data;
                        S_frame_start_1d <= I_96b_frame_start;
                        S_count           <= 2'd1;
                    end

                    2'd1: begin
                        // Bytes: A[95:0] + B[95:64].
                        O_128b_valid       <= 1'b1;
                        O_128b_frame_start <= S_frame_start_1d;
                        O_128b_data        <= {S_data_1d, I_96b_data[95:64]};
                        S_data_1d          <= I_96b_data;
                        S_count            <= 2'd2;
                    end

                    2'd2: begin
                        // Bytes: B[63:0] + C[95:32].
                        O_128b_valid       <= 1'b1;
                        O_128b_data        <= {S_data_1d[63:0], I_96b_data[95:32]};
                        S_data_1d          <= I_96b_data;
                        S_count            <= 2'd3;
                    end

                    2'd3: begin
                        // Bytes: C[31:0] + D[95:0].
                        O_128b_valid       <= 1'b1;
                        O_128b_data        <= {S_data_1d[31:0], I_96b_data};
                        O_128b_tlast       <= I_96b_tlast;
                        S_data_1d          <= 96'd0;
                        S_frame_start_1d  <= 1'b0;
                        S_count            <= 2'd0;
                    end

                    default: begin
                        S_data_1d         <= 96'd0;
                        S_frame_start_1d <= 1'b0;
                        S_count           <= 2'd0;
                    end
                endcase
            end else begin
                // A gap is only expected between complete groups/lines.
                // Do not allow a partial group to leak into the next line.
                S_data_1d         <= 96'd0;
                S_frame_start_1d <= 1'b0;
                S_count           <= 2'd0;
            end
        end
    end

endmodule