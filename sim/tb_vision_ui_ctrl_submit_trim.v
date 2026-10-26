`timescale 1ns/1ps

module tb_vision_ui_ctrl_submit_trim;
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

    reg [3:0] expected_page [0:5];
    integer i;

    always #5 clk = ~clk;

    vision_ui_ctrl dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_key_up(key_up), .I_key_down(key_down),
        .I_key_enter(key_enter), .I_key_back(key_back),
        .O_mode(mode), .O_page(page), .O_menu_index(menu_index),
        .O_in_menu(in_menu), .O_osd_en(osd_en)
    );

    task pulse_key;
        input [3:0] key_bits;
        begin
            @(negedge clk);
            {key_up, key_down, key_enter, key_back} = key_bits;
            @(negedge clk);
            {key_up, key_down, key_enter, key_back} = 4'b0000;
            @(negedge clk);
        end
    endtask

    initial begin
        expected_page[0] = 4'd0;
        expected_page[1] = 4'd2;
        expected_page[2] = 4'd3;
        expected_page[3] = 4'd4;
        expected_page[4] = 4'd6;
        expected_page[5] = 4'd7;

        #20 rst_n = 1'b1;
        @(negedge clk);
        if (!in_menu || menu_index != 4'd0 || !osd_en)
            $fatal(1, "reset state mismatch");

        pulse_key(4'b1000);
        if (menu_index != 4'd5)
            $fatal(1, "K1 did not wrap from first to last item");
        pulse_key(4'b0100);
        if (menu_index != 4'd0)
            $fatal(1, "K2 did not wrap from last to first item");

        for (i = 0; i < 6; i = i + 1) begin
            if (menu_index != i[3:0])
                $fatal(1, "unexpected menu index before enter: %0d", menu_index);
            pulse_key(4'b0010);
            if (in_menu || page != expected_page[i])
                $fatal(1, "menu item %0d opened page %0d, expected %0d",
                       i, page, expected_page[i]);
            if (i == 0) begin
                pulse_key(4'b0100);
                if (mode != 2'd1)
                    $fatal(1, "K2 did not switch image mode inside page 0");
                pulse_key(4'b1000);
                if (mode != 2'd0)
                    $fatal(1, "K1 did not restore image mode inside page 0");
            end
            pulse_key(4'b0001);
            if (!in_menu)
                $fatal(1, "K4 did not return to menu");
            pulse_key(4'b0100);
        end

        if (menu_index != 4'd0)
            $fatal(1, "six-item menu did not wrap after last item");

        $display("PASS: six menu entries, page mapping, wraparound, and model keys");
        $finish;
    end
endmodule
