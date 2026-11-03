`timescale 1ns / 1ps

module super_top(
    input  wire sys_clk_pin,    // 板载时钟输入脚 33.333MHz
    input  wire rst_n,      // 总复位

    // ====== 视觉模块 (OV7670 & LCD) ======
    output wire lcd_clk,
    output wire lcd_hs,
    output wire lcd_vs,
    output wire lcd_de,
    output wire lcd_bl,
    output wire lcd_rst,
    output wire [23:0] lcd_rgb,
    
    output wire ov_xclk,    
    output wire ov_sio_c,
    inout  wire ov_sio_d,
    input  wire ov_pclk,
    input  wire ov_href,
    input  wire ov_vsync,
    input  wire [7:0] ov_data,

    // ====== 循迹避障模块 ======
    // ★ 五路循迹的传感器线现在接在上层板（本板 J4 被板载 LCD 占满，接不了），
    //   状态从板间链路下来：link_demux 的 track_pat[4:0] 直接喂给 xunbi_core。
    //   本板不再有自己的 track_xx 输入脚，D20/F19/F20 三个脚因此空出来了。
    output wire us_trig,
    input  wire us_echo,

    // ====== 共用底盘控制 (I2C) ======
    output wire motor_scl,
    inout  wire motor_sda,

    // ====== 机械臂控制 (UART) ======
    output wire arm_uart,
    output wire tcon,

    // ====== 板间串口链路：接上层板 project_109_cam_lcd_voice（115200 8N1，2 个脚）======
    input  wire link_rx,      // D19  <- 上层板 F19 (TX)
    output wire link_tx       // C20  -> 上层板 F20 (RX)
);

    // Input pins cannot feed both an input buffer and internal logic directly in
    // the 2022.2 synthesis engine. Create one explicit global clock net.
    wire sys_clk;
    BUFG u_sys_clk_bufg (
        .I (sys_clk_pin),
        .O (sys_clk)
    );

    // ===================================
    // 基础时钟生成 (复用视觉模块的 IP)
    // ===================================
    wire clk_75m; 
    wire clk_24m; 
    
    clk_wiz_0 u_clock(
        .clk_in1 (sys_clk), // 33.333M in
        .clk_out1(clk_75m), // 75M out
        .clk_out2(clk_24m)  // 24M out
    );

    // ===================================
    // 工作模式解析：只由语音/YOLO 命令决定（拨码开关已经拆掉）
    //   命令 1 循迹 / 2 跟随 / 3 防空 / 4 停下 / 5 装卸货
    //   还没收到命令时三个都不使能（站着等指令）。
    // ===================================
    wire vision_en;
    wire defense_en;
    wire xunbi_en ;
    wire arm_en   ;
    wire [7:0] link_peer_cmd;   // one byte decoded from the upper-board link
    wire       link_cmd_valid;  // one-cycle pulse for a real mode command

    voice_mode_select u_voice_mode_select (
        .clk       (sys_clk),
        .rst_n     (rst_n),
        .cmd       (link_peer_cmd),
        .cmd_valid (link_cmd_valid),   // link_demux 给的"这一帧是命令"脉冲
        .xunbi_en  (xunbi_en),
        .vision_en (vision_en),
        .defense_en(defense_en),
        .arm_en    (arm_en)
    );

    // ===================================
    // 机械臂实例 (上电等待 3 秒，靠复位脉冲重跑)
    // ===================================
    // 机械臂使能来自 arm_en（语音说"装卸货"=5）；
    // arm_voice_trigger 只负责每次收到命令给一个约 1ms 的复位脉冲，
    // 让它从 3 秒等待开始重跑一遍定点放置（每说一次都会重跑）。
    // ★ STARTUP_WAIT_MS=3000：说"装卸货"后约 3 秒机械臂开始动。
    // ★ 收到"停下"(命令 4)：arm_stop_cmd 给 arm_pick_place_once_top 一拍，
    //   它立刻广播 SERVO_MOVE_STOP（指令 12 / ID 254），所有舵机停在当前角度；
    //   同时 arm_en=0，动作序列也停下（不会接着走下一步）。
    // ★ 收到命令 1/2/3：arm_home_cmd 让它把 6 个舵机送回初始姿态（第 1 步的姿势），
    //   然后停在那儿。命令 5 不用这个：装卸货序列的第 1 步本来就是初始姿态。
    // ★ 上电/复位后另有一个独立的回位脉冲（见下面 pwr_home_*），不参与任何模式。
    wire arm_voice_rst_n;
    wire arm_stop_cmd;
    wire arm_home_cmd;

    assign arm_stop_cmd = link_cmd_valid && (link_peer_cmd == 8'd4);

    // 命令 1/3 -> 回初始姿态。命令 2 现在由舵机 4/6 跟踪红色目标，
    // 不再整臂回位，因此舵机 5 在跟踪期间保持不动。
    // 延后两拍再给，让 voice_mode 先更新；模块里只有 run_en=0 时才执行回位，
    // 所以装卸货过程中不会被回位请求插进来。
    wire arm_home_raw;
    assign arm_home_raw = link_cmd_valid &&
                          ((link_peer_cmd == 8'd1) || (link_peer_cmd == 8'd2));
    reg [1:0] arm_home_dly;
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) arm_home_dly <= 2'd0;
        else       arm_home_dly <= {arm_home_dly[0], arm_home_raw};
    end

    // 上电回位：复位释放后固定等 3 秒（舵机上电），给一拍"回初始姿态"。
    // 它独立于任何模式，也不受"装卸货"命令脉冲影响 —— 装卸货自己的 3 秒等待在
    // arm_pick_place_once_top 的 S_POWERUP 里，两边互不相干。
    reg [26:0] pwr_home_cnt;
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n)                              pwr_home_cnt <= 27'd0;
        else if(pwr_home_cnt < 27'd100_000_000) pwr_home_cnt <= pwr_home_cnt + 1'b1;
    end
    wire pwr_home_req = (pwr_home_cnt == (27'd100_000_000 - 1'b1));   // 3.0s @33.333MHz

    assign arm_home_cmd = arm_home_dly[1] | (pwr_home_req && !defense_en);

    arm_voice_trigger #(
        .CLK_FREQ    (33_333_333),   // 与板载晶振一致
        .ARM_CMD     (8'd5),         // 5 = 装卸货
        .RST_HOLD_MS (1)             // 复位脉冲宽度：1ms
    ) u_arm_voice_trigger (
        .clk       (sys_clk),
        .rst_n     (rst_n),
        .cmd       (link_peer_cmd),
        .cmd_valid (link_cmd_valid),   // 只用命令帧，循迹状态帧不碰机械臂
        .arm_req   (),                 // 保持电平用不上了：使能改由 arm_en（看 voice_mode）给
        .arm_rst_n (arm_voice_rst_n)
    );

    // 机械臂复位：只由复位键 + 每次命令的复位脉冲控制。
    // 不再把 arm_en 放进复位里 —— 模块要活着才能发"停止包"；
    // 使能改由 run_en 管（arm_en=0 时它停在上电等待里，不发任何动作）。
    wire arm_rst_n;
    assign arm_rst_n = rst_n & arm_voice_rst_n;

    wire pick_arm_uart;
    wire pick_tcon;
    wire track_arm_uart;
    wire track_tcon;

    arm_pick_place_once_top #(
        .CLK_HZ(33333333),
        .STARTUP_WAIT_MS(3000)
    ) u_arm_core (
        .sys_clk  (sys_clk),
        .rst_n    (arm_rst_n),
        .run_en   (arm_en),          // 1 = 允许跑动作（只有"装卸货"模式）
        .stop_i   (arm_stop_cmd),    // "停下"命令：立刻广播舵机停止
        .home_i   (arm_home_cmd),    // 命令 1/2/3/5：先回初始姿态
        .arm_uart (pick_arm_uart),
        .tcon     (pick_tcon)
    );

    // ===================================
    // 视觉跟瞄核心实例
    // ===================================
    wire [10:0] vision_box_x;
    wire [10:0] vision_box_y;
    wire [10:0] vision_box_w;
    wire [10:0] vision_box_h;
    wire [7:0] vision_m1, vision_m2, vision_m3, vision_m4;
    wire vision_cmd_req;

    shijue_arm_core u_shijue_arm_core (
        .clk              (sys_clk),
        .clk_75m          (clk_75m),
        .clk_24m          (clk_24m),
        .rst_n            (rst_n),
        // 只有"跟随"(命令 2) 才让下层 OV7670 去锁红色目标。防空模式仍然打开
        // 摄像头和 LCD，但 color_track 的 lock_sw=0 会让红框固定停在画面中心
        // （300×400 源图中心 150,200，框 100×100），不再跟着画面里的红东西跑。
        .vision_mode_sw   (vision_en),
        
        .lcd_clk(lcd_clk), .lcd_hs(lcd_hs), .lcd_vs(lcd_vs), .lcd_de(lcd_de),
        .lcd_bl(lcd_bl), .lcd_rst(lcd_rst), .lcd_rgb(lcd_rgb),
        .ov_xclk(ov_xclk), .ov_sio_c(ov_sio_c), .ov_sio_d(ov_sio_d), 
        .ov_pclk(ov_pclk), .ov_href(ov_href), .ov_vsync(ov_vsync), .ov_data(ov_data),
        
        .target_x(vision_box_x), .target_y(vision_box_y),
        .target_w(vision_box_w), .target_h(vision_box_h),
        .out_m1(vision_m1), .out_m2(vision_m2),
        .out_m3(vision_m3), .out_m4(vision_m4),
        .cmd_update(vision_cmd_req)
    );

    // ===================================
    // 循迹避障核心实例
    // ===================================
    wire [7:0] xunbi_m1, xunbi_m2, xunbi_m3, xunbi_m4;
    wire xunbi_cmd_req;

    xunbi_core u_xunbi_core (
        .sys_clk   (sys_clk),
        .rst_n     (rst_n),
        .run_en    (xunbi_en),                                // 只有命令 1 才让循迹 PID 工作
        .track_l2  (track_pat[4]), .track_l1(track_pat[3]), .track_m(track_pat[2]),
        .track_r1  (track_pat[1]), .track_r2(track_pat[0]),   // 5 路都来自上层板（板间链路）
        .us_trig   (us_trig), .us_echo(us_echo),
        
        .out_m1(xunbi_m1), .out_m2(xunbi_m2), .out_m3(xunbi_m3), .out_m4(xunbi_m4),
        .cmd_update(xunbi_cmd_req)
    );

    // ===================================
    // 底盘 I2C 总线路由与自动刹停
    // ===================================
    reg [7:0] iic_m1, iic_m2, iic_m3, iic_m4;
    reg iic_cmd_req;

    // 防空原地转向（见下面的 defense_spin 实例）
    wire        spin_active;
    wire        spin_req;
    wire [7:0]  spin_m1, spin_m2, spin_m3, spin_m4;

    // 当需要停车时，生成周期性的刹车请求，防止 I2C 总线卡死或不触发
    reg [19:0] stop_cnt;
    reg stop_pulse;
    always @(posedge sys_clk) begin
        if (!vision_en && !xunbi_en) begin
            if (stop_cnt < 20'd333333) begin // 约 10ms
                stop_cnt <= stop_cnt + 1;
                stop_pulse <= 1'b0;
            end else begin
                stop_cnt <= 0;
                stop_pulse <= 1'b1;
            end
        end else begin
            stop_cnt <= 0;
            stop_pulse <= 1'b0;
        end
    end

    // 路由选择网络
    always @(*) begin
        if (vision_en) begin
            iic_m1 = vision_m1; iic_m2 = vision_m2; iic_m3 = vision_m3; iic_m4 = vision_m4;
            iic_cmd_req = vision_cmd_req;
        end else if (xunbi_en) begin
            iic_m1 = xunbi_m1; iic_m2 = xunbi_m2; iic_m3 = xunbi_m3; iic_m4 = xunbi_m4;
            iic_cmd_req = xunbi_cmd_req;
        end else if (spin_active) begin
            // 防空：云台到限位且目标顶住同侧边框 -> 原地转向
            iic_m1 = spin_m1; iic_m2 = spin_m2; iic_m3 = spin_m3; iic_m4 = spin_m4;
            iic_cmd_req = spin_req;
        end else begin
            iic_m1 = 8'sd0; iic_m2 = 8'sd0; iic_m3 = 8'sd0; iic_m4 = 8'sd0;
            iic_cmd_req = stop_pulse; // 输出持续停车命令
        end
    end

    // 唯一的共用底盘发包器
    iic_w_top u_motor_iic(
        .sys_clk        (sys_clk),     
        .rst_n          (rst_n),
        .SDA            (motor_sda),
        .SCL            (motor_scl),
        .motor1_spd     (iic_m1),
        .motor2_spd     (iic_m2),
        .motor3_spd     (iic_m3),
        .motor4_spd     (iic_m4),
        .cmd_update_req (iic_cmd_req)
    );

    // ===================================
    // 板间串口链路（上层板 project_109_cam_lcd_voice）
    //   上层板收到语音命令后把模式号发一帧 AA 55 <命令号> 55 AA 下来（115200 8N1）；
    //   本板 ECHO_EN=0：bbox 突发有 11 帧，不能逐字节回显占用回程链路。
    //   一个字节分两类，靠 bit7 区分（link_demux 负责拆开）：
    //     bit7=1 -> 循迹状态帧：低 5 位 = 上层板读到的五路循迹，锁在 track_pat 里，
    //               每 1ms 一帧，直接喂给 xunbi_core（见上面的例化）。
    //     bit7=0 -> 命令号：cmd_valid 那一拍有效，由 voice_mode_select 记成"当前模式"。
    //               1 循迹 -> 开 xunbi_core（五路循迹 -> 麦克轮）；
    //               5 装卸货 -> 使能机械臂并重跑一遍定点放置（见上面 arm 那一段）；
    //               2 跟随 -> 下层红色目标控制底盘；
    //               3 防空 -> 上层 OV5640 目标框控制舵机 4/6；
    //               4 -> 停车并停止舵机。
    //     bit7=0 的 0x40 是 bbox 突发起始字节，后接 9 个坐标/状态字节和 1 个校验字节。
    //   ★ 本板不回发 bbox/循迹，避免 11 字节坐标突发产生无用的回程流量。
    //   link_err_flag 是链路坏帧指示：本板引脚已经排满（J4 全被板载 LCD 占了）引不出来，
    //   排障看上层的 frame_err_flag 就够了。
    // ===================================
    wire       link_peer_valid;   // 收到上层板一整帧（一个时钟周期的高脉冲）
    wire       link_err_flag  ;   // 链路坏帧指示（出过一次错就拉高保持）
    wire [4:0] track_pat      ;   // 五路循迹状态（来自上层板，保持住）
    wire       track_upd      ;   // 循迹状态更新（一拍，暂时没人用，留给以后）
    wire       bbox_rx_busy   ;   // bbox 11 字节突发进行中
    wire       bbox_valid     ;   // 上层 OV5640 当前有有效目标
    wire [9:0] bbox_x         ;
    wire [9:0] bbox_y         ;
    wire [9:0] bbox_w         ;
    wire [9:0] bbox_h         ;
    wire       bbox_label     ;
    wire       bbox_frame_tgl ;

    // Upper OV5640 bbox: serialized by upper_link_send.
    bbox_unpack #(
        .CLK_FREQ (33_333_333)
    ) u_bbox_unpack (
        .clk             (sys_clk),
        .rst_n           (rst_n),
        .peer_cmd        (link_peer_cmd),
        .peer_valid      (link_peer_valid),
        .bbox_valid      (bbox_valid),
        .bbox_x          (bbox_x),
        .bbox_y          (bbox_y),
        .bbox_w          (bbox_w),
        .bbox_h          (bbox_h),
        .bbox_label      (bbox_label),
        .bbox_frame_tgl  (bbox_frame_tgl),
        .bbox_rx_busy    (bbox_rx_busy)
    );

    // 把收到的字节拆成"循迹状态"和"命令号"两类
    link_demux u_link_demux (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .peer_cmd   (link_peer_cmd),
        .peer_valid (link_peer_valid),
        .bbox_busy  (bbox_rx_busy),
        .track_pat  (track_pat),
        .track_upd  (track_upd),
        .cmd_valid  (link_cmd_valid)
    );

    board_link #(
        .CLK_FREQ (33_333_333),   // 必须与板载晶振一致，写错串口会收成乱码
        .UART_BPS (115200),       // 与上层板一致
        .ECHO_EN  (1'b0)          // bbox 突发不能逐字节回显
    ) u_board_link (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .link_rx    (link_rx),
        .link_tx    (link_tx),
        .local_cmd  (8'd0),       // 本板暂时没有要主动上报的东西
        .local_send (1'b0),
        .peer_cmd   (link_peer_cmd),
        .peer_valid (link_peer_valid),
        .link_err   (link_err_flag)
    );

    // Command 3 (air defense) uses the UPPER OV5640 bbox over the board link.
    // Servo 6 = yaw, servo 4 = primary pitch, servo 3 = secondary pitch after
    // servo 4 reaches 200 or 400. Servos 1/2/5 receive one fixed startup pose.
    // The bbox arrives in raw OV5640 coordinates, while the upper LCD displays
    // the frame rotated by 180 degrees. Mirror the bbox centre into the
    // coordinates the operator actually sees before driving the gimbal.
    // Otherwise a target at the visible top-left arrives as bottom-right and
    // both servo axes move in the wrong direction.
    wire [10:0] bbox_raw_cx = {1'b0, bbox_x} + {2'b0, bbox_w[9:1]};
    wire [10:0] bbox_raw_cy = {1'b0, bbox_y} + {2'b0, bbox_h[9:1]};
    wire [10:0] bbox_cx = 11'd599 - bbox_raw_cx;
    wire [10:0] bbox_cy = 11'd399 - bbox_raw_cy;

    // 每次收到"防空"(命令 3) 都给一次回位脉冲：即使在防空模式里再说一遍，
    // 也会把 6 个舵机送回防空初始姿态。防空时机械臂串口被 u_arm_red_track 独占，
    // 所以回位只能走这个模块自己，走 arm_pick_place_once_top 是发不到总线的。
    wire defense_home_req = link_cmd_valid && (link_peer_cmd == 8'd3);
    wire [15:0] track_yaw_pos;

    arm_red_track #(
        .CLK_HZ(33_333_333),
        .BAUD(115_200),
        .CENTER_PITCH(200),
        .CENTER_YAW(300),
        .PITCH_MIN(200),
        .PITCH_MAX(400),
        .YAW_MIN(210),          // 防空时舵机6 的软件范围（与装卸货姿态范围一致）
        .YAW_MAX(750),
        .PITCH3_MIN(600),
        .PITCH3_MAX(800),
        .PITCH_CASCADE_LOW(200),
        .PITCH_CASCADE_HIGH(400),
        .POS4_INIT(300),
        .POS6_INIT(500),
        .POS1_AIR(220),
        .POS2_AIR(500),
        .POS3_INIT(700),
        .POS5_AIR(400),
        .DEADBAND(16),
        .KP_SHIFT(3),
        // 防空模式降低每次位置更新的最大步进，减慢机械臂下落并减少冲击。
        .STEP_MAX(14),
        .MOVE_TIME_MS(100),     // 跟踪中的单次动作时间
        .HOME_TIME_MS(1000),    // 回防空初始姿态的时间，与"追随"口令自动复位一致
        .UPDATE_PERIOD_MS(100),
        .PITCH_SIGN(1),
        .PITCH3_SIGN(-1),
        .YAW_SIGN(1)
    ) u_arm_red_track (
        .clk        (sys_clk),
        .rst_n      (rst_n & defense_en),
        .target_pitch(bbox_cy),
        .target_yaw  (bbox_cx),
        .target_valid(bbox_valid),
        .home_i     (defense_home_req),
        .arm_uart   (track_arm_uart),
        .tx_oe      (track_tcon),
        .dbg_move_time(),
        .dbg_pos3   (),
        .dbg_pos4   (),
        .dbg_pos6   (track_yaw_pos),
        .dbg_servo_id(),
        .dbg_send   (),
        .dbg_busy   ()
    );

    // ===================================
    // 防空原地转向
    //   舵机6 到限位（210/750）且锁定框顶住同侧边框（框边缘距边界 <30px）时，
    //   麦克纳姆轮原地转向：至少 1s，最长 2s，中途无人机回画面中央或换边就提前停。
    //   上层下发的是固定 128×128 框且被夹在画面内，框中心可见坐标只有 63~535，
    //   所以"30px"必须量在框边缘上（模块内部换算成中心 505/94）。
    // ===================================
    defense_spin #(
        .CLK_HZ      (33_333_333),
        .IMG_W       (600),          // 可见画面 600×400（bbox 已镜像到这个坐标系）
        .CENTER_X    (300),
        .BOX_HALF_W  (64),           // 上层 ROI 框固定 128×128
        .EDGE_PX     (30),
        .YAW_MIN     (210),          // 与上面 arm_red_track 的 YAW_MIN/MAX 保持一致
        .YAW_MAX     (750),
        .CONFIRM_MS  (300),
        .MIN_SPIN_MS (1000),
        .MAX_SPIN_MS (2000),
        .SPIN_SPEED  (8'sd18),
        .RIGHT_SIGN  (1)             // 实车方向反了就改 -1
    ) u_defense_spin (
        .clk         (sys_clk),
        .rst_n       (rst_n & defense_en),
        .defense_en  (defense_en),
        .target_valid(bbox_valid),
        .target_cx   (bbox_cx),
        .yaw_pos     (track_yaw_pos),
        .spin_active (spin_active),
        .m1          (spin_m1),
        .m2          (spin_m2),
        .m3          (spin_m3),
        .m4          (spin_m4),
        .cmd_update  (spin_req)
    );

    // Only one UART source may drive the arm bus at a time.
    assign arm_uart = defense_en ? track_arm_uart : pick_arm_uart;
    assign tcon     = defense_en ? track_tcon     : pick_tcon;

endmodule
