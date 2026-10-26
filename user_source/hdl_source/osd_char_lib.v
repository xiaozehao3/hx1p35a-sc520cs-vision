// 16x16 OSD font. Private Chinese codes are 0x80..0xA0.
module osd_char_lib (
    input wire [7:0] I_char,
    input wire [3:0] I_row,
    output reg [15:0] O_row_bits
);

    function [15:0] glyph_row;
        input [7:0] c;
        input [3:0] r;
        begin
            glyph_row = 16'h0000;
            case (c)
                8'h80: begin
                    case (r)
                        4'd0: glyph_row = 16'h0180;
                        4'd1: glyph_row = 16'h00C0;
                        4'd2: glyph_row = 16'h7FFE;
                        4'd3: glyph_row = 16'h4002;
                        4'd4: glyph_row = 16'h4102;
                        4'd5: glyph_row = 16'h0200;
                        4'd6: glyph_row = 16'h0200;
                        4'd7: glyph_row = 16'hFFFF;
                        4'd8: glyph_row = 16'h0C10;
                        4'd9: glyph_row = 16'h1830;
                        4'd10: glyph_row = 16'h0C20;
                        4'd11: glyph_row = 16'h03C0;
                        4'd12: glyph_row = 16'h03E0;
                        4'd13: glyph_row = 16'h0E18;
                        4'd14: glyph_row = 16'h7006;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h81: begin
                    case (r)
                        4'd0: glyph_row = 16'h0020;
                        4'd1: glyph_row = 16'h7C40;
                        4'd2: glyph_row = 16'h44FE;
                        4'd3: glyph_row = 16'h4586;
                        4'd4: glyph_row = 16'h474C;
                        4'd5: glyph_row = 16'h7C78;
                        4'd6: glyph_row = 16'h5030;
                        4'd7: glyph_row = 16'h10CC;
                        4'd8: glyph_row = 16'h5F03;
                        4'd9: glyph_row = 16'h50FE;
                        4'd10: glyph_row = 16'h5082;
                        4'd11: glyph_row = 16'h5082;
                        4'd12: glyph_row = 16'h5E82;
                        4'd13: glyph_row = 16'hE0FE;
                        4'd14: glyph_row = 16'h0082;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h82: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0782;
                        4'd2: glyph_row = 16'h7804;
                        4'd3: glyph_row = 16'h0888;
                        4'd4: glyph_row = 16'h4530;
                        4'd5: glyph_row = 16'h2561;
                        4'd6: glyph_row = 16'h2202;
                        4'd7: glyph_row = 16'h0804;
                        4'd8: glyph_row = 16'h7F98;
                        4'd9: glyph_row = 16'h1831;
                        4'd10: glyph_row = 16'h1E02;
                        4'd11: glyph_row = 16'h2B04;
                        4'd12: glyph_row = 16'h4898;
                        4'd13: glyph_row = 16'h8870;
                        4'd14: glyph_row = 16'h08C0;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h83: begin
                    case (r)
                        4'd0: glyph_row = 16'h0400;
                        4'd1: glyph_row = 16'h0C00;
                        4'd2: glyph_row = 16'h1FE0;
                        4'd3: glyph_row = 16'h3060;
                        4'd4: glyph_row = 16'h60C0;
                        4'd5: glyph_row = 16'hFFF8;
                        4'd6: glyph_row = 16'h2108;
                        4'd7: glyph_row = 16'h2108;
                        4'd8: glyph_row = 16'h2108;
                        4'd9: glyph_row = 16'h3FF8;
                        4'd10: glyph_row = 16'h2008;
                        4'd11: glyph_row = 16'h2000;
                        4'd12: glyph_row = 16'h2002;
                        4'd13: glyph_row = 16'h2002;
                        4'd14: glyph_row = 16'h1FFC;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h84: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h7FFC;
                        4'd3: glyph_row = 16'h0000;
                        4'd4: glyph_row = 16'h0000;
                        4'd5: glyph_row = 16'h0000;
                        4'd6: glyph_row = 16'h0000;
                        4'd7: glyph_row = 16'h0000;
                        4'd8: glyph_row = 16'h0000;
                        4'd9: glyph_row = 16'h0000;
                        4'd10: glyph_row = 16'h0000;
                        4'd11: glyph_row = 16'h0000;
                        4'd12: glyph_row = 16'hFFFE;
                        4'd13: glyph_row = 16'h0000;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h85: begin
                    case (r)
                        4'd0: glyph_row = 16'h1040;
                        4'd1: glyph_row = 16'h1040;
                        4'd2: glyph_row = 16'h2FFE;
                        4'd3: glyph_row = 16'h2040;
                        4'd4: glyph_row = 16'h2040;
                        4'd5: glyph_row = 16'h63FC;
                        4'd6: glyph_row = 16'h6204;
                        4'd7: glyph_row = 16'hA3FC;
                        4'd8: glyph_row = 16'hA204;
                        4'd9: glyph_row = 16'h23FC;
                        4'd10: glyph_row = 16'h2204;
                        4'd11: glyph_row = 16'h23FC;
                        4'd12: glyph_row = 16'h2204;
                        4'd13: glyph_row = 16'h2FFE;
                        4'd14: glyph_row = 16'h2000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h86: begin
                    case (r)
                        4'd0: glyph_row = 16'h0480;
                        4'd1: glyph_row = 16'h0880;
                        4'd2: glyph_row = 16'h0882;
                        4'd3: glyph_row = 16'h1084;
                        4'd4: glyph_row = 16'h108C;
                        4'd5: glyph_row = 16'h10B0;
                        4'd6: glyph_row = 16'h30E0;
                        4'd7: glyph_row = 16'h50C0;
                        4'd8: glyph_row = 16'h5180;
                        4'd9: glyph_row = 16'h1380;
                        4'd10: glyph_row = 16'h1682;
                        4'd11: glyph_row = 16'h1082;
                        4'd12: glyph_row = 16'h1082;
                        4'd13: glyph_row = 16'h10FC;
                        4'd14: glyph_row = 16'h1000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h87: begin
                    case (r)
                        4'd0: glyph_row = 16'h4080;
                        4'd1: glyph_row = 16'h2080;
                        4'd2: glyph_row = 16'h2080;
                        4'd3: glyph_row = 16'h17FC;
                        4'd4: glyph_row = 16'h0084;
                        4'd5: glyph_row = 16'h0084;
                        4'd6: glyph_row = 16'hE084;
                        4'd7: glyph_row = 16'h2104;
                        4'd8: glyph_row = 16'h2104;
                        4'd9: glyph_row = 16'h2304;
                        4'd10: glyph_row = 16'h2604;
                        4'd11: glyph_row = 16'h2C78;
                        4'd12: glyph_row = 16'h6000;
                        4'd13: glyph_row = 16'hD800;
                        4'd14: glyph_row = 16'h8FFF;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h88: begin
                    case (r)
                        4'd0: glyph_row = 16'h1100;
                        4'd1: glyph_row = 16'h21F8;
                        4'd2: glyph_row = 16'h2108;
                        4'd3: glyph_row = 16'h45F8;
                        4'd4: glyph_row = 16'h8808;
                        4'd5: glyph_row = 16'hF7FE;
                        4'd6: glyph_row = 16'h30C0;
                        4'd7: glyph_row = 16'h6144;
                        4'd8: glyph_row = 16'hC6D8;
                        4'd9: glyph_row = 16'hF1A8;
                        4'd10: glyph_row = 16'h0668;
                        4'd11: glyph_row = 16'h0CAC;
                        4'd12: glyph_row = 16'h3324;
                        4'd13: glyph_row = 16'hC622;
                        4'd14: glyph_row = 16'h01C0;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h89: begin
                    case (r)
                        4'd0: glyph_row = 16'h1020;
                        4'd1: glyph_row = 16'h1070;
                        4'd2: glyph_row = 16'h1048;
                        4'd3: glyph_row = 16'h7E8C;
                        4'd4: glyph_row = 16'h1106;
                        4'd5: glyph_row = 16'h1203;
                        4'd6: glyph_row = 16'h39F8;
                        4'd7: glyph_row = 16'h3400;
                        4'd8: glyph_row = 16'h5244;
                        4'd9: glyph_row = 16'h5248;
                        4'd10: glyph_row = 16'h5128;
                        4'd11: glyph_row = 16'h1128;
                        4'd12: glyph_row = 16'h1010;
                        4'd13: glyph_row = 16'h17FE;
                        4'd14: glyph_row = 16'h1000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h8A: begin
                    case (r)
                        4'd0: glyph_row = 16'h4002;
                        4'd1: glyph_row = 16'h27CA;
                        4'd2: glyph_row = 16'h144A;
                        4'd3: glyph_row = 16'h054A;
                        4'd4: glyph_row = 16'h454A;
                        4'd5: glyph_row = 16'h254A;
                        4'd6: glyph_row = 16'h154A;
                        4'd7: glyph_row = 16'h054A;
                        4'd8: glyph_row = 16'h054A;
                        4'd9: glyph_row = 16'h154A;
                        4'd10: glyph_row = 16'h110A;
                        4'd11: glyph_row = 16'h2302;
                        4'd12: glyph_row = 16'h2682;
                        4'd13: glyph_row = 16'h4C42;
                        4'd14: glyph_row = 16'h582E;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h8B: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0800;
                        4'd2: glyph_row = 16'h0800;
                        4'd3: glyph_row = 16'h7FFF;
                        4'd4: glyph_row = 16'h0800;
                        4'd5: glyph_row = 16'h0840;
                        4'd6: glyph_row = 16'h1C42;
                        4'd7: glyph_row = 16'h1244;
                        4'd8: glyph_row = 16'h1244;
                        4'd9: glyph_row = 16'h3168;
                        4'd10: glyph_row = 16'h20A0;
                        4'd11: glyph_row = 16'h6090;
                        4'd12: glyph_row = 16'h4118;
                        4'd13: glyph_row = 16'h860C;
                        4'd14: glyph_row = 16'h1803;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h8C: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0080;
                        4'd2: glyph_row = 16'h0040;
                        4'd3: glyph_row = 16'h3FFF;
                        4'd4: glyph_row = 16'h2000;
                        4'd5: glyph_row = 16'h2208;
                        4'd6: glyph_row = 16'h3FFF;
                        4'd7: glyph_row = 16'h2208;
                        4'd8: glyph_row = 16'h23F8;
                        4'd9: glyph_row = 16'h2000;
                        4'd10: glyph_row = 16'h2FFC;
                        4'd11: glyph_row = 16'h2418;
                        4'd12: glyph_row = 16'h43E0;
                        4'd13: glyph_row = 16'h43F0;
                        4'd14: glyph_row = 16'h9C0F;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h8D: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h7FFE;
                        4'd2: glyph_row = 16'h4202;
                        4'd3: glyph_row = 16'h47F2;
                        4'd4: glyph_row = 16'h4C22;
                        4'd5: glyph_row = 16'h5242;
                        4'd6: glyph_row = 16'h4182;
                        4'd7: glyph_row = 16'h46F2;
                        4'd8: glyph_row = 16'h781E;
                        4'd9: glyph_row = 16'h47C2;
                        4'd10: glyph_row = 16'h4062;
                        4'd11: glyph_row = 16'h4F02;
                        4'd12: glyph_row = 16'h40F2;
                        4'd13: glyph_row = 16'h7FFE;
                        4'd14: glyph_row = 16'h4002;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h8E: begin
                    case (r)
                        4'd0: glyph_row = 16'h1040;
                        4'd1: glyph_row = 16'h1040;
                        4'd2: glyph_row = 16'h27FE;
                        4'd3: glyph_row = 16'h2080;
                        4'd4: glyph_row = 16'h2100;
                        4'd5: glyph_row = 16'h6FFF;
                        4'd6: glyph_row = 16'h6100;
                        4'd7: glyph_row = 16'hA200;
                        4'd8: glyph_row = 16'hA3FE;
                        4'd9: glyph_row = 16'h2004;
                        4'd10: glyph_row = 16'h2608;
                        4'd11: glyph_row = 16'h2310;
                        4'd12: glyph_row = 16'h20E0;
                        4'd13: glyph_row = 16'h2030;
                        4'd14: glyph_row = 16'h2018;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h8F: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h7FFC;
                        4'd2: glyph_row = 16'h0820;
                        4'd3: glyph_row = 16'h0820;
                        4'd4: glyph_row = 16'h0820;
                        4'd5: glyph_row = 16'h0820;
                        4'd6: glyph_row = 16'h0820;
                        4'd7: glyph_row = 16'hFFFE;
                        4'd8: glyph_row = 16'h0820;
                        4'd9: glyph_row = 16'h0820;
                        4'd10: glyph_row = 16'h0820;
                        4'd11: glyph_row = 16'h1020;
                        4'd12: glyph_row = 16'h1020;
                        4'd13: glyph_row = 16'h6020;
                        4'd14: glyph_row = 16'hC020;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h90: begin
                    case (r)
                        4'd0: glyph_row = 16'h1008;
                        4'd1: glyph_row = 16'h0C10;
                        4'd2: glyph_row = 16'h0420;
                        4'd3: glyph_row = 16'h7FFE;
                        4'd4: glyph_row = 16'h0080;
                        4'd5: glyph_row = 16'h0080;
                        4'd6: glyph_row = 16'h0080;
                        4'd7: glyph_row = 16'hFFFF;
                        4'd8: glyph_row = 16'h0180;
                        4'd9: glyph_row = 16'h0380;
                        4'd10: glyph_row = 16'h0240;
                        4'd11: glyph_row = 16'h0420;
                        4'd12: glyph_row = 16'h1810;
                        4'd13: glyph_row = 16'h300C;
                        4'd14: glyph_row = 16'hC003;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h91: begin
                    case (r)
                        4'd0: glyph_row = 16'h0100;
                        4'd1: glyph_row = 16'h0100;
                        4'd2: glyph_row = 16'h3FF8;
                        4'd3: glyph_row = 16'h2108;
                        4'd4: glyph_row = 16'h2108;
                        4'd5: glyph_row = 16'h3FF8;
                        4'd6: glyph_row = 16'h2108;
                        4'd7: glyph_row = 16'h0100;
                        4'd8: glyph_row = 16'h7FFC;
                        4'd9: glyph_row = 16'h4104;
                        4'd10: glyph_row = 16'h4104;
                        4'd11: glyph_row = 16'h7FFC;
                        4'd12: glyph_row = 16'h4104;
                        4'd13: glyph_row = 16'h0100;
                        4'd14: glyph_row = 16'h0100;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h92: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h3FFC;
                        4'd2: glyph_row = 16'h2004;
                        4'd3: glyph_row = 16'h2004;
                        4'd4: glyph_row = 16'h2004;
                        4'd5: glyph_row = 16'h2004;
                        4'd6: glyph_row = 16'h2004;
                        4'd7: glyph_row = 16'h2004;
                        4'd8: glyph_row = 16'h2004;
                        4'd9: glyph_row = 16'h2004;
                        4'd10: glyph_row = 16'h2004;
                        4'd11: glyph_row = 16'h2004;
                        4'd12: glyph_row = 16'h3FFC;
                        4'd13: glyph_row = 16'h2004;
                        4'd14: glyph_row = 16'h2004;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h93: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0880;
                        4'd2: glyph_row = 16'h0980;
                        4'd3: glyph_row = 16'h4900;
                        4'd4: glyph_row = 16'h49FE;
                        4'd5: glyph_row = 16'h4B08;
                        4'd6: glyph_row = 16'h4F08;
                        4'd7: glyph_row = 16'h4D08;
                        4'd8: glyph_row = 16'h4990;
                        4'd9: glyph_row = 16'h4890;
                        4'd10: glyph_row = 16'h58F0;
                        4'd11: glyph_row = 16'h6860;
                        4'd12: glyph_row = 16'h48E0;
                        4'd13: glyph_row = 16'h0998;
                        4'd14: glyph_row = 16'h0E06;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h94: begin
                    case (r)
                        4'd0: glyph_row = 16'h2130;
                        4'd1: glyph_row = 16'h2118;
                        4'd2: glyph_row = 16'h420C;
                        4'd3: glyph_row = 16'h7FFF;
                        4'd4: glyph_row = 16'h0200;
                        4'd5: glyph_row = 16'h0400;
                        4'd6: glyph_row = 16'h07FC;
                        4'd7: glyph_row = 16'h0604;
                        4'd8: glyph_row = 16'h0A08;
                        4'd9: glyph_row = 16'h1908;
                        4'd10: glyph_row = 16'h1090;
                        4'd11: glyph_row = 16'h2060;
                        4'd12: glyph_row = 16'h40E0;
                        4'd13: glyph_row = 16'h8718;
                        4'd14: glyph_row = 16'h1807;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h95: begin
                    case (r)
                        4'd0: glyph_row = 16'h0820;
                        4'd1: glyph_row = 16'h1020;
                        4'd2: glyph_row = 16'h23FC;
                        4'd3: glyph_row = 16'h4020;
                        4'd4: glyph_row = 16'h8820;
                        4'd5: glyph_row = 16'h1FFE;
                        4'd6: glyph_row = 16'h1000;
                        4'd7: glyph_row = 16'h3008;
                        4'd8: glyph_row = 16'h77FE;
                        4'd9: glyph_row = 16'h5008;
                        4'd10: glyph_row = 16'h1208;
                        4'd11: glyph_row = 16'h1108;
                        4'd12: glyph_row = 16'h1088;
                        4'd13: glyph_row = 16'h1008;
                        4'd14: glyph_row = 16'h1078;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h96: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h1000;
                        4'd2: glyph_row = 16'h11F8;
                        4'd3: glyph_row = 16'h1108;
                        4'd4: glyph_row = 16'hFD08;
                        4'd5: glyph_row = 16'h1108;
                        4'd6: glyph_row = 16'h3108;
                        4'd7: glyph_row = 16'h3908;
                        4'd8: glyph_row = 16'h3508;
                        4'd9: glyph_row = 16'h5108;
                        4'd10: glyph_row = 16'hD108;
                        4'd11: glyph_row = 16'h9109;
                        4'd12: glyph_row = 16'h1209;
                        4'd13: glyph_row = 16'h1209;
                        4'd14: glyph_row = 16'h140E;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h97: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h24FE;
                        4'd2: glyph_row = 16'h2492;
                        4'd3: glyph_row = 16'h7E92;
                        4'd4: glyph_row = 16'h2492;
                        4'd5: glyph_row = 16'h3C92;
                        4'd6: glyph_row = 16'h0892;
                        4'd7: glyph_row = 16'h7E92;
                        4'd8: glyph_row = 16'h4AFE;
                        4'd9: glyph_row = 16'h4A82;
                        4'd10: glyph_row = 16'h7E80;
                        4'd11: glyph_row = 16'h0881;
                        4'd12: glyph_row = 16'h7F81;
                        4'd13: glyph_row = 16'h0883;
                        4'd14: glyph_row = 16'h087E;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h98: begin
                    case (r)
                        4'd0: glyph_row = 16'h1000;
                        4'd1: glyph_row = 16'h11FE;
                        4'd2: glyph_row = 16'h1000;
                        4'd3: glyph_row = 16'h7C00;
                        4'd4: glyph_row = 16'h11FF;
                        4'd5: glyph_row = 16'h1020;
                        4'd6: glyph_row = 16'h3C20;
                        4'd7: glyph_row = 16'h36A4;
                        4'd8: glyph_row = 16'h5126;
                        4'd9: glyph_row = 16'h5122;
                        4'd10: glyph_row = 16'h1222;
                        4'd11: glyph_row = 16'h1223;
                        4'd12: glyph_row = 16'h1421;
                        4'd13: glyph_row = 16'h11E0;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h99: begin
                    case (r)
                        4'd0: glyph_row = 16'h0200;
                        4'd1: glyph_row = 16'h0400;
                        4'd2: glyph_row = 16'h7FFC;
                        4'd3: glyph_row = 16'h0800;
                        4'd4: glyph_row = 16'h1880;
                        4'd5: glyph_row = 16'h1080;
                        4'd6: glyph_row = 16'h3080;
                        4'd7: glyph_row = 16'h3FF8;
                        4'd8: glyph_row = 16'h0080;
                        4'd9: glyph_row = 16'h0080;
                        4'd10: glyph_row = 16'h0080;
                        4'd11: glyph_row = 16'hFFFE;
                        4'd12: glyph_row = 16'h0080;
                        4'd13: glyph_row = 16'h0080;
                        4'd14: glyph_row = 16'h0080;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h9A: begin
                    case (r)
                        4'd0: glyph_row = 16'h0810;
                        4'd1: glyph_row = 16'h4820;
                        4'd2: glyph_row = 16'h49FE;
                        4'd3: glyph_row = 16'h4912;
                        4'd4: glyph_row = 16'h4912;
                        4'd5: glyph_row = 16'h7DFE;
                        4'd6: glyph_row = 16'h4112;
                        4'd7: glyph_row = 16'h4112;
                        4'd8: glyph_row = 16'h79FE;
                        4'd9: glyph_row = 16'h4862;
                        4'd10: glyph_row = 16'h4990;
                        4'd11: glyph_row = 16'h4BFF;
                        4'd12: glyph_row = 16'h4810;
                        4'd13: glyph_row = 16'h8810;
                        4'd14: glyph_row = 16'h8810;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h9B: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h3FFE;
                        4'd2: glyph_row = 16'h0000;
                        4'd3: glyph_row = 16'h0000;
                        4'd4: glyph_row = 16'h0000;
                        4'd5: glyph_row = 16'h0000;
                        4'd6: glyph_row = 16'h7FFF;
                        4'd7: glyph_row = 16'h0300;
                        4'd8: glyph_row = 16'h0600;
                        4'd9: glyph_row = 16'h0620;
                        4'd10: glyph_row = 16'h0C10;
                        4'd11: glyph_row = 16'h0818;
                        4'd12: glyph_row = 16'h100C;
                        4'd13: glyph_row = 16'h3FFE;
                        4'd14: glyph_row = 16'h0002;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h9C: begin
                    case (r)
                        4'd0: glyph_row = 16'h0100;
                        4'd1: glyph_row = 16'h0200;
                        4'd2: glyph_row = 16'h0410;
                        4'd3: glyph_row = 16'h0808;
                        4'd4: glyph_row = 16'h3004;
                        4'd5: glyph_row = 16'h60FE;
                        4'd6: glyph_row = 16'hFF03;
                        4'd7: glyph_row = 16'h0001;
                        4'd8: glyph_row = 16'h0000;
                        4'd9: glyph_row = 16'h3FFC;
                        4'd10: glyph_row = 16'h2004;
                        4'd11: glyph_row = 16'h2004;
                        4'd12: glyph_row = 16'h2004;
                        4'd13: glyph_row = 16'h3FFC;
                        4'd14: glyph_row = 16'h2004;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h9D: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'hC208;
                        4'd2: glyph_row = 16'h6F88;
                        4'd3: glyph_row = 16'h389F;
                        4'd4: glyph_row = 16'h0F92;
                        4'd5: glyph_row = 16'hC8B2;
                        4'd6: glyph_row = 16'h6FB2;
                        4'd7: glyph_row = 16'h0252;
                        4'd8: glyph_row = 16'h020C;
                        4'd9: glyph_row = 16'h1FCC;
                        4'd10: glyph_row = 16'h440C;
                        4'd11: glyph_row = 16'h478C;
                        4'd12: glyph_row = 16'h4494;
                        4'd13: glyph_row = 16'h88B2;
                        4'd14: glyph_row = 16'h93C1;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h9E: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0080;
                        4'd2: glyph_row = 16'h2082;
                        4'd3: glyph_row = 16'h1084;
                        4'd4: glyph_row = 16'h0888;
                        4'd5: glyph_row = 16'h0490;
                        4'd6: glyph_row = 16'h0080;
                        4'd7: glyph_row = 16'h7FFF;
                        4'd8: glyph_row = 16'h0420;
                        4'd9: glyph_row = 16'h0420;
                        4'd10: glyph_row = 16'h0420;
                        4'd11: glyph_row = 16'h0821;
                        4'd12: glyph_row = 16'h0821;
                        4'd13: glyph_row = 16'h3021;
                        4'd14: glyph_row = 16'h603E;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h9F: begin
                    case (r)
                        4'd0: glyph_row = 16'h2221;
                        4'd1: glyph_row = 16'h6122;
                        4'd2: glyph_row = 16'h7CA4;
                        4'd3: glyph_row = 16'hC020;
                        4'd4: glyph_row = 16'h83FF;
                        4'd5: glyph_row = 16'h7A01;
                        4'd6: glyph_row = 16'h2221;
                        4'd7: glyph_row = 16'h2221;
                        4'd8: glyph_row = 16'hFA21;
                        4'd9: glyph_row = 16'h2221;
                        4'd10: glyph_row = 16'h2221;
                        4'd11: glyph_row = 16'h2070;
                        4'd12: glyph_row = 16'h28CC;
                        4'd13: glyph_row = 16'h3386;
                        4'd14: glyph_row = 16'h2C01;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'hA0: begin
                    case (r)
                        4'd0: glyph_row = 16'h0100;
                        4'd1: glyph_row = 16'h0180;
                        4'd2: glyph_row = 16'h7FFE;
                        4'd3: glyph_row = 16'h4002;
                        4'd4: glyph_row = 16'h0000;
                        4'd5: glyph_row = 16'hFFFF;
                        4'd6: glyph_row = 16'h0080;
                        4'd7: glyph_row = 16'h1080;
                        4'd8: glyph_row = 16'h1080;
                        4'd9: glyph_row = 16'h10FE;
                        4'd10: glyph_row = 16'h3080;
                        4'd11: glyph_row = 16'h3880;
                        4'd12: glyph_row = 16'h6C80;
                        4'd13: glyph_row = 16'h43FF;
                        4'd14: glyph_row = 16'h8000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'hA1: begin
                    case (r)
                        4'd0: glyph_row = 16'h2000;
                        4'd1: glyph_row = 16'h13FE;
                        4'd2: glyph_row = 16'h0802;
                        4'd3: glyph_row = 16'h4042;
                        4'd4: glyph_row = 16'h4042;
                        4'd5: glyph_row = 16'h4FFA;
                        4'd6: glyph_row = 16'h40C2;
                        4'd7: glyph_row = 16'h40C2;
                        4'd8: glyph_row = 16'h4142;
                        4'd9: glyph_row = 16'h4242;
                        4'd10: glyph_row = 16'h4442;
                        4'd11: glyph_row = 16'h4842;
                        4'd12: glyph_row = 16'h5042;
                        4'd13: glyph_row = 16'h43C2;
                        4'd14: glyph_row = 16'h403E;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h4D: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h3004;
                        4'd3: glyph_row = 16'h380C;
                        4'd4: glyph_row = 16'h380C;
                        4'd5: glyph_row = 16'h2C14;
                        4'd6: glyph_row = 16'h2C14;
                        4'd7: glyph_row = 16'h2624;
                        4'd8: glyph_row = 16'h2624;
                        4'd9: glyph_row = 16'h2224;
                        4'd10: glyph_row = 16'h2344;
                        4'd11: glyph_row = 16'h2144;
                        4'd12: glyph_row = 16'h21C4;
                        4'd13: glyph_row = 16'h2084;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h6F: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h0000;
                        4'd3: glyph_row = 16'h03E0;
                        4'd4: glyph_row = 16'h0630;
                        4'd5: glyph_row = 16'h0C18;
                        4'd6: glyph_row = 16'h0C18;
                        4'd7: glyph_row = 16'h0C18;
                        4'd8: glyph_row = 16'h0C18;
                        4'd9: glyph_row = 16'h0C18;
                        4'd10: glyph_row = 16'h0630;
                        4'd11: glyph_row = 16'h03E0;
                        4'd12: glyph_row = 16'h0000;
                        4'd13: glyph_row = 16'h0000;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h64: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0030;
                        4'd2: glyph_row = 16'h0030;
                        4'd3: glyph_row = 16'h0030;
                        4'd4: glyph_row = 16'h0030;
                        4'd5: glyph_row = 16'h03B0;
                        4'd6: glyph_row = 16'h0670;
                        4'd7: glyph_row = 16'h0C30;
                        4'd8: glyph_row = 16'h0C30;
                        4'd9: glyph_row = 16'h0C30;
                        4'd10: glyph_row = 16'h0C30;
                        4'd11: glyph_row = 16'h0C30;
                        4'd12: glyph_row = 16'h0670;
                        4'd13: glyph_row = 16'h03B0;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h65: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h0000;
                        4'd3: glyph_row = 16'h03C0;
                        4'd4: glyph_row = 16'h0660;
                        4'd5: glyph_row = 16'h0C30;
                        4'd6: glyph_row = 16'h0C30;
                        4'd7: glyph_row = 16'h0FF0;
                        4'd8: glyph_row = 16'h0C00;
                        4'd9: glyph_row = 16'h0C00;
                        4'd10: glyph_row = 16'h0620;
                        4'd11: glyph_row = 16'h03C0;
                        4'd12: glyph_row = 16'h0000;
                        4'd13: glyph_row = 16'h0000;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h6C: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0180;
                        4'd2: glyph_row = 16'h0180;
                        4'd3: glyph_row = 16'h0180;
                        4'd4: glyph_row = 16'h0180;
                        4'd5: glyph_row = 16'h0180;
                        4'd6: glyph_row = 16'h0180;
                        4'd7: glyph_row = 16'h0180;
                        4'd8: glyph_row = 16'h0180;
                        4'd9: glyph_row = 16'h0180;
                        4'd10: glyph_row = 16'h0180;
                        4'd11: glyph_row = 16'h0180;
                        4'd12: glyph_row = 16'h0180;
                        4'd13: glyph_row = 16'h0180;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h31: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h0080;
                        4'd3: glyph_row = 16'h0380;
                        4'd4: glyph_row = 16'h0580;
                        4'd5: glyph_row = 16'h0180;
                        4'd6: glyph_row = 16'h0180;
                        4'd7: glyph_row = 16'h0180;
                        4'd8: glyph_row = 16'h0180;
                        4'd9: glyph_row = 16'h0180;
                        4'd10: glyph_row = 16'h0180;
                        4'd11: glyph_row = 16'h0180;
                        4'd12: glyph_row = 16'h0180;
                        4'd13: glyph_row = 16'h0180;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h32: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h0780;
                        4'd3: glyph_row = 16'h08E0;
                        4'd4: glyph_row = 16'h0060;
                        4'd5: glyph_row = 16'h0060;
                        4'd6: glyph_row = 16'h0060;
                        4'd7: glyph_row = 16'h00C0;
                        4'd8: glyph_row = 16'h01C0;
                        4'd9: glyph_row = 16'h0300;
                        4'd10: glyph_row = 16'h0600;
                        4'd11: glyph_row = 16'h0C00;
                        4'd12: glyph_row = 16'h0C00;
                        4'd13: glyph_row = 16'h0FE0;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h33: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h07C0;
                        4'd3: glyph_row = 16'h08E0;
                        4'd4: glyph_row = 16'h0060;
                        4'd5: glyph_row = 16'h0060;
                        4'd6: glyph_row = 16'h00C0;
                        4'd7: glyph_row = 16'h0780;
                        4'd8: glyph_row = 16'h0060;
                        4'd9: glyph_row = 16'h0030;
                        4'd10: glyph_row = 16'h0030;
                        4'd11: glyph_row = 16'h0030;
                        4'd12: glyph_row = 16'h0860;
                        4'd13: glyph_row = 16'h07C0;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h34: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h0060;
                        4'd3: glyph_row = 16'h00E0;
                        4'd4: glyph_row = 16'h01E0;
                        4'd5: glyph_row = 16'h0160;
                        4'd6: glyph_row = 16'h0360;
                        4'd7: glyph_row = 16'h0660;
                        4'd8: glyph_row = 16'h0C60;
                        4'd9: glyph_row = 16'h0860;
                        4'd10: glyph_row = 16'h1FF8;
                        4'd11: glyph_row = 16'h0060;
                        4'd12: glyph_row = 16'h0060;
                        4'd13: glyph_row = 16'h0060;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                8'h3A: begin
                    case (r)
                        4'd0: glyph_row = 16'h0000;
                        4'd1: glyph_row = 16'h0000;
                        4'd2: glyph_row = 16'h0000;
                        4'd3: glyph_row = 16'h0180;
                        4'd4: glyph_row = 16'h0180;
                        4'd5: glyph_row = 16'h0000;
                        4'd6: glyph_row = 16'h0000;
                        4'd7: glyph_row = 16'h0000;
                        4'd8: glyph_row = 16'h0000;
                        4'd9: glyph_row = 16'h0000;
                        4'd10: glyph_row = 16'h0180;
                        4'd11: glyph_row = 16'h0180;
                        4'd12: glyph_row = 16'h0000;
                        4'd13: glyph_row = 16'h0000;
                        4'd14: glyph_row = 16'h0000;
                        4'd15: glyph_row = 16'h0000;
                        default: glyph_row = 16'h0000;
                    endcase
                end
                default: glyph_row = 16'h0000;
            endcase
        end
    endfunction

    always @(*) begin
        O_row_bits = glyph_row(I_char, I_row);
    end
endmodule
