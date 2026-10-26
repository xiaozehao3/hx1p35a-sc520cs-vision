`timescale 1ns/1ps
module tb_vision_ui_ctrl_pc_image;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg key_up = 1'b0;
    reg key_down = 1'b0;
    reg key_enter = 1'b0;
    reg key_back = 1'b0;
    wire [1:0] mode;
    wire [3:0] page;
    wire [3:0] menu_index;
    wire in_menu;
    wire osd_en;

    always #5 clk = ~clk;

    vision_ui_ctrl dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_key_up(key_up), .I_key_down(key_down),
        .I_key_enter(key_enter), .I_key_back(key_back),
        .O_mode(mode), .O_page(page), .O_menu_index(menu_index),
        .O_in_menu(in_menu), .O_osd_en(osd_en)
    );

    task pulse_down;
        begin
            @(negedge clk); key_down = 1'b1;
            @(negedge clk); key_down = 1'b0;
        end
    endtask

    task pulse_up;
        begin
            @(negedge clk); key_up = 1'b1;
            @(negedge clk); key_up = 1'b0;
        end
    endtask

    task pulse_enter;
        begin
            @(negedge clk); key_enter = 1'b1;
            @(negedge clk); key_enter = 1'b0;
        end
    endtask

    task pulse_back;
        begin
            @(negedge clk); key_back = 1'b1;
            @(negedge clk); key_back = 1'b0;
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        for (i = 0; i < 6; i = i + 1)
            pulse_down();
        if (menu_index !== 4'd6 || !in_menu) begin
            $display("FAIL: seventh menu item was not reachable");
            $fatal(1);
        end

        pulse_enter();
        if (page !== 4'd5 || in_menu) begin
            $display("FAIL: seventh menu item did not select the PC image page");
            $fatal(1);
        end

        pulse_back();
        pulse_up();
        pulse_enter();
        if (page !== 4'd7 || in_menu) begin
            $display("FAIL: pseudo-color menu mapping changed while adding the PC image page");
            $fatal(1);
        end

        $display("PASS: K1/K2 menu navigation selects PC IMAGE and retains pseudo-color mapping");
        $finish;
    end
endmodule
