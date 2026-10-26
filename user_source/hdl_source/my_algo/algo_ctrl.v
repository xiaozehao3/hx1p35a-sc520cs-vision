//===========================================================================
//  algo_ctrl.v  ——  按键控制：K1 切换算法，K2 开关上位机图传模式
//
//  I_mode_trig / I_pc_tx_trig 为消抖后的单拍脉冲（按键低有效）。
//  模式编码与屏幕显示保持一致：
//      2'd0 = Model1：彩色
//      2'd1 = Model2：二值化
//      2'd2 = Model3：边缘检测
//      2'd3 = Model4：灰度
//===========================================================================
module algo_ctrl(
    input               I_clk,
    input               I_rst_n,
    input               I_mode_trig,
    input               I_pc_tx_trig,
    output reg [1:0]    O_mode,
    output reg          O_pc_tx_en,
    output reg          O_osd_en
);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode     <= 2'd0;
            O_pc_tx_en <= 1'b0;
            O_osd_en   <= 1'b1;
        end else begin
            if (I_mode_trig) begin
                if (O_mode == 2'd3)
                    O_mode <= 2'd0;
                else
                    O_mode <= O_mode + 2'd1;
            end
            if (I_pc_tx_trig)
                O_pc_tx_en <= ~O_pc_tx_en;
        end
    end
endmodule
