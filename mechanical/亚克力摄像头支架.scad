// 亚克力 MIPI 摄像头支架
// 单位：mm。模型由 3 mm 板材折弯/拼接形状近似；摄像头板和螺丝不包含在内。

// ---------- 可调整尺寸 ----------
plate_width = 40;          // 支架宽度
back_height = 40;          // 背板沿板面长度
base_depth = 40;           // 底板前后深度
plate_thickness = 3;       // 亚克力厚度
back_lean_deg = 0;         // 背板垂直于底板，即底板与背板夹角为 90°

camera_board_size = 35;    // 摄像头板外形参考尺寸
camera_hole_pitch = 28;    // 摄像头板安装孔中心距
camera_hole_d = 2;         // 安装孔直径

ffc_slot_length = 15;      // 排线槽长度
ffc_slot_width = 1;        // 排线槽宽度
// --------------------------------

// 在 Y-Z 平面定义底板和倾斜背板的连续截面，再沿 X 方向挤出支架宽度。
module bracket_body() {
    a = back_lean_deg;
    t = plate_thickness;
    h = back_height;
    inner_top_y = -h * sin(a);
    inner_top_z = t + h * cos(a);

    multmatrix([
        [0, 0, 1, 0],
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 0, 1]
    ])
    linear_extrude(height=plate_width, center=true, convexity=10)
        polygon(points=[
            [0, 0],
            [base_depth, 0],
            [base_depth, t],
            [0, t],
            [inner_top_y, inner_top_z],
            [inner_top_y - t*cos(a), inner_top_z - t*sin(a)],
            [-t*cos(a), t - t*sin(a)]
        ]);
}

// 四个孔按摄像头板的 28 mm 方形孔距布置，板中心对准背板中心。
module camera_mount_holes() {
    a = back_lean_deg;
    for (x = [-camera_hole_pitch/2, camera_hole_pitch/2]) {
        for (s = [back_height/2 - camera_hole_pitch/2,
                  back_height/2 + camera_hole_pitch/2]) {
            translate([x, -s*sin(a), plate_thickness + s*cos(a)])
                rotate([a - 90, 0, 0])
                    cylinder(d=camera_hole_d, h=20, center=true, $fn=32);
        }
    }
}

// 背板中心的 FFC 排线通槽，槽长沿支架宽度方向。
module ffc_slot() {
    a = back_lean_deg;
    s = back_height/2;
    translate([0, -s*sin(a), plate_thickness + s*cos(a)])
        rotate([a - 90, 0, 0])
            cube([ffc_slot_length, ffc_slot_width, 20], center=true);
}

difference() {
    bracket_body();
    camera_mount_holes();
    ffc_slot();
}
