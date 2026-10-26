//===========================================================================
//  my_algo_core.v  ——  基础算法、自动质量调节和自主伪彩算法
//  模式编码：0=Model1彩色，1=Model2二值化，2=Model3边缘备用，3=Model4灰度
//===========================================================================
module my_algo_core #(
    parameter IMG_WIDTH=1280, parameter IMG_HEIGHT=720
)(
    input I_clk, input I_rst_n, input I_tlast, input I_tuser,
    input [95:0] I_tdata, input I_tvalid, input I_tready,
    output reg O_tlast, output reg O_tuser, output reg [95:0] O_tdata,
    output reg O_tvalid, output O_tready,
    input [1:0] I_mode, input [7:0] I_th_offset,
    input I_quality_en, input I_creative_en,
    output reg [7:0] O_luma_avg
);
    assign O_tready=I_tready;
    wire [23:0] pix0=I_tdata[95:72], pix1=I_tdata[71:48], pix2=I_tdata[47:24], pix3=I_tdata[23:0];

    // Sample one pixel from every 128x32 block. The accumulated channel
    // averages are used only once per frame, so the feedback path stays out
    // of the critical per-pixel multiply path.
    reg [8:0]  quality_x_grp;
    reg [10:0] quality_y_pos;
    reg [17:0] quality_r_sum;
    reg [17:0] quality_g_sum;
    reg [17:0] quality_b_sum;
    reg [7:0]  quality_r_offset;
    reg [7:0]  quality_g_offset;
    reg [7:0]  quality_b_offset;
    wire quality_sample = I_tvalid && (quality_x_grp[4:0] == 5'd0) &&
                           (quality_y_pos[4:0] == 5'd0);

    // Per-channel adaptive correction.  The sampled average is scaled by
    // 230/256 for 1280x720, so the control thresholds are expressed in that
    // scaled domain.  A slow, bounded frame loop avoids a divider in the pixel
    // path and limits visible pumping when scene content changes.
    function [7:0] quality_next_offset;
        input [17:0] sum;
        input [17:0] peer_sum0;
        input [17:0] peer_sum1;
        input [7:0] old_offset;
        reg [7:0] avg;
        reg [8:0] peer_avg;
        reg signed [9:0] next_value;
        begin
            // About 230 samples per frame; >>8 approximates division by 256.
            avg = sum[17:8];
            peer_avg = ({1'b0,peer_sum0[17:8]} + {1'b0,peer_sum1[17:8]}) >> 1;
            next_value = $signed(old_offset);

            // Digital brightness correction.  These limits correspond to an
            // approximate scene luma of 116..165 for the default frame size.
            if (avg < 8'd104)
                next_value = next_value + 2;
            else if (avg > 8'd148)
                next_value = next_value - 2;

            // Gray-world white balance with a dead band to prevent hunting.
            if ({1'b0,avg} + 9'd10 < peer_avg)
                next_value = next_value + 2;
            else if ({1'b0,avg} > peer_avg + 9'd10)
                next_value = next_value - 2;

            if (next_value > 10'sd64)
                next_value = 10'sd64;
            else if (next_value < -10'sd32)
                next_value = -10'sd32;
            quality_next_offset = next_value[7:0];
        end
    endfunction

    function [7:0] quality_channel;
        input [7:0] value;
        input [7:0] offset;
        reg signed [9:0] adjusted;
        begin
            adjusted = $signed({1'b0, value}) + $signed(offset);
            if (adjusted < 0)
                quality_channel = 8'd0;
            else if (adjusted > 10'sd255)
                quality_channel = 8'd255;
            else
                quality_channel = adjusted[7:0];
        end
    endfunction

    function [23:0] quality_pixel;
        input [23:0] p;
        input quality_en;
        begin
            if (quality_en)
                quality_pixel = {quality_channel(p[23:16], quality_r_offset),
                                 quality_channel(p[15:8],  quality_g_offset),
                                 quality_channel(p[7:0],   quality_b_offset)};
            else
                quality_pixel = p;
        end
    endfunction

    wire [23:0] quality_pix0 = quality_pixel(pix0, I_quality_en);
    wire [23:0] quality_pix1 = quality_pixel(pix1, I_quality_en);
    wire [23:0] quality_pix2 = quality_pixel(pix2, I_quality_en);
    wire [23:0] quality_pix3 = quality_pixel(pix3, I_quality_en);

    // Timing-friendly luma approximation: 0.25R + 0.5G + 0.25B.
    // It avoids three per-pixel multipliers while preserving the brightness
    // ordering needed by grayscale, thresholding and auto-quality control.
    function [7:0] luma8; input [23:0] p; reg [9:0] s; begin
        s = ({2'b00,p[23:16]} >> 2) +
            ({2'b00,p[15:8]}  >> 1) +
            ({2'b00,p[7:0]}   >> 2);
        luma8 = (s > 10'd255) ? 8'hFF : s[7:0];
    end endfunction
    wire [7:0] g0=luma8(quality_pix0), g1=luma8(quality_pix1),
               g2=luma8(quality_pix2), g3=luma8(quality_pix3);
    wire [9:0] beat_sum={2'b00,g0}+{2'b00,g1}+{2'b00,g2}+{2'b00,g3};
    wire [7:0] beat_avg=beat_sum[9:2];
    reg [7:0] luma_avg;
    wire [7:0] luma_diff=(beat_avg>luma_avg)?(beat_avg-luma_avg):(luma_avg-beat_avg);
    wire [7:0] luma_step=((luma_diff>>3)==8'd0)?8'd1:(luma_diff>>3);
    wire [7:0] luma_next=(beat_avg>luma_avg)?(luma_avg+luma_step):(luma_avg-luma_step);
    wire [8:0] th_sum={1'b0,luma_avg}+{1'b0,I_th_offset};
    wire [7:0] th_cur=(th_sum>9'd255)?8'd255:th_sum[7:0];
    function [23:0] creative_pix;
        input [7:0] g;
        reg [7:0] ramp;
        begin
            // A four-band thermal/pseudo-colour map is the autonomous design
            // feature.  It is entirely combinational and costs no frame RAM.
            ramp = {g[5:0], 2'b00};
            case (g[7:6])
                2'b00: creative_pix = {8'h00, ramp, 8'hFF};
                2'b01: creative_pix = {8'h00, 8'hFF, 8'hFF-ramp};
                2'b10: creative_pix = {ramp, 8'hFF, 8'h00};
                default: creative_pix = {8'hFF, 8'hFF-ramp, 8'h00};
            endcase
        end
    endfunction

    function [23:0] proc_pix;
        input [23:0] p; input [7:0] g; input [7:0] th; input [1:0] md;
        begin
            if (I_creative_en && (md == 2'd0))
                proc_pix = creative_pix(g);
            else begin
                case(md)
                    2'd0: proc_pix=p;
                    2'd1: proc_pix=(g>=th)?24'hFFFFFF:24'h000000;
                    2'd2: proc_pix={g,g,g};
                    default: proc_pix={g,g,g};
                endcase
            end
        end
    endfunction
    wire [23:0] q0=proc_pix(quality_pix0,g0,th_cur,I_mode),
                q1=proc_pix(quality_pix1,g1,th_cur,I_mode),
                q2=proc_pix(quality_pix2,g2,th_cur,I_mode),
                q3=proc_pix(quality_pix3,g3,th_cur,I_mode);
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_tlast<=0; O_tuser<=0; O_tdata<=0; O_tvalid<=0;
            luma_avg<=8'd96; O_luma_avg<=8'd96;
            quality_x_grp<=0; quality_y_pos<=0;
            quality_r_sum<=0; quality_g_sum<=0; quality_b_sum<=0;
            quality_r_offset<=0; quality_g_offset<=0; quality_b_offset<=0;
        end
        else begin
            O_tlast<=I_tlast; O_tuser<=I_tuser; O_tvalid<=I_tvalid;
            if(I_tvalid && I_tready) begin
                luma_avg<=luma_next; O_luma_avg<=luma_avg; O_tdata<={q0,q1,q2,q3};

                if (I_tuser) begin
                    quality_x_grp <= 9'd1;
                    quality_y_pos <= 11'd0;
                    quality_r_sum <= quality_sample ? {10'd0,quality_pix0[23:16]} : 18'd0;
                    quality_g_sum <= quality_sample ? {10'd0,quality_pix0[15:8]}  : 18'd0;
                    quality_b_sum <= quality_sample ? {10'd0,quality_pix0[7:0]}   : 18'd0;
                end else begin
                    if (quality_sample) begin
                        quality_r_sum <= quality_r_sum + {10'd0,quality_pix0[23:16]};
                        quality_g_sum <= quality_g_sum + {10'd0,quality_pix0[15:8]};
                        quality_b_sum <= quality_b_sum + {10'd0,quality_pix0[7:0]};
                    end
                    if (I_tlast) begin
                        quality_x_grp <= 9'd0;
                        if (quality_y_pos == IMG_HEIGHT-1) begin
                            quality_y_pos <= 11'd0;
                            if (I_quality_en) begin
                                quality_r_offset <= quality_next_offset(quality_r_sum, quality_g_sum, quality_b_sum, quality_r_offset);
                                quality_g_offset <= quality_next_offset(quality_g_sum, quality_r_sum, quality_b_sum, quality_g_offset);
                                quality_b_offset <= quality_next_offset(quality_b_sum, quality_r_sum, quality_g_sum, quality_b_offset);
                            end else begin
                                quality_r_offset <= 0;
                                quality_g_offset <= 0;
                                quality_b_offset <= 0;
                            end
                            quality_r_sum <= 0;
                            quality_g_sum <= 0;
                            quality_b_sum <= 0;
                        end else
                            quality_y_pos <= quality_y_pos + 1'b1;
                    end else
                        quality_x_grp <= quality_x_grp + 1'b1;
                end
            end else if (!I_tvalid)
                O_tdata<=96'd0;
        end
    end
endmodule

// ---------------------------------------------------------------------------
// Low-cost scene analysis.
//
// The detector is deliberately deterministic and stream-safe:
//   * blue chroma candidates form a license-plate region;
//   * red chroma candidates form a tracked target region;
//   * a 16x16 downsampled frame-difference map reports motion;
//   * all results are latched at frame end and can therefore be drawn on the
//     following complete frame without tearing.
//
// This is a hardware plate-region detector, not a general OCR neural network.
// The displayed A12345 code is the fixed hardware demo code until a character
// template/ML accelerator is added.
// ---------------------------------------------------------------------------
module vision_analysis_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    input  wire        I_tready,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    output wire        O_tready,
    output reg         O_plate_valid,
    output reg  [10:0] O_plate_x_min,
    output reg  [10:0] O_plate_x_max,
    output reg  [10:0] O_plate_y_min,
    output reg  [10:0] O_plate_y_max,
    output reg  [7:0]  O_plate_code0,
    output reg  [7:0]  O_plate_code1,
    output reg  [7:0]  O_plate_code2,
    output reg  [7:0]  O_plate_code3,
    output reg  [7:0]  O_plate_code4,
    output reg  [7:0]  O_plate_code5,
    output reg         O_track_valid,
    output reg  [10:0] O_track_x_min,
    output reg  [10:0] O_track_x_max,
    output reg  [10:0] O_track_y_min,
    output reg  [10:0] O_track_y_max,
    output reg         O_motion_active,
    output reg  [10:0] O_motion_x_min,
    output reg  [10:0] O_motion_x_max,
    output reg  [10:0] O_motion_y_min,
    output reg  [10:0] O_motion_y_max,
    output reg         O_external_event
);

    assign O_tready = I_tready;

    wire [23:0] pix0 = I_tdata[95:72];
    wire [23:0] pix1 = I_tdata[71:48];
    wire [23:0] pix2 = I_tdata[47:24];
    wire [23:0] pix3 = I_tdata[23:0];

    reg [8:0]  x_grp;
    reg [10:0] y_pos;
    wire [10:0] x_base = {x_grp,2'b00};
    wire [10:0] x0 = x_base;
    wire [10:0] x1 = x_base + 11'd1;
    wire [10:0] x2 = x_base + 11'd2;
    wire [10:0] x3 = x_base + 11'd3;

    // Timing-friendly luma approximation: 0.25R + 0.5G + 0.25B.
    // This detector only needs monotonic brightness, so shift/add is enough.
    function [7:0] luma8;
        input [23:0] p;
        reg [9:0] s;
        begin
            s = ({2'b00,p[23:16]} >> 2) +
                ({2'b00,p[15:8]}  >> 1) +
                ({2'b00,p[7:0]}   >> 2);
            luma8 = (s > 10'd255) ? 8'hFF : s[7:0];
        end
    endfunction

    function plate_candidate;
        input [23:0] p;
        begin
            // Blue plate chroma; wide margins tolerate the new lens balance.
            plate_candidate = ({1'b0,p[7:0]} > ({1'b0,p[23:16]} + 9'd18)) &&
                               ({1'b0,p[7:0]} > ({1'b0,p[15:8]}  + 9'd8))  &&
                               (p[7:0] > 8'd72);
        end
    endfunction

    function track_candidate;
        input [23:0] p;
        begin
            // Red high-saturation target/laser marker for the 2-D platform.
            track_candidate = (p[23:16] > 8'd120) &&
                              ({1'b0,p[23:16]} > ({1'b0,p[15:8]} + 9'd28)) &&
                              ({1'b0,p[23:16]} > ({1'b0,p[7:0]}  + 9'd28));
        end
    endfunction

    localparam [10:0] TRACK_GATE_X = 11'd96;
    localparam [10:0] TRACK_GATE_Y = 11'd72;
    localparam [2:0]  TRACK_HOLD_FRAMES = 3'd3;
    wire [11:0] track_gate_x_min_calc =
        ({1'b0,O_track_x_min} > {1'b0,TRACK_GATE_X}) ?
        ({1'b0,O_track_x_min} - {1'b0,TRACK_GATE_X}) : 12'd0;
    wire [11:0] track_gate_x_max_calc =
        {1'b0,O_track_x_max} + {1'b0,TRACK_GATE_X};
    wire [11:0] track_gate_y_min_calc =
        ({1'b0,O_track_y_min} > {1'b0,TRACK_GATE_Y}) ?
        ({1'b0,O_track_y_min} - {1'b0,TRACK_GATE_Y}) : 12'd0;
    wire [11:0] track_gate_y_max_calc =
        {1'b0,O_track_y_max} + {1'b0,TRACK_GATE_Y};
    wire [10:0] track_gate_x_min = track_gate_x_min_calc[10:0];
    wire [10:0] track_gate_x_max =
        (track_gate_x_max_calc > 12'd2047) ? 11'd2047 : track_gate_x_max_calc[10:0];
    wire [10:0] track_gate_y_min = track_gate_y_min_calc[10:0];
    wire [10:0] track_gate_y_max =
        (track_gate_y_max_calc > 12'd2047) ? 11'd2047 : track_gate_y_max_calc[10:0];
    wire track_y_in_gate = (y_pos >= track_gate_y_min) &&
                           (y_pos <= track_gate_y_max);

    wire plate0 = plate_candidate(pix0);
    wire plate1 = plate_candidate(pix1);
    wire plate2 = plate_candidate(pix2);
    wire plate3 = plate_candidate(pix3);
    wire track0 = track_candidate(pix0) &&
                  (!O_track_valid || (track_y_in_gate &&
                   (x0 >= track_gate_x_min) && (x0 <= track_gate_x_max)));
    wire track1 = track_candidate(pix1) &&
                  (!O_track_valid || (track_y_in_gate &&
                   (x1 >= track_gate_x_min) && (x1 <= track_gate_x_max)));
    wire track2 = track_candidate(pix2) &&
                  (!O_track_valid || (track_y_in_gate &&
                   (x2 >= track_gate_x_min) && (x2 <= track_gate_x_max)));
    wire track3 = track_candidate(pix3) &&
                  (!O_track_valid || (track_y_in_gate &&
                   (x3 >= track_gate_x_min) && (x3 <= track_gate_x_max)));
    wire plate_has = plate0 | plate1 | plate2 | plate3;
    wire track_has = track0 | track1 | track2 | track3;
    wire [2:0] plate_hits = {2'b0,plate0} + {2'b0,plate1} +
                             {2'b0,plate2} + {2'b0,plate3};
    wire [2:0] track_hits = {2'b0,track0} + {2'b0,track1} +
                             {2'b0,track2} + {2'b0,track3};
    wire [10:0] plate_first_x = plate0 ? x0 : plate1 ? x1 : plate2 ? x2 : x3;
    wire [10:0] plate_last_x  = plate3 ? x3 : plate2 ? x2 : plate1 ? x1 : x0;
    wire [10:0] track_first_x = track0 ? x0 : track1 ? x1 : track2 ? x2 : x3;
    wire [10:0] track_last_x  = track3 ? x3 : track2 ? x2 : track1 ? x1 : x0;

    reg [15:0] plate_count;
    reg [15:0] track_count;
    reg [10:0] plate_min_x, plate_max_x, plate_min_y, plate_max_y;
    reg [10:0] track_min_x, track_max_x, track_min_y, track_max_y;
    reg [2:0] track_lost_frames;
    wire frame_end = I_tlast && (y_pos == IMG_HEIGHT-1);

    wire [16:0] track_count_with_current =
        {1'b0,track_count} + {14'd0,track_hits};
    wire [10:0] track_min_x_with_current =
        track_has && (track_first_x < track_min_x) ? track_first_x : track_min_x;
    wire [10:0] track_max_x_with_current =
        track_has && (track_last_x > track_max_x) ? track_last_x : track_max_x;
    wire [10:0] track_min_y_with_current =
        track_has && (y_pos < track_min_y) ? y_pos : track_min_y;
    wire [10:0] track_max_y_with_current =
        track_has && (y_pos > track_max_y) ? y_pos : track_max_y;
    wire track_detection_valid = (track_count_with_current >= 17'd24) &&
        (track_max_x_with_current > track_min_x_with_current + 11'd12) &&
        (track_max_y_with_current > track_min_y_with_current + 11'd12);

    function [10:0] track_smooth_coord;
        input [10:0] old_value;
        input [10:0] new_value;
        reg [12:0] weighted;
        begin
            weighted = ({2'b00,old_value} << 1) + {2'b00,old_value} +
                        {2'b00,new_value} + 13'd2;
            track_smooth_coord = weighted[12:2];
        end
    endfunction

    // One-frame delayed, low-cost seven-segment template OCR.  The previous
    // frame's blue-plate box is used as the ROI for the current frame.  This
    // avoids a frame RAM and keeps the recognition path bounded; it is intended
    // for the simple printed/digital target used in the competition demo, not
    // for unrestricted street-scene OCR.
    reg        prev_plate_valid;
    reg [10:0] prev_plate_x_min, prev_plate_x_max;
    reg [10:0] prev_plate_y_min, prev_plate_y_max;
    reg [10:0] ocr_zone_w_reg;
    reg [10:0] ocr_z1, ocr_z2, ocr_z3, ocr_z4, ocr_z5;
    reg [5:0]  ocr_seg_count [0:41];
    integer ocr_i;

    wire ocr_roi = prev_plate_valid &&
                   (x0 >= prev_plate_x_min) && (x0 < prev_plate_x_max) &&
                   (y_pos >= prev_plate_y_min) && (y_pos < prev_plate_y_max) &&
                   (x_grp[1:0] == 2'd0) && (y_pos[1:0] == 2'd0);
    // White glyphs on a blue plate and dark glyphs on a light plate are both
    // accepted.  The ROI and the decimation suppress most background noise.
    wire ocr_mark = ocr_roi &&
                    (((pix0[23:16] > 8'd180) && (pix0[15:8] > 8'd180) &&
                      (pix0[7:0] > 8'd180)) ||
                     ((luma8(pix0) < 8'd48) && !plate_candidate(pix0)));

    function [10:0] ocr_zone_start;
        input [2:0] zone;
        begin
            case (zone)
                3'd0: ocr_zone_start = prev_plate_x_min;
                3'd1: ocr_zone_start = ocr_z1;
                3'd2: ocr_zone_start = ocr_z2;
                3'd3: ocr_zone_start = ocr_z3;
                3'd4: ocr_zone_start = ocr_z4;
                default: ocr_zone_start = ocr_z5;
            endcase
        end
    endfunction

    wire [2:0] ocr_zone = (x0 < ocr_z1) ? 3'd0 :
                          (x0 < ocr_z2) ? 3'd1 :
                          (x0 < ocr_z3) ? 3'd2 :
                          (x0 < ocr_z4) ? 3'd3 :
                          (x0 < ocr_z5) ? 3'd4 : 3'd5;
    wire [10:0] ocr_local_x = x0 - ocr_zone_start(ocr_zone);
    wire [10:0] ocr_local_y = y_pos - prev_plate_y_min;

    function [2:0] ocr_segment;
        input [10:0] lx;
        input [10:0] ly;
        input [10:0] w;
        input [10:0] h;
        reg [10:0] xq;
        reg [10:0] yq;
        reg [10:0] mid;
        begin
            ocr_segment = 3'd7;
            xq = w >> 2;
            yq = h >> 2;
            mid = h >> 1;
            if ((w != 0) && (h != 0)) begin
                if ((ly < yq) && (lx >= xq) && (lx < (w - xq)))
                    ocr_segment = 3'd0; // top
                else if ((ly >= (h - yq)) && (lx >= xq) &&
                         (lx < (w - xq)))
                    ocr_segment = 3'd3; // bottom
                else if ((ly >= (mid - 11'd4)) && (ly < (mid + 11'd4)) &&
                         (lx >= xq) && (lx < (w - xq)))
                    ocr_segment = 3'd6; // middle
                else if ((ly >= yq) && (ly < mid) && (lx < xq))
                    ocr_segment = 3'd5; // upper-left
                else if ((ly >= yq) && (ly < mid) && (lx >= (w - xq)))
                    ocr_segment = 3'd1; // upper-right
                else if ((ly >= mid) && (ly < (h - yq)) && (lx < xq))
                    ocr_segment = 3'd4; // lower-left
                else if ((ly >= mid) && (ly < (h - yq)) &&
                         (lx >= (w - xq)))
                    ocr_segment = 3'd2; // lower-right
            end
        end
    endfunction

    wire [2:0] ocr_seg = ocr_segment(ocr_local_x, ocr_local_y,
                                     ocr_zone_w_reg,
                                     prev_plate_y_max - prev_plate_y_min);
    wire [5:0] ocr_index = ({3'd0,ocr_zone} << 3) -
                            {3'd0,ocr_zone} + {3'd0,ocr_seg};

    function [7:0] ocr_digit;
        input [6:0] pat;
        begin
            // Bits: top, upper-right, lower-right, bottom, lower-left,
            // upper-left, middle.
            case (pat)
                7'b0111111: ocr_digit = 8'h30; // 0
                7'b0000110: ocr_digit = 8'h31; // 1
                7'b1011011: ocr_digit = 8'h32; // 2
                7'b1001111: ocr_digit = 8'h33; // 3
                7'b1100110: ocr_digit = 8'h34; // 4
                7'b1101101: ocr_digit = 8'h35; // 5
                7'b1111101: ocr_digit = 8'h36; // 6
                7'b0000111: ocr_digit = 8'h37; // 7
                7'b1111111: ocr_digit = 8'h38; // 8
                7'b1101111: ocr_digit = 8'h39; // 9
                default:    ocr_digit = 8'h3F; // '?' when no template match
            endcase
        end
    endfunction

    wire [6:0] ocr_pat0 = {ocr_seg_count[6]  >= 6'd2,
                            ocr_seg_count[5]  >= 6'd2,
                            ocr_seg_count[4]  >= 6'd2,
                            ocr_seg_count[3]  >= 6'd2,
                            ocr_seg_count[2]  >= 6'd2,
                            ocr_seg_count[1]  >= 6'd2,
                            ocr_seg_count[0]  >= 6'd2};
    wire [6:0] ocr_pat1 = {ocr_seg_count[13] >= 6'd2,
                            ocr_seg_count[12] >= 6'd2,
                            ocr_seg_count[11] >= 6'd2,
                            ocr_seg_count[10] >= 6'd2,
                            ocr_seg_count[9]  >= 6'd2,
                            ocr_seg_count[8]  >= 6'd2,
                            ocr_seg_count[7]  >= 6'd2};
    wire [6:0] ocr_pat2 = {ocr_seg_count[20] >= 6'd2,
                            ocr_seg_count[19] >= 6'd2,
                            ocr_seg_count[18] >= 6'd2,
                            ocr_seg_count[17] >= 6'd2,
                            ocr_seg_count[16] >= 6'd2,
                            ocr_seg_count[15] >= 6'd2,
                            ocr_seg_count[14] >= 6'd2};
    wire [6:0] ocr_pat3 = {ocr_seg_count[27] >= 6'd2,
                            ocr_seg_count[26] >= 6'd2,
                            ocr_seg_count[25] >= 6'd2,
                            ocr_seg_count[24] >= 6'd2,
                            ocr_seg_count[23] >= 6'd2,
                            ocr_seg_count[22] >= 6'd2,
                            ocr_seg_count[21] >= 6'd2};
    wire [6:0] ocr_pat4 = {ocr_seg_count[34] >= 6'd2,
                            ocr_seg_count[33] >= 6'd2,
                            ocr_seg_count[32] >= 6'd2,
                            ocr_seg_count[31] >= 6'd2,
                            ocr_seg_count[30] >= 6'd2,
                            ocr_seg_count[29] >= 6'd2,
                            ocr_seg_count[28] >= 6'd2};
    wire [6:0] ocr_pat5 = {ocr_seg_count[41] >= 6'd2,
                            ocr_seg_count[40] >= 6'd2,
                            ocr_seg_count[39] >= 6'd2,
                            ocr_seg_count[38] >= 6'd2,
                            ocr_seg_count[37] >= 6'd2,
                            ocr_seg_count[36] >= 6'd2,
                            ocr_seg_count[35] >= 6'd2};

    // 80 x 45 samples, four bits of horizontal and vertical decimation.
    // The RAM is intentionally not cleared on reset so the implementation can
    // infer block RAM.  motion_frame_valid masks the first uninitialized frame.
    (* ram_style = "block" *) reg [7:0] motion_mem [0:3599];
    reg motion_frame_valid;
    reg [11:0] motion_count;
    reg [10:0] motion_min_x, motion_max_x, motion_min_y, motion_max_y;
    wire motion_sample_en = (x_grp[1:0] == 2'd0) && (y_pos[3:0] == 4'd0);
    wire [10:0] motion_sample_x = {x_grp,2'b00};
    wire [10:0] motion_sample_y = y_pos;
    wire [12:0] motion_addr = ((y_pos >> 4) * 7'd80) + (x_grp >> 2);
    wire [9:0] motion_sum = {2'b00,luma8(pix0)} + {2'b00,luma8(pix1)} +
                             {2'b00,luma8(pix2)} + {2'b00,luma8(pix3)};
    wire [7:0] motion_value = motion_sum[9:2];
    wire [7:0] motion_old_value = motion_mem[motion_addr];
    wire [8:0] motion_delta = (motion_value >= motion_old_value) ?
                               (motion_value - motion_old_value) :
                               (motion_old_value - motion_value);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast <= 1'b0;
            O_tuser <= 1'b0;
            O_tdata <= 96'd0;
            O_tvalid <= 1'b0;
            x_grp <= 9'd0;
            y_pos <= 11'd0;
            plate_count <= 16'd0;
            track_count <= 16'd0;
            plate_min_x <= 11'd2047;
            plate_max_x <= 11'd0;
            plate_min_y <= 11'd2047;
            plate_max_y <= 11'd0;
            track_min_x <= 11'd2047;
            track_max_x <= 11'd0;
            track_min_y <= 11'd2047;
            track_max_y <= 11'd0;
            track_lost_frames <= 3'd0;
            O_plate_valid <= 1'b0;
            O_track_valid <= 1'b0;
            O_motion_active <= 1'b0;
            O_external_event <= 1'b0;
            O_plate_x_min <= 11'd0;
            O_plate_x_max <= 11'd0;
            O_plate_y_min <= 11'd0;
            O_plate_y_max <= 11'd0;
            O_track_x_min <= 11'd0;
            O_track_x_max <= 11'd0;
            O_track_y_min <= 11'd0;
            O_track_y_max <= 11'd0;
            O_motion_x_min <= 11'd0;
            O_motion_x_max <= 11'd0;
            O_motion_y_min <= 11'd0;
            O_motion_y_max <= 11'd0;
            O_plate_code0 <= 8'h41;
            O_plate_code1 <= 8'h31;
            O_plate_code2 <= 8'h32;
            O_plate_code3 <= 8'h33;
            O_plate_code4 <= 8'h34;
            O_plate_code5 <= 8'h35;
            motion_frame_valid <= 1'b0;
            motion_count <= 12'd0;
            motion_min_x <= 11'd2047;
            motion_max_x <= 11'd0;
            motion_min_y <= 11'd2047;
            motion_max_y <= 11'd0;
            prev_plate_valid <= 1'b0;
            prev_plate_x_min <= 11'd0;
            prev_plate_x_max <= 11'd0;
            prev_plate_y_min <= 11'd0;
            prev_plate_y_max <= 11'd0;
            ocr_zone_w_reg <= 11'd0;
            ocr_z1 <= 11'd0;
            ocr_z2 <= 11'd0;
            ocr_z3 <= 11'd0;
            ocr_z4 <= 11'd0;
            ocr_z5 <= 11'd0;
            for (ocr_i = 0; ocr_i < 42; ocr_i = ocr_i + 1)
                ocr_seg_count[ocr_i] <= 6'd0;
        end else begin
            O_tlast <= I_tlast;
            O_tuser <= I_tuser;
            O_tvalid <= I_tvalid;
            O_external_event <= 1'b0;
            if (I_tvalid && I_tready) begin
                O_tdata <= I_tdata;

                if (I_tuser) begin
                    // Prepare the previous frame's ROI and start a new template pass.
                    if (prev_plate_valid && (prev_plate_x_max > prev_plate_x_min)) begin
                        ocr_zone_w_reg <= (prev_plate_x_max - prev_plate_x_min) / 6;
                        ocr_z1 <= prev_plate_x_min + ((prev_plate_x_max - prev_plate_x_min) / 6);
                        ocr_z2 <= prev_plate_x_min + (((prev_plate_x_max - prev_plate_x_min) * 2) / 6);
                        ocr_z3 <= prev_plate_x_min + (((prev_plate_x_max - prev_plate_x_min) * 3) / 6);
                        ocr_z4 <= prev_plate_x_min + (((prev_plate_x_max - prev_plate_x_min) * 4) / 6);
                        ocr_z5 <= prev_plate_x_min + (((prev_plate_x_max - prev_plate_x_min) * 5) / 6);
                    end else begin
                        ocr_zone_w_reg <= 11'd0;
                        ocr_z1 <= 11'd0;
                        ocr_z2 <= 11'd0;
                        ocr_z3 <= 11'd0;
                        ocr_z4 <= 11'd0;
                        ocr_z5 <= 11'd0;
                    end
                    for (ocr_i = 0; ocr_i < 42; ocr_i = ocr_i + 1)
                        ocr_seg_count[ocr_i] <= 6'd0;
                end else if (ocr_mark && (ocr_seg < 3'd7) && (ocr_index < 6'd42) &&
                             (ocr_seg_count[ocr_index] != 6'h3F)) begin
                    ocr_seg_count[ocr_index] <= ocr_seg_count[ocr_index] + 1'b1;
                end

                if (motion_sample_en) begin
                    if (!I_tuser && motion_frame_valid && (motion_delta >= 9'd24) &&
                        (motion_count != 12'hFFF))
                        motion_count <= motion_count + 1'b1;
                    if (!I_tuser && motion_frame_valid && (motion_delta >= 9'd24)) begin
                        if (motion_sample_x < motion_min_x)
                            motion_min_x <= motion_sample_x;
                        if ((motion_sample_x + 11'd15) > motion_max_x)
                            motion_max_x <= motion_sample_x + 11'd15;
                        if (motion_sample_y < motion_min_y)
                            motion_min_y <= motion_sample_y;
                        if ((motion_sample_y + 11'd15) > motion_max_y)
                            motion_max_y <= motion_sample_y + 11'd15;
                    end
                    motion_mem[motion_addr] <= motion_value;
                end

                if (I_tuser) begin
                    plate_count <= {13'd0,plate_hits};
                    track_count <= {13'd0,track_hits};
                    plate_min_x <= plate_has ? plate_first_x : 11'd2047;
                    plate_max_x <= plate_has ? plate_last_x  : 11'd0;
                    plate_min_y <= plate_has ? y_pos : 11'd2047;
                    plate_max_y <= plate_has ? y_pos : 11'd0;
                    track_min_x <= track_has ? track_first_x : 11'd2047;
                    track_max_x <= track_has ? track_last_x  : 11'd0;
                    track_min_y <= track_has ? y_pos : 11'd2047;
                    track_max_y <= track_has ? y_pos : 11'd0;
                    motion_count <= 12'd0;
                    motion_min_x <= 11'd2047;
                    motion_max_x <= 11'd0;
                    motion_min_y <= 11'd2047;
                    motion_max_y <= 11'd0;
                end else begin
                    if (plate_has) begin
                        if (plate_first_x < plate_min_x) plate_min_x <= plate_first_x;
                        if (plate_last_x  > plate_max_x) plate_max_x <= plate_last_x;
                        if (y_pos < plate_min_y) plate_min_y <= y_pos;
                        if (y_pos > plate_max_y) plate_max_y <= y_pos;
                        if (plate_count <= 16'd65531 - plate_hits)
                            plate_count <= plate_count + plate_hits;
                    end
                    if (track_has) begin
                        if (track_first_x < track_min_x) track_min_x <= track_first_x;
                        if (track_last_x  > track_max_x) track_max_x <= track_last_x;
                        if (y_pos < track_min_y) track_min_y <= y_pos;
                        if (y_pos > track_max_y) track_max_y <= y_pos;
                        if (track_count <= 16'd65531 - track_hits)
                            track_count <= track_count + track_hits;
                    end
                end

                if (frame_end) begin
                    O_plate_valid <= (plate_count >= 16'd80) &&
                                     (plate_max_x > plate_min_x + 11'd80) &&
                                     (plate_max_y > plate_min_y + 11'd12);
                    O_plate_x_min <= plate_min_x;
                    O_plate_x_max <= plate_max_x;
                    O_plate_y_min <= plate_min_y;
                    O_plate_y_max <= plate_max_y;
                    if (track_detection_valid) begin
                        O_track_valid <= 1'b1;
                        track_lost_frames <= 3'd0;
                        if (O_track_valid) begin
                            O_track_x_min <= track_smooth_coord(O_track_x_min,
                                                                 track_min_x_with_current);
                            O_track_x_max <= track_smooth_coord(O_track_x_max,
                                                                 track_max_x_with_current);
                            O_track_y_min <= track_smooth_coord(O_track_y_min,
                                                                 track_min_y_with_current);
                            O_track_y_max <= track_smooth_coord(O_track_y_max,
                                                                 track_max_y_with_current);
                        end else begin
                            O_track_x_min <= track_min_x_with_current;
                            O_track_x_max <= track_max_x_with_current;
                            O_track_y_min <= track_min_y_with_current;
                            O_track_y_max <= track_max_y_with_current;
                        end
                    end else if (O_track_valid &&
                                 (track_lost_frames < TRACK_HOLD_FRAMES)) begin
                        track_lost_frames <= track_lost_frames + 1'b1;
                    end else begin
                        O_track_valid <= 1'b0;
                        track_lost_frames <= 3'd0;
                        O_track_x_min <= 11'd0;
                        O_track_x_max <= 11'd0;
                        O_track_y_min <= 11'd0;
                        O_track_y_max <= 11'd0;
                    end
                    // The first character is a stable A-style prefix for the
                    // simplified target; the five following characters come
                    // from the seven-segment template matcher above.
                    if (prev_plate_valid) begin
                        O_plate_code0 <= 8'h41;
                        O_plate_code1 <= ocr_digit(ocr_pat1);
                        O_plate_code2 <= ocr_digit(ocr_pat2);
                        O_plate_code3 <= ocr_digit(ocr_pat3);
                        O_plate_code4 <= ocr_digit(ocr_pat4);
                        O_plate_code5 <= ocr_digit(ocr_pat5);
                    end else begin
                        O_plate_code0 <= 8'h41;
                        O_plate_code1 <= 8'h31;
                        O_plate_code2 <= 8'h32;
                        O_plate_code3 <= 8'h33;
                        O_plate_code4 <= 8'h34;
                        O_plate_code5 <= 8'h35;
                    end
                    prev_plate_valid <= (plate_count >= 16'd80) &&
                                        (plate_max_x > plate_min_x + 11'd80) &&
                                        (plate_max_y > plate_min_y + 11'd12);
                    prev_plate_x_min <= plate_min_x;
                    prev_plate_x_max <= plate_max_x;
                    prev_plate_y_min <= plate_min_y;
                    prev_plate_y_max <= plate_max_y;
                    if (motion_frame_valid && (motion_count >= 12'd8) &&
                        (motion_max_x >= motion_min_x) &&
                        (motion_max_y >= motion_min_y)) begin
                        O_motion_active <= 1'b1;
                        O_motion_x_min <= motion_min_x;
                        O_motion_x_max <= motion_max_x;
                        O_motion_y_min <= motion_min_y;
                        O_motion_y_max <= motion_max_y;
                    end else begin
                        O_motion_active <= 1'b0;
                        O_motion_x_min <= 11'd0;
                        O_motion_x_max <= 11'd0;
                        O_motion_y_min <= 11'd0;
                        O_motion_y_max <= 11'd0;
                    end
                    O_external_event <= (plate_count >= 16'd80) || track_detection_valid;
                    motion_frame_valid <= 1'b1;
                    motion_count <= 12'd0;
                end

                if (I_tuser) begin
                    x_grp <= 9'd1;
                    y_pos <= 11'd0;
                end else if (I_tlast) begin
                    x_grp <= 9'd0;
                    y_pos <= (y_pos == IMG_HEIGHT-1) ? 11'd0 : y_pos + 1'b1;
                end else begin
                    x_grp <= x_grp + 1'b1;
                end
            end else if (!I_tvalid) begin
                O_tdata <= 96'd0;
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// External-control UART.  This sends a compact detection packet only; it never
// streams image data.  Packet (8 bytes, 8-N-1):
//   AA 55 status X_LO X_HI Y_LO Y_HI checksum
// status bit0=plate, bit1=tracked.  Full 11-bit coordinates are preserved.
// ---------------------------------------------------------------------------
module vision_external_ctrl_tx #(
    parameter integer CLOCK_HZ = 100000000,
    parameter integer BAUD     = 115200
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire       I_enable,
    input  wire       I_event_toggle,
    input  wire       I_plate_valid,
    input  wire       I_track_valid,
    input  wire [10:0] I_x,
    input  wire [10:0] I_y,
    output reg        O_tx
);
    localparam integer BAUD_DIV = CLOCK_HZ / BAUD;
    reg [15:0] baud_count;
    reg [3:0]  bit_count;
    reg [3:0]  byte_index;
    reg [7:0]  byte_data;
    reg [7:0]  status_byte;
    reg [7:0]  x_lo;
    reg [7:0]  x_hi;
    reg [7:0]  y_lo;
    reg [7:0]  y_hi;
    reg [7:0]  checksum;
    reg        busy;
    reg        event_sync1;
    reg        event_sync2;
    reg        event_seen;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            baud_count <= 16'd0;
            bit_count <= 4'd0;
            byte_index <= 4'd0;
            byte_data <= 8'd0;
            status_byte <= 8'd0;
            x_lo <= 8'd0;
            x_hi <= 8'd0;
            y_lo <= 8'd0;
            y_hi <= 8'd0;
            checksum <= 8'd0;
            busy <= 1'b0;
            event_sync1 <= 1'b0;
            event_sync2 <= 1'b0;
            event_seen <= 1'b0;
            O_tx <= 1'b1;
        end else begin
            event_sync1 <= I_event_toggle;
            event_sync2 <= event_sync1;
            if (!I_enable) begin
                baud_count <= 16'd0;
                bit_count <= 4'd0;
                byte_index <= 4'd0;
                busy <= 1'b0;
                event_seen <= event_sync2;
                O_tx <= 1'b1;
            end else if (!busy) begin
                O_tx <= 1'b1;
                if (event_sync2 != event_seen) begin
                    event_seen <= event_sync2;
                    status_byte <= {6'd0,I_track_valid,I_plate_valid};
                    x_lo <= I_x[7:0];
                    x_hi <= {5'd0,I_x[10:8]};
                    y_lo <= I_y[7:0];
                    y_hi <= {5'd0,I_y[10:8]};
                    checksum <= 8'hAA ^ 8'h55 ^ {6'd0,I_track_valid,I_plate_valid} ^
                                I_x[7:0] ^ {5'd0,I_x[10:8]} ^
                                I_y[7:0] ^ {5'd0,I_y[10:8]};
                    byte_index <= 4'd0;
                    bit_count <= 4'd0;
                    baud_count <= 16'd0;
                    busy <= 1'b1;
                    byte_data <= 8'hAA;
                    O_tx <= 1'b0; // start bit of AA
                end
            end else if (baud_count == BAUD_DIV-1) begin
                baud_count <= 16'd0;
                if (bit_count == 4'd9) begin
                    bit_count <= 4'd0;
                    if (byte_index == 4'd7) begin
                        busy <= 1'b0;
                        O_tx <= 1'b1;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                        case (byte_index + 1'b1)
                            4'd1: byte_data <= 8'h55;
                            4'd2: byte_data <= status_byte;
                            4'd3: byte_data <= x_lo;
                            4'd4: byte_data <= x_hi;
                            4'd5: byte_data <= y_lo;
                            4'd6: byte_data <= y_hi;
                            default: byte_data <= checksum;
                        endcase
                        O_tx <= 1'b0; // start bit of the next byte
                    end
                end else begin
                    bit_count <= bit_count + 1'b1;
                    if (bit_count == 4'd8)
                        O_tx <= 1'b1; // stop bit
                    else
                        O_tx <= byte_data[bit_count];
                end
            end else begin
                baud_count <= baud_count + 1'b1;
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// First extension stage: selectable stylization plus thresholded ROI filling.
// I_switch is active-high after the top-level board-input inversion:
//   SW1: style enable, SW2: center ROI fill, SW3: pseudo-colour style,
//   SW4: fill colour (0 red, 1 green).
// The ROI fill intentionally uses a fixed hardware-friendly rectangle and
// luminance threshold; this keeps the operation stream-safe and predictable.
// ---------------------------------------------------------------------------
module vision_style_fill_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    input  wire        I_tready,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    output wire        O_tready,
    input  wire [3:0]  I_switch
);

    assign O_tready = I_tready;

    wire [23:0] pix0 = I_tdata[95:72];
    wire [23:0] pix1 = I_tdata[71:48];
    wire [23:0] pix2 = I_tdata[47:24];
    wire [23:0] pix3 = I_tdata[23:0];

    reg [8:0]  x_grp;
    reg [10:0] y_pos;
    wire [10:0] x_base = {x_grp, 2'b00};
    wire [10:0] x0 = x_base;
    wire [10:0] x1 = x_base + 11'd1;
    wire [10:0] x2 = x_base + 11'd2;
    wire [10:0] x3 = x_base + 11'd3;

    function [7:0] approx_luma;
        input [23:0] p;
        begin
            approx_luma = {2'b00, p[23:18]} +
                          {1'b0,  p[15:9]}  +
                          {2'b00, p[7:2]};
        end
    endfunction

    function [23:0] style_pixel;
        input [23:0] p;
        input [3:0]  sw;
        reg [7:0] luma;
        reg [7:0] ramp;
        begin
            if (!sw[0]) begin
                style_pixel = p;
            end else if (!sw[2]) begin
                // Posterization: four bits per channel, replicated to 8 bits.
                style_pixel = {{2{p[23:20]}},
                               {2{p[15:12]}},
                               {2{p[7:4]}}};
            end else begin
                // Four-segment pseudo-colour map from blue through red.
                luma = approx_luma(p);
                ramp = {luma[5:0], 2'b00};
                case (luma[7:6])
                    2'b00: style_pixel = {8'h00, ramp, 8'hFF};
                    2'b01: style_pixel = {8'h00, 8'hFF, 8'hFF - ramp};
                    2'b10: style_pixel = {ramp, 8'hFF, 8'h00};
                    default: style_pixel = {8'hFF, 8'hFF - ramp, 8'h00};
                endcase
            end
        end
    endfunction

    function [23:0] fill_pixel;
        input [23:0] base;
        input [3:0]  sw;
        input [10:0] x;
        input [10:0] y;
        reg [7:0] luma;
        reg [23:0] fill_color;
        begin
            luma = approx_luma(base);
            fill_color = sw[3] ? 24'h20E060 : 24'hFF3030;
            fill_pixel = base;

            if (sw[1] &&
                ((((x == 11'd320) || (x == 11'd959)) &&
                  (y >= 11'd180) && (y < 11'd540)) ||
                 (((y == 11'd180) || (y == 11'd539)) &&
                  (x >= 11'd320) && (x < 11'd960)))) begin
                fill_pixel = fill_color;
            end else if (sw[1] && (x >= 11'd320) && (x < 11'd960) &&
                         (y >= 11'd180) && (y < 11'd540) &&
                         (luma >= 8'd128)) begin
                fill_pixel = fill_color;
            end
        end
    endfunction

    wire [23:0] style0 = style_pixel(pix0, I_switch);
    wire [23:0] style1 = style_pixel(pix1, I_switch);
    wire [23:0] style2 = style_pixel(pix2, I_switch);
    wire [23:0] style3 = style_pixel(pix3, I_switch);

    wire [23:0] out0 = fill_pixel(style0, I_switch, x0, y_pos);
    wire [23:0] out1 = fill_pixel(style1, I_switch, x1, y_pos);
    wire [23:0] out2 = fill_pixel(style2, I_switch, x2, y_pos);
    wire [23:0] out3 = fill_pixel(style3, I_switch, x3, y_pos);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
            x_grp    <= 9'd0;
            y_pos    <= 11'd0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;

            if (I_tvalid && I_tready) begin
                O_tdata <= {out0, out1, out2, out3};

                if (I_tuser) begin
                    x_grp <= 9'd1;
                    y_pos <= 11'd0;
                end else if (I_tlast) begin
                    x_grp <= 9'd0;
                    y_pos <= (y_pos == (IMG_HEIGHT - 1)) ? 11'd0 : y_pos + 11'd1;
                end else begin
                    x_grp <= x_grp + 9'd1;
                end
            end else if (!I_tvalid) begin
                O_tdata <= 96'd0;
            end
        end
    end

endmodule
