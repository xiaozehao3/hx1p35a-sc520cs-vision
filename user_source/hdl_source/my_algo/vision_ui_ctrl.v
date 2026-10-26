// Four-key UI controller for the local HDMI vision interface.
// K1/K2 navigate; K3 enters a page; K4 returns to the main menu.
// Seven selectable entries expose the implemented board demonstrations,
// including the PC still-image UART input page.
module vision_ui_ctrl (
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire       I_key_up,
    input  wire       I_key_down,
    input  wire       I_key_enter,
    input  wire       I_key_back,
    output reg  [1:0] O_mode,
    output reg  [3:0] O_page,
    output reg  [3:0] O_menu_index,
    output reg        O_in_menu,
    output reg        O_osd_en
);

    localparam [3:0] MENU_LAST = 4'd6;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode      <= 2'd0;
            O_page      <= 4'd0;
            O_menu_index<= 4'd0;
            O_in_menu   <= 1'b1;
            O_osd_en    <= 1'b1;
        end else begin
            O_osd_en   <= 1'b1;

            if (O_in_menu) begin
                if (I_key_up) begin
                    if (O_menu_index == 4'd0)
                        O_menu_index <= MENU_LAST;
                    else
                        O_menu_index <= O_menu_index - 4'd1;
                end else if (I_key_down) begin
                    if (O_menu_index == MENU_LAST)
                        O_menu_index <= 4'd0;
                    else
                        O_menu_index <= O_menu_index + 4'd1;
                end

                if (I_key_enter) begin
                    case (O_menu_index)
                        4'd0: O_page <= 4'd0; // image modes and style/fill
                        4'd1: O_page <= 4'd2; // color-target tracking
                        4'd2: O_page <= 4'd3; // frame-difference motion
                        4'd3: O_page <= 4'd4; // image-quality compensation
                        4'd4: O_page <= 4'd6; // live performance counters
                        4'd5: O_page <= 4'd7; // pseudo-color creative mode
                        default: O_page <= 4'd5; // PC still image over UART
                    endcase
                    O_in_menu <= 1'b0;
                end
            end else begin
                if (I_key_back) begin
                    O_in_menu <= 1'b1;
                end else if (O_page == 4'd0) begin
                    // Algorithm selection is only active inside the image-mode page.
                    if (I_key_up) begin
                        if (O_mode == 2'd0)
                            O_mode <= 2'd3;
                        else
                            O_mode <= O_mode - 2'd1;
                    end else if (I_key_down) begin
                        if (O_mode == 2'd3)
                            O_mode <= 2'd0;
                        else
                            O_mode <= O_mode + 2'd1;
                    end
                end
            end
        end
    end

endmodule
