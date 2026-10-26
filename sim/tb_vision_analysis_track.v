`timescale 1ns/1ps

module tb_vision_analysis_track;
    localparam integer IMG_WIDTH = 640;
    localparam integer IMG_HEIGHT = 32;
    localparam integer BEATS_PER_LINE = IMG_WIDTH / 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg tlast = 1'b0;
    reg tuser = 1'b0;
    reg [95:0] tdata = 96'd0;
    reg tvalid = 1'b0;
    reg tready = 1'b1;

    reg target_enable = 1'b0;
    reg decoy_enable = 1'b0;
    integer target_x_min = 0;
    integer target_x_max = 0;
    integer target_y_min = 0;
    integer target_y_max = 0;
    integer decoy_x_min = 400;
    integer decoy_x_max = 435;
    integer decoy_y_min = 6;
    integer decoy_y_max = 25;
    integer row_idx;
    integer beat_idx;
    integer pixel_x;

    wire out_tlast;
    wire out_tuser;
    wire [95:0] out_tdata;
    wire out_tvalid;
    wire out_tready;
    wire plate_valid;
    wire [10:0] plate_x_min, plate_x_max, plate_y_min, plate_y_max;
    wire [7:0] plate_code0, plate_code1, plate_code2;
    wire [7:0] plate_code3, plate_code4, plate_code5;
    wire track_valid;
    wire [10:0] track_x_min, track_x_max, track_y_min, track_y_max;
    wire motion_active;
    wire [10:0] motion_x_min, motion_x_max, motion_y_min, motion_y_max;
    wire external_event;

    always #5 clk = ~clk;

    vision_analysis_96 #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(tlast), .I_tuser(tuser), .I_tdata(tdata),
        .I_tvalid(tvalid), .I_tready(tready),
        .O_tlast(out_tlast), .O_tuser(out_tuser), .O_tdata(out_tdata),
        .O_tvalid(out_tvalid), .O_tready(out_tready),
        .O_plate_valid(plate_valid),
        .O_plate_x_min(plate_x_min), .O_plate_x_max(plate_x_max),
        .O_plate_y_min(plate_y_min), .O_plate_y_max(plate_y_max),
        .O_plate_code0(plate_code0), .O_plate_code1(plate_code1),
        .O_plate_code2(plate_code2), .O_plate_code3(plate_code3),
        .O_plate_code4(plate_code4), .O_plate_code5(plate_code5),
        .O_track_valid(track_valid),
        .O_track_x_min(track_x_min), .O_track_x_max(track_x_max),
        .O_track_y_min(track_y_min), .O_track_y_max(track_y_max),
        .O_motion_active(motion_active),
        .O_motion_x_min(motion_x_min), .O_motion_x_max(motion_x_max),
        .O_motion_y_min(motion_y_min), .O_motion_y_max(motion_y_max),
        .O_external_event(external_event)
    );

    function [23:0] pixel_at;
        input integer x;
        input integer y;
        begin
            pixel_at = 24'h101010;
            if (target_enable && (x >= target_x_min) && (x <= target_x_max) &&
                (y >= target_y_min) && (y <= target_y_max))
                pixel_at = 24'hFF1010;
            if (decoy_enable && (x >= decoy_x_min) && (x <= decoy_x_max) &&
                (y >= decoy_y_min) && (y <= decoy_y_max))
                pixel_at = 24'hFF1010;
        end
    endfunction

    task send_frame;
        begin
            for (row_idx = 0; row_idx < IMG_HEIGHT; row_idx = row_idx + 1) begin
                for (beat_idx = 0; beat_idx < BEATS_PER_LINE; beat_idx = beat_idx + 1) begin
                    @(negedge clk);
                    pixel_x = beat_idx * 4;
                    tvalid = 1'b1;
                    tuser = (row_idx == 0) && (beat_idx == 0);
                    tlast = (beat_idx == BEATS_PER_LINE - 1);
                    tdata = {pixel_at(pixel_x, row_idx),
                             pixel_at(pixel_x + 1, row_idx),
                             pixel_at(pixel_x + 2, row_idx),
                             pixel_at(pixel_x + 3, row_idx)};
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tlast = 1'b0;
            tuser = 1'b0;
            tdata = 96'd0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // A small red speck must not acquire a target.
        target_enable = 1'b1;
        target_x_min = 20; target_x_max = 23;
        target_y_min = 4;  target_y_max = 7;
        send_frame;
        if (track_valid !== 1'b0)
            $fatal(1, "FAIL: small red speck acquired as target");

        // Acquire a valid object and verify its first full-frame bounds.
        target_x_min = 20; target_x_max = 55;
        target_y_min = 4;  target_y_max = 23;
        send_frame;
        if (!track_valid || track_x_min != 11'd20 || track_x_max != 11'd55 ||
            track_y_min != 11'd4 || track_y_max != 11'd23)
            $fatal(1, "FAIL: initial box wrong: v=%b x=%0d..%0d y=%0d..%0d",
                   track_valid, track_x_min, track_x_max, track_y_min, track_y_max);

        // A nearby moving object is associated and smoothed; a distant red
        // decoy must not expand the tracked box.
        target_x_min = 24; target_x_max = 59;
        target_y_min = 6;  target_y_max = 25;
        decoy_enable = 1'b1;
        send_frame;
        if (!track_valid || track_x_min != 11'd21 || track_x_max != 11'd56 ||
            track_y_min != 11'd5 || track_y_max != 11'd24)
            $fatal(1, "FAIL: association/smoothing failed: v=%b x=%0d..%0d y=%0d..%0d",
                   track_valid, track_x_min, track_x_max, track_y_min, track_y_max);

        // Hold the last valid coordinates through three missed frames, then
        // release the track on the fourth missed frame.
        target_enable = 1'b0;
        repeat (3) begin
            send_frame;
            if (!track_valid || track_x_min != 11'd21 || track_y_min != 11'd5)
                $fatal(1, "FAIL: short occlusion hold lost or moved the target");
        end
        send_frame;
        if (track_valid !== 1'b0)
            $fatal(1, "FAIL: stale target was not released after hold window");

        // Once released, search the full frame and acquire a newly positioned target.
        decoy_enable = 1'b0;
        target_enable = 1'b1;
        target_x_min = 300; target_x_max = 335;
        target_y_min = 6;   target_y_max = 25;
        send_frame;
        if (!track_valid || track_x_min != 11'd300 || track_x_max != 11'd335 ||
            track_y_min != 11'd6 || track_y_max != 11'd25)
            $fatal(1, "FAIL: full-frame reacquisition failed");

        $display("PASS: target filtering, association, smoothing, occlusion hold, and reacquisition");
        $finish;
    end
endmodule
