// Frame counters and measured frame rate in the 100 MHz system clock domain.
// The two toggle inputs are generated in the camera and HDMI pixel domains.
module vision_perf_monitor #(
    parameter integer REF_CLOCK_HZ = 100000000
)(
    input  wire        I_ref_clk,
    input  wire        I_rst_n,
    input  wire        I_capture_toggle,
    input  wire        I_display_toggle,
    output reg [31:0]  O_capture_frame,
    output reg [31:0]  O_display_frame,
    output reg [7:0]   O_fps
);

    reg cap_sync_1d;
    reg cap_sync_2d;
    reg cap_seen;
    reg disp_sync_1d;
    reg disp_sync_2d;
    reg disp_seen;
    reg [31:0] ref_count;
    reg [7:0]  frames_in_second;

    always @(posedge I_ref_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cap_sync_1d      <= 1'b0;
            cap_sync_2d      <= 1'b0;
            cap_seen         <= 1'b0;
            disp_sync_1d     <= 1'b0;
            disp_sync_2d     <= 1'b0;
            disp_seen        <= 1'b0;
            ref_count        <= 32'd0;
            frames_in_second <= 8'd0;
            O_capture_frame  <= 32'd0;
            O_display_frame  <= 32'd0;
            O_fps            <= 8'd0;
        end else begin
            cap_sync_1d  <= I_capture_toggle;
            cap_sync_2d  <= cap_sync_1d;
            disp_sync_1d <= I_display_toggle;
            disp_sync_2d <= disp_sync_1d;

            if (cap_sync_2d != cap_seen) begin
                cap_seen        <= cap_sync_2d;
                O_capture_frame <= O_capture_frame + 32'd1;
                if (frames_in_second != 8'hFF)
                    frames_in_second <= frames_in_second + 8'd1;
            end

            if (disp_sync_2d != disp_seen) begin
                disp_seen       <= disp_sync_2d;
                O_display_frame <= O_display_frame + 32'd1;
            end

            if (ref_count == REF_CLOCK_HZ - 1) begin
                ref_count        <= 32'd0;
                O_fps            <= frames_in_second;
                frames_in_second <= 8'd0;
            end else begin
                ref_count <= ref_count + 32'd1;
            end
        end
    end

endmodule
