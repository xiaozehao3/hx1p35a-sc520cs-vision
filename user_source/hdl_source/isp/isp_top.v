// Minimal camera display path with frame-safe algorithm switching.
//
// RAW10 -> AXI stream -> Bayer demosaic -> packed RGB888 -> fixed white
// balance -> parallel algorithm paths (Sobel / grayscale / binarization /
// color bypass) -> example-style OSD -> contiguous RGB888 DDR stream.
//
// The demosaic block outputs four RGB pixels in four 32-bit words.  The
// padding byte in each word must be removed before video_in writes DDR,
// because video_out reads a continuous stream of 24-bit RGB pixels.
module isp_top (
    input               axi4s_video_aclk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input      [39:0]   I_tdata,
    input               I_tvalid,
    input      [9:0]    I_tdest,
    input               O_tready,
    output     [127:0]  O_tdata,
    output              O_tlast,
    output              O_tuser,
    output              O_tvalid,
    output              I_tready,

    input      [1:0]    I_algo_mode,
    input      [7:0]    I_algo_th_offset,
    input               I_osd_en,
    input      [3:0]    I_switch,
    input      [3:0]    I_ui_page,
    input      [3:0]    I_ui_menu_index,
    input               I_ui_in_menu,
    input      [7:0]    I_fps,
    input      [31:0]   I_capture_frame,
    input      [31:0]   I_display_frame,
    input      [7:0]    I_latency_frame,
    input               I_uart_clk,
    input               I_uart_rx,
    output              O_uart_tx
);

    wire        S_demosaic_tlast;
    wire        S_demosaic_tuser;
    wire [127:0] S_demosaic_tdata;
    wire        S_demosaic_tvalid;
    wire        S_demosaic_tready;

    wire [95:0]  S_rgb96_raw;
    wire [95:0]  S_rgb96;

    // Parallel algorithm outputs.  All three paths have the same one-beat
    // stream latency and receive the same tuser/tlast markers.
    wire [95:0] S_algo_core_tdata;
    wire        S_algo_core_tlast;
    wire        S_algo_core_tuser;
    wire        S_algo_core_tvalid;
    wire        S_algo_core_tready;
    wire [7:0]  S_algo_core_luma;

    wire [95:0] S_analysis_tdata;
    wire        S_analysis_tlast;
    wire        S_analysis_tuser;
    wire        S_analysis_tvalid;
    wire        S_analysis_tready;
    wire        S_analysis_plate_valid;
    wire [10:0] S_analysis_plate_x_min;
    wire [10:0] S_analysis_plate_x_max;
    wire [10:0] S_analysis_plate_y_min;
    wire [10:0] S_analysis_plate_y_max;
    wire [7:0]  S_analysis_plate_code0;
    wire [7:0]  S_analysis_plate_code1;
    wire [7:0]  S_analysis_plate_code2;
    wire [7:0]  S_analysis_plate_code3;
    wire [7:0]  S_analysis_plate_code4;
    wire [7:0]  S_analysis_plate_code5;
    wire        S_analysis_track_valid;
    wire [10:0] S_analysis_track_x_min;
    wire [10:0] S_analysis_track_x_max;
    wire [10:0] S_analysis_track_y_min;
    wire [10:0] S_analysis_track_y_max;
    wire        S_analysis_motion_active;
    wire [10:0] S_analysis_motion_x_min;
    wire [10:0] S_analysis_motion_x_max;
    wire [10:0] S_analysis_motion_y_min;
    wire [10:0] S_analysis_motion_y_max;
    wire        S_analysis_external_event;

    wire [95:0] S_edge_tdata;
    wire        S_edge_tlast;
    wire        S_edge_tuser;
    wire        S_edge_tvalid;
    wire        S_edge_tready;

    wire [95:0] S_algo_tdata;
    wire        S_algo_tlast;
    wire        S_algo_tuser;
    wire        S_algo_tvalid;
    wire [7:0]  S_algo_luma;

    wire [95:0] S_visual_tdata;
    wire        S_visual_tlast;
    wire        S_visual_tuser;
    wire        S_visual_tvalid;
    wire        S_visual_tready;

    wire        S_osd_tlast;
    wire        S_osd_tuser;
    wire [95:0] S_osd_tdata;
    wire        S_osd_tvalid;
    wire        S_osd_tready;
    wire        S_ui_tlast;
    wire        S_ui_tuser;
    wire [95:0] S_ui_tdata;
    wire        S_ui_tvalid;
    wire        S_ui_tready;

    // PC still-image UART source.  It is selected only after a complete
    // CRC-valid frame has been received on the PC image page.
    wire        S_pc_image_tlast;
    wire        S_pc_image_tuser;
    wire [95:0] S_pc_image_tdata;
    wire        S_pc_image_tvalid;
    wire        S_pc_image_valid;
    wire        S_pc_image_active;
    wire [15:0] S_pc_rx_byte_count_uart;
    wire [15:0] S_pc_frame_ok_count_uart;
    wire [15:0] S_pc_frame_error_count_uart;
    reg  [15:0] S_pc_rx_byte_count_sync1;
    reg  [15:0] S_pc_rx_byte_count_sync2;
    reg  [15:0] S_pc_frame_ok_count_sync1;
    reg  [15:0] S_pc_frame_ok_count_sync2;
    reg  [15:0] S_pc_frame_error_count_sync1;
    reg  [15:0] S_pc_frame_error_count_sync2;
    wire        S_video_src_tlast;
    wire        S_video_src_tuser;
    wire [95:0] S_video_src_tdata;
    wire        S_video_src_tvalid;

    wire        S_packed_tlast;
    wire        S_packed_tuser;
    wire [127:0] S_packed_tdata;
    wire        S_packed_tvalid;

    // The external controls are pending controls.  They are sampled only at
    // a frame start, so one frame never contains two different algorithms or
    // half old/half new OSD settings.
    reg  [1:0] S_active_mode;
    reg        S_active_osd_en;
    reg  [3:0] S_active_switch;
    reg  [3:0] S_active_page;
    reg        S_ctrl_event_toggle;
    wire [1:0] S_mode_for_input =
        (S_demosaic_tvalid && S_demosaic_tuser) ? I_algo_mode : S_active_mode;
    wire [3:0] S_switch_for_input =
        (S_demosaic_tvalid && S_demosaic_tuser) ? I_switch : S_active_switch;
    wire [3:0] S_page_for_input =
        (S_demosaic_tvalid && S_demosaic_tuser) ? I_ui_page : S_active_page;

    // Switch sources only at the start of a complete source frame.  The PC
    // image bridge continuously replays its last CRC-valid still image; the
    // camera path remains selected until a PC frame boundary is available.
    wire S_pc_image_page_requested = (S_active_page == 4'd5) && S_pc_image_valid;
    reg  S_pc_image_source_active;
    wire S_pc_frame_start = S_pc_image_tvalid && S_pc_image_tuser;
    wire S_camera_frame_start = S_analysis_tvalid && S_analysis_tuser;
    wire S_select_pc_handoff = !S_pc_image_source_active &&
                               S_pc_image_page_requested && S_pc_frame_start &&
                               S_ui_tready;
    wire S_select_camera_handoff = S_pc_image_source_active &&
                                   !S_pc_image_page_requested &&
                                   S_camera_frame_start && S_ui_tready;
    wire S_use_pc_image = S_pc_image_source_active ?
                          !S_select_camera_handoff : S_select_pc_handoff;

    always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
        if (!I_rst_n)
            S_pc_image_source_active <= 1'b0;
        else if (S_select_pc_handoff)
            S_pc_image_source_active <= 1'b1;
        else if (S_select_camera_handoff)
            S_pc_image_source_active <= 1'b0;
    end

    assign S_video_src_tlast  = S_use_pc_image ? S_pc_image_tlast  : S_analysis_tlast;
    assign S_video_src_tuser  = S_use_pc_image ? S_pc_image_tuser  : S_analysis_tuser;
    assign S_video_src_tdata  = S_use_pc_image ? S_pc_image_tdata  : S_analysis_tdata;
    assign S_video_src_tvalid = S_use_pc_image ? S_pc_image_tvalid : S_analysis_tvalid;

    always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_active_mode    <= 2'd0; // default: Model1 color bypass
            S_active_osd_en  <= 1'b1; // OSD always visible
            S_active_switch  <= 4'b0000;
            S_active_page    <= 4'd0;
        end else if (S_demosaic_tvalid && S_demosaic_tuser) begin
            S_active_mode    <= I_algo_mode;
            S_active_osd_en  <= I_osd_en;
            S_active_switch  <= I_switch;
            S_active_page    <= I_ui_page;
        end
    end

    always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
        if (!I_rst_n)
            S_ctrl_event_toggle <= 1'b0;
        else if (S_analysis_external_event)
            S_ctrl_event_toggle <= ~S_ctrl_event_toggle;
    end

    demosaic #(
        .IMG_HEIGHT          (720),
        .IMG_WIDTH           (1280),
        .data_complete_delay (50),
        .BAYER_MODE          ("BGGR")
    ) u_demosaic (
        .I_clk              (axi4s_video_aclk),
        .I_rst_n            (I_rst_n),
        .axi4s_video_tdata  (I_tdata),
        .axi4s_video_tdest  (I_tdest),
        .axi4s_video_tlast  (I_tlast),
        .axi4s_video_tvalid (I_tvalid),
        .axi4s_video_tuser  (I_tuser),
        .axi4s_video_tready (I_tready),
        .O_tlast            (S_demosaic_tlast),
        .O_tuser            (S_demosaic_tuser),
        .O_tdata            (S_demosaic_tdata),
        .O_tvalid           (S_demosaic_tvalid),
        .O_tready           (S_demosaic_tready)
    );

    // video_in has no back-pressure signal on the camera side.  Keep the
    // demosaic/algorithm/OSD stream running continuously for this design.
    assign S_demosaic_tready = O_tready;

    // Remove the padding byte from each demosaic RGB word.  The result is
    // four RGB888 pixels in 96 bits, ordered from left to right.
    data128_96 u_data128_96 (
        .I_tdata (S_demosaic_tdata),
        .O_tdata (S_rgb96_raw)
    );

    // The replacement lens produced a green cast and the raw image was dark.
    // Fixed white-balance plus a moderate 1.25x brightness gain.
    function [7:0] correct_red;
        input [7:0] value; reg [15:0] wb; reg [17:0] scaled;
        begin wb=value+(value>>2); scaled=wb+(wb>>2); correct_red=(scaled>18'd255)?8'd255:scaled[7:0]; end
    endfunction
    function [7:0] correct_green;
        input [7:0] value; reg [15:0] wb; reg [17:0] scaled;
        begin wb=value-(value>>3); scaled=wb+(wb>>2); correct_green=(scaled>18'd255)?8'd255:scaled[7:0]; end
    endfunction
    function [7:0] correct_blue;
        input [7:0] value; reg [15:0] wb; reg [17:0] scaled;
        begin wb=value+(value>>2); scaled=wb+(wb>>2); correct_blue=(scaled>18'd255)?8'd255:scaled[7:0]; end
    endfunction
    assign S_rgb96 = {
        correct_red(S_rgb96_raw[95:88]), correct_green(S_rgb96_raw[87:80]), correct_blue(S_rgb96_raw[79:72]),
        correct_red(S_rgb96_raw[71:64]), correct_green(S_rgb96_raw[63:56]), correct_blue(S_rgb96_raw[55:48]),
        correct_red(S_rgb96_raw[47:40]), correct_green(S_rgb96_raw[39:32]), correct_blue(S_rgb96_raw[31:24]),
        correct_red(S_rgb96_raw[23:16]), correct_green(S_rgb96_raw[15:8]), correct_blue(S_rgb96_raw[7:0])
    };

    // Required algorithm 1: Sobel edge detection.  The module uses two line
    // buffers and emits four RGB pixels per beat, just like the other path.
    edge_detect_96 #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720),
        .EDGE_TH    (11'd80)
    ) u_edge_detect (
        .I_clk      (axi4s_video_aclk),
        .I_rst_n    (I_rst_n),
        .I_tlast    (S_demosaic_tlast),
        .I_tuser    (S_demosaic_tuser),
        .I_tdata    (S_rgb96),
        .I_tvalid   (S_demosaic_tvalid),
        .I_tready   (O_tready),
        .O_tlast    (S_edge_tlast),
        .O_tuser    (S_edge_tuser),
        .O_tdata    (S_edge_tdata),
        .O_tvalid   (S_edge_tvalid),
        .O_tready   (S_edge_tready)
    );

    // Model1/2/4 use the lightweight core; Model3 uses the Sobel path.
    my_algo_core #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720)
    ) u_algo_core (
        .I_clk       (axi4s_video_aclk),
        .I_rst_n     (I_rst_n),
        .I_tlast     (S_demosaic_tlast),
        .I_tuser     (S_demosaic_tuser),
        .I_tdata     (S_rgb96),
        .I_tvalid    (S_demosaic_tvalid),
        .I_tready    (O_tready),
        .O_tlast     (S_algo_core_tlast),
        .O_tuser     (S_algo_core_tuser),
        .O_tdata     (S_algo_core_tdata),
        .O_tvalid    (S_algo_core_tvalid),
        .O_tready    (S_algo_core_tready),
        .I_mode      (S_mode_for_input),
        .I_th_offset (I_algo_th_offset),
        .I_quality_en (S_page_for_input == 4'd4),
        .I_creative_en(S_page_for_input == 4'd7),
        .O_luma_avg  (S_algo_core_luma)
    );

    // Select only at the frame-latched mode.  Because both paths have the
    // Model3 (mode 2) is the Sobel path.
    assign S_algo_tdata  = (S_active_mode == 2'd2) ? S_edge_tdata  : S_algo_core_tdata;
    assign S_algo_tlast  = (S_active_mode == 2'd2) ? S_edge_tlast  : S_algo_core_tlast;
    assign S_algo_tuser  = (S_active_mode == 2'd2) ? S_edge_tuser  : S_algo_core_tuser;
    assign S_algo_tvalid = (S_active_mode == 2'd2) ? S_edge_tvalid : S_algo_core_tvalid;
    assign S_algo_luma   = S_algo_core_luma;

    // First extension stage: frame-safe visual stylization and ROI filling.
    // The switch values are active-high and are selected from the new frame
    // at its first beat so a switch change cannot split a frame.
    vision_style_fill_96 #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720)
    ) u_vision_style_fill (
        .I_clk      (axi4s_video_aclk),
        .I_rst_n    (I_rst_n),
        .I_tlast    (S_algo_tlast),
        .I_tuser    (S_algo_tuser),
        .I_tdata    (S_algo_tdata),
        .I_tvalid   (S_algo_tvalid),
        .I_tready   (S_analysis_tready),
        .O_tlast    (S_visual_tlast),
        .O_tuser    (S_visual_tuser),
        .O_tdata    (S_visual_tdata),
        .O_tvalid   (S_visual_tvalid),
        .O_tready   (S_visual_tready),
        .I_switch   (S_switch_for_input)
    );

    // Hardware-friendly plate region, target, motion and coordinate analysis.
    vision_analysis_96 #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720)
    ) u_vision_analysis (
        .I_clk           (axi4s_video_aclk),
        .I_rst_n         (I_rst_n),
        .I_tlast         (S_visual_tlast),
        .I_tuser         (S_visual_tuser),
        .I_tdata         (S_visual_tdata),
        .I_tvalid        (S_visual_tvalid),
        .I_tready        (S_ui_tready),
        .O_tlast         (S_analysis_tlast),
        .O_tuser         (S_analysis_tuser),
        .O_tdata         (S_analysis_tdata),
        .O_tvalid        (S_analysis_tvalid),
        .O_tready        (S_analysis_tready),
        .O_plate_valid   (S_analysis_plate_valid),
        .O_plate_x_min   (S_analysis_plate_x_min),
        .O_plate_x_max   (S_analysis_plate_x_max),
        .O_plate_y_min   (S_analysis_plate_y_min),
        .O_plate_y_max   (S_analysis_plate_y_max),
        .O_plate_code0   (S_analysis_plate_code0),
        .O_plate_code1   (S_analysis_plate_code1),
        .O_plate_code2   (S_analysis_plate_code2),
        .O_plate_code3   (S_analysis_plate_code3),
        .O_plate_code4   (S_analysis_plate_code4),
        .O_plate_code5   (S_analysis_plate_code5),
        .O_track_valid   (S_analysis_track_valid),
        .O_track_x_min   (S_analysis_track_x_min),
        .O_track_x_max   (S_analysis_track_x_max),
        .O_track_y_min   (S_analysis_track_y_min),
        .O_track_y_max   (S_analysis_track_y_max),
        .O_motion_active (S_analysis_motion_active),
        .O_motion_x_min  (S_analysis_motion_x_min),
        .O_motion_x_max  (S_analysis_motion_x_max),
        .O_motion_y_min  (S_analysis_motion_y_min),
        .O_motion_y_max  (S_analysis_motion_y_max),
        .O_external_event(S_analysis_external_event)
    );

    // Page 5 uses a short detection/control packet only. Image UART transfer
    // has been removed from this video path.
    wire S_ctrl_uart_tx;

    wire        S_pc_uart_update_toggle;
    wire        S_pc_uart_valid;
    wire [3:0]  S_pc_uart_len;
    wire [87:0] S_pc_uart_chars;
    reg  [1:0]  S_pc_update_sync;
    reg         S_pc_update_seen;
    reg         S_pc_plate_received_pixel;
    reg         S_pc_plate_valid_pixel;
    reg  [3:0]  S_pc_plate_len_pixel;
    reg  [87:0] S_pc_plate_chars_pixel;

    pc_plate_uart_rx #(
        .CLOCK_HZ (100000000),
        .BAUD     (115200),
        .MAX_CHARS(11)
    ) u_pc_plate_uart_rx (
        .I_clk          (I_uart_clk),
        .I_rst_n        (I_rst_n),
        .I_rx           (I_uart_rx),
        .O_update_toggle(S_pc_uart_update_toggle),
        .O_valid        (S_pc_uart_valid),
        .O_length       (S_pc_uart_len),
        .O_chars        (S_pc_uart_chars)
    );

    // The UART holds its result until the next complete packet.  Synchronize
    // the update toggle, then sample that stable result bus in the video clock.
    always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_pc_update_sync       <= 2'b00;
            S_pc_update_seen       <= 1'b0;
            S_pc_plate_received_pixel <= 1'b0;
            S_pc_plate_valid_pixel <= 1'b0;
            S_pc_plate_len_pixel   <= 4'd0;
            S_pc_plate_chars_pixel <= 88'd0;
            S_pc_rx_byte_count_sync1 <= 16'd0;
            S_pc_rx_byte_count_sync2 <= 16'd0;
            S_pc_frame_ok_count_sync1 <= 16'd0;
            S_pc_frame_ok_count_sync2 <= 16'd0;
            S_pc_frame_error_count_sync1 <= 16'd0;
            S_pc_frame_error_count_sync2 <= 16'd0;
        end else begin
            S_pc_update_sync <= {S_pc_update_sync[0], S_pc_uart_update_toggle};
            S_pc_rx_byte_count_sync1 <= S_pc_rx_byte_count_uart;
            S_pc_rx_byte_count_sync2 <= S_pc_rx_byte_count_sync1;
            S_pc_frame_ok_count_sync1 <= S_pc_frame_ok_count_uart;
            S_pc_frame_ok_count_sync2 <= S_pc_frame_ok_count_sync1;
            S_pc_frame_error_count_sync1 <= S_pc_frame_error_count_uart;
            S_pc_frame_error_count_sync2 <= S_pc_frame_error_count_sync1;
            if (S_pc_update_sync[1] != S_pc_update_seen) begin
                S_pc_update_seen       <= S_pc_update_sync[1];
                S_pc_plate_received_pixel <= 1'b1;
                S_pc_plate_valid_pixel <= S_pc_uart_valid;
                S_pc_plate_len_pixel   <= S_pc_uart_len;
                S_pc_plate_chars_pixel <= S_pc_uart_chars;
            end
        end
    end

    // PC image input: one 160x90 RGB565 frame at 115200 baud. The bridge stores
    // the image in dual-port RAM and repeats it as a 1280x720 stream.
    pc_image_uart_bridge #(
        .IMAGE_WIDTH    (160),
        .IMAGE_HEIGHT   (90),
        .DISPLAY_WIDTH  (1280),
        .DISPLAY_HEIGHT (720),
        .CLOCK_HZ       (100000000),
        .BAUD           (115200)
    ) u_pc_image_uart_bridge (
        .I_uart_clk     (I_uart_clk),
        .I_video_clk    (axi4s_video_aclk),
        .I_rst_n        (I_rst_n),
        .I_uart_rx      (I_uart_rx),
        // Keep the receiver/video replay logic armed on every UI page.  A
        // complete CRC-valid frame selects the image source above.
        .I_enable       (1'b1),
        .I_tready       (S_ui_tready),
        .O_tlast        (S_pc_image_tlast),
        .O_tuser        (S_pc_image_tuser),
        .O_tdata        (S_pc_image_tdata),
        .O_tvalid       (S_pc_image_tvalid),
        .O_active       (S_pc_image_active),
        .O_image_valid  (S_pc_image_valid),
        .O_rx_byte_count(S_pc_rx_byte_count_uart),
        .O_frame_ok_count(S_pc_frame_ok_count_uart),
        .O_frame_error_count(S_pc_frame_error_count_uart)
    );

    vision_external_ctrl_tx #(
        .CLOCK_HZ (100000000),
        .BAUD     (115200)
    ) u_vision_external_ctrl_tx (
        .I_clk         (I_uart_clk),
        .I_rst_n       (I_rst_n),
        .I_enable      (1'b0),
        .I_event_toggle(S_ctrl_event_toggle),
        .I_plate_valid (S_analysis_plate_valid),
        .I_track_valid (S_analysis_track_valid),
        .I_x           (S_analysis_plate_valid ? S_analysis_plate_x_min : S_analysis_track_x_min),
        .I_y           (S_analysis_plate_valid ? S_analysis_plate_y_min : S_analysis_track_y_min),
        .O_tx          (S_ctrl_uart_tx)
    );

    // No UART control feature is exposed in the submission UI.
    assign O_uart_tx = 1'b1;

    // Keep the example-style border, mode indicator, brightness bar and
    // "??" logo.  OSD control is also frame-latched above.
    my_osd #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720)
    ) u_my_osd (
        .I_clk      (axi4s_video_aclk),
        .I_rst_n    (I_rst_n),
        .I_tlast    (S_video_src_tlast),
        .I_tuser    (S_video_src_tuser),
        .I_tdata    (S_video_src_tdata),
        .I_tvalid   (S_video_src_tvalid),
        .I_tready   (S_ui_tready),
        .O_tlast    (S_osd_tlast),
        .O_tuser    (S_osd_tuser),
        .O_tdata    (S_osd_tdata),
        .O_tvalid   (S_osd_tvalid),
        .O_tready   (),
        .I_mode     (S_active_mode),
        .I_luma_avg (S_algo_luma),
        .I_osd_en   (S_active_osd_en),
        .I_pc_tx_en (1'b0)
    );

    vision_ui_osd #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720)
    ) u_vision_ui_osd (
        .I_clk           (axi4s_video_aclk),
        .I_rst_n         (I_rst_n),
        .I_tlast         (S_osd_tlast),
        .I_tuser         (S_osd_tuser),
        .I_tdata         (S_osd_tdata),
        .I_tvalid        (S_osd_tvalid),
        .I_tready        (O_tready),
        .O_tlast         (S_ui_tlast),
        .O_tuser         (S_ui_tuser),
        .O_tdata         (S_ui_tdata),
        .O_tvalid        (S_ui_tvalid),
        .O_tready        (S_ui_tready),
        .I_mode          (S_active_mode),
        .I_page          (S_active_page),
        .I_menu_index    (I_ui_menu_index),
        .I_in_menu       (I_ui_in_menu),
        .I_fps           (I_fps),
        .I_capture_frame (I_capture_frame),
        .I_display_frame (I_display_frame),
        .I_latency_frame (I_latency_frame),
        .I_switch        (S_active_switch),
        .I_osd_en        (S_active_osd_en),
        .I_plate_valid   (S_analysis_plate_valid),
        .I_plate_x_min   (S_analysis_plate_x_min),
        .I_plate_x_max   (S_analysis_plate_x_max),
        .I_plate_y_min   (S_analysis_plate_y_min),
        .I_plate_y_max   (S_analysis_plate_y_max),
        .I_plate_code0   (S_analysis_plate_code0),
        .I_plate_code1   (S_analysis_plate_code1),
        .I_plate_code2   (S_analysis_plate_code2),
        .I_plate_code3   (S_analysis_plate_code3),
        .I_plate_code4   (S_analysis_plate_code4),
        .I_plate_code5   (S_analysis_plate_code5),
        .I_pc_plate_received(S_pc_plate_received_pixel),
        .I_pc_plate_valid(S_pc_plate_valid_pixel),
        .I_pc_plate_len  (S_pc_plate_len_pixel),
        .I_pc_plate_chars(S_pc_plate_chars_pixel),
         .I_pc_image_valid(S_pc_image_valid),
         .I_pc_rx_byte_count(S_pc_rx_byte_count_sync2),
         .I_pc_frame_count(S_pc_frame_ok_count_sync2),
         .I_pc_error_count(S_pc_frame_error_count_sync2),
        .I_track_valid   (S_analysis_track_valid),
        .I_track_x_min   (S_analysis_track_x_min),
        .I_track_x_max   (S_analysis_track_x_max),
        .I_track_y_min   (S_analysis_track_y_min),
        .I_track_y_max   (S_analysis_track_y_max),
        .I_motion_active (S_analysis_motion_active),
        .I_motion_x_min  (S_analysis_motion_x_min),
        .I_motion_x_max  (S_analysis_motion_x_max),
        .I_motion_y_min  (S_analysis_motion_y_min),
        .I_motion_y_max  (S_analysis_motion_y_max)
    );

    // Four 96-bit beats (16 RGB pixels) are packed into three contiguous
    // 128-bit beats (48 RGB bytes).  The packer also aligns frame_start with
    // the first valid packed beat; video_in uses that marker to select the
    // next DDR frame buffer.
    data_96bit_to_128bit u_data_96bit_to_128bit (
        .I_clk              (axi4s_video_aclk),
        .I_rst_n            (I_rst_n),
        .I_96b_frame_start  (S_ui_tuser),
        .I_96b_valid        (S_ui_tvalid),
        .I_96b_data         (S_ui_tdata),
        .I_96b_tlast        (S_ui_tlast),
        .O_128b_frame_start (S_packed_tuser),
        .O_128b_valid       (S_packed_tvalid),
        .O_128b_data        (S_packed_tdata),
        .O_128b_tlast       (S_packed_tlast)
    );

    assign O_tdata  = S_packed_tdata;
    assign O_tlast  = S_packed_tlast;
    assign O_tuser  = S_packed_tuser;
    assign O_tvalid = S_packed_tvalid;

endmodule

/*
//------------------------------------------------------------------------------
// pc_image_uart_tx.v
//
// K2 ?????????????? 1280x720 ???? 8x8 ???
// 160x90 RGB565???? 100 MHz ???? UART ???????
//
// ?????2,000,000 baud?8 ????????1 ????8N1??
// ????
//   55 AA 5A A5 01 01
//   width[15:0] height[15:0] payload_len[15:0] frame_seq[31:0]
//   payload?160*90 ? RGB565 ?????????
//   crc16-ccitt??? payload ?????????
//   0D 0A
//
// ??????? UART ?????frame_ready_toggle / ack_toggle ??
// toggle ????? UART ????????????
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

    // One 160x90 RGB565 frame = 28,800 bytes.  Use the device's native
    // asynchronous dual-port embedded RAM explicitly.  A plain Verilog array
    // with unrelated clocks is not reliably inferred by TD and otherwise
    // expands into tens of thousands of LUTs/FFs during place.
    wire [15:0] frame_mem_dob;
    reg         frame_mem_we;
    reg  [13:0] frame_mem_waddr;
    reg  [15:0] frame_mem_wdata;
    // Declare before the RAM instance so TD does not create an implicit wire.
    reg  [13:0] tx_pixel_index;

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A       (16),
        .DATA_WIDTH_B       (16),
        .ADDR_WIDTH_A       (14),
        .ADDR_WIDTH_B       (14),
        .DATA_DEPTH_A       (IMAGE_PIXELS),
        .DATA_DEPTH_B       (IMAGE_PIXELS),
        .MODE               ("DP"),
        .REGMODE_A          ("NOREG"),
        .REGMODE_B          ("OUTREG"),
        .WRITEMODE_A        ("NORMAL"),
        .WRITEMODE_B        ("NORMAL"),
        .IMPLEMENT          ("20K(FAST)"),
        .ECC_ENCODE         ("DISABLE"),
        .ECC_DECODE         ("DISABLE"),
        .CLKMODE            ("ASYNC"),
        .SSROVERCE          ("DISABLE"),
        .OREGSET_A          ("RESET"),
        .OREGSET_B          ("RESET"),
        .RESETMODE_A        ("ASYNC"),
        .RESETMODE_B        ("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),
        .ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE          ("NONE"),
        .FILL_ALL           ("NONE")
    ) u_pc_frame_ram (
        .dia       (frame_mem_wdata),
        .dib       (16'd0),
        .addra     (frame_mem_waddr),
        .addrb     (tx_pixel_index),
        .cea       (1'b1),
        .ceb       (1'b1),
        .ocea      (1'b0),
        .oceb      (1'b1),
        .clka      (I_video_clk),
        .clkb      (I_uart_clk),
        .wea       (frame_mem_we),
        .web       (1'b0),
        .bea       (1'b0),
        .beb       (1'b0),
        .rsta      (1'b0),
        .rstb      (1'b0),
        .doa       (),
        .ecc_sbiterr(),
        .ecc_dbiterr(),
        .ecc_sbiterrinj('d0),
        .ecc_dbiterrinj('d0),
        .dob       (frame_mem_dob)
    );

    // The RAM's registered B output is the pixel consumed by the scheduler.
    wire [15:0] tx_pixel_data = frame_mem_dob;

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
            frame_mem_we    <= 1'b0;
            frame_mem_waddr <= 14'd0;
            frame_mem_wdata <= 16'd0;
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
            frame_mem_we    <= 1'b0;
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
                        frame_mem_we    <= 1'b1;
                        frame_mem_waddr <= 14'd0;
                        frame_mem_wdata <= rgb565_from_rgb888(
                            I_tdata[95:88], I_tdata[87:80], I_tdata[79:72]);
                    end else begin
                        capture_active <= 1'b0;
                    end
                end else if (capture_active) begin
                    // Select y=0,8,16,... and x=0,8,16,... .
                    if (src_y[2:0] == 3'b000 && src_x[2:0] == 3'b000) begin
                        if (capture_index < IMAGE_PIXELS) begin
                            frame_mem_we    <= 1'b1;
                            frame_mem_waddr <= capture_index;
                            frame_mem_wdata <= rgb565_from_rgb888(
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
*/


