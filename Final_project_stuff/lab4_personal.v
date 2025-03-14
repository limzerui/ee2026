
module Top_Student(
  input clk, btnU, btnD, btnL, btnR, btnC,
  output [7:0] JB
);
    wire [7:0] oledJ;
    assign oledJ = JB;

    wire clk_mhz_6_25;
    clk_divider cdl(clk, 32'd7, clk_mhz_6_25);

    wire frame_begin, sending_pixels,sample_pixel;
    wire [12:0] pixel_index;
    reg [15:0] oled_data;

    Oled_Display oled_inst ( 
        .clk(clk_mhz_6_25),
        .reset(0),
        .frame_begin(frame_begin),
        .sending_pixels(sending_pixels),
        .sample_pixel(sample_pixel),
        .pixel_index(pixel_index),
        .pixel_data(oled_data),
        .cs(oledJ[0]),
        .sdin(oledJ[1]),
        .sclk(oledJ[3]),
        .d_cn(oledJ[4]),
        .resn(oledJ[5]),
        .vccen(oledJ[6]),
        .pmoden(oledJ[7])
    );

    localparam pixel_index_width = $clog2(96*64);
    localparam x_width = $clog2(96);
    localparam y_width = $clog2(64);
    localparam x_center = 96/2;
    localparam y_center = 64/2;

    localparam COLOR_BLACK = 16'h0000;
    localparam COLOR_RED   = 16'hF800;
    localparam COLOR_GREEN = 16'h07E0;

    // Border Parameters
    localparam BORDER_DISTANCE = 4;
    localparam BORDER_THICKNESS = 3;

    // Ring Parametes
    reg ring_active = 0;
    reg [7:0] outer_dia = 30;  // Initial outer diameter
    wire [7:0] inner_dia = outer_dia - 5;
    //wire[7:0] outer_radius = outer_dia>>1;
    //wire[7:0] inner_radius = inner_dia>>1;

    wire[x_width-1:0] x;
    wire[y_width-1:0] y;
    assign x = pixel_index % 96;
    assign y = pixel_index / 96;

    wire in_border;
    wire in_excluded_area = (x < BORDER_DISTANCE || x >= 96 - BORDER_DISTANCE || y < BORDER_DISTANCE || y >= 64 - BORDER_DISTANCE);
    //if x is within 0 and 4 or 92 and 96 or y is within 0 and 4 or 60 and 64, then it is not in border
    assign in_border = (
        (x >= BORDER_DISTANCE && x< BORDER_DISTANCE + BORDER_THICKNESS) ||
        (x >= 96 - BORDER_DISTANCE - BORDER_THICKNESS && x < 96 - BORDER_DISTANCE) ||
        (y >= BORDER_DISTANCE && y < BORDER_DISTANCE + BORDER_THICKNESS) ||
        (y >= 64 - BORDER_DISTANCE - BORDER_THICKNESS && y < 64 - BORDER_DISTANCE)
    );

    wire [15:0] dx = (x > x_center) ? (x - x_center) : (x_center - x);
    wire [15:0] dy = (y > y_center) ? (y - y_center) : (y_center - y);
    wire [31:0] dx_sq = dx * dx;
    wire [31:0] dy_sq = dy * dy;
    wire [31:0] dist_sq = dx_sq + dy_sq;
    wire[31:0] dist_sq_4 = dist_sq << 2;
    wire [31:0] outer_dia_sq = outer_dia * outer_dia;
    wire [31:0] inner_dia_sq = (outer_dia - 5) * (outer_dia - 5);
    wire in_ring = (dist_sq_4 <= outer_dia_sq) && (dist_sq_4 >= inner_dia_sq);

    always @(posedge clk_mhz_6_25) begin
        if (in_excluded_area) begin
            oled_data <= COLOR_BLACK;
        end else if(in_border) begin
            oled_data <= COLOR_RED;
        end else if(ring_active && in_ring) begin
            oled_data <= COLOR_GREEN;
        end else begin
            oled_data <= COLOR_BLACK;
        end
    end

    wire center_pressed, up_pressed, down_pressed;

    debounce deb_center(
        .clk(clk_mhz_6_25),
        .btn_in(btnC),
        .pressed(center_pressed)
    );
    debounce deb_up(
        .clk(clk_mhz_6_25),
        .btn_in(btnU),
        .pressed(up_pressed)
    );
    debounce deb_down(
        .clk(clk_mhz_6_25),
        .btn_in(btnD),
        .pressed(down_pressed)
    );

    always @(posedge clk_mhz_6_25) begin
            if(center_pressed && !ring_active) begin
                ring_active <= 1;
            end else if(up_pressed && ring_active) begin
                if (outer_dia <= 45) outer_dia <= outer_dia +5;
            end
            else if(down_pressed && ring_active) begin
                if (outer_dia >= 15) outer_dia <= outer_dia -5;
            end
    end
endmodule

module debounce(
    input clk,       // 6.25 MHz clock
    input btn_in,
    output reg pressed
);
    // For a 6.25 MHz clock:
    // 1ms = 6250 cycles, 200ms = 6250 * 200 = 1,250,000 cycles
    localparam DEBOUNCE_COUNT = 1250000;  // 200 ms debounce period

    reg [20:0] counter; // 21 bits are sufficient (2^21 = 2097152)
    reg state; // 0: ready, 1: debouncing

    always @(posedge clk) begin
        case (state)
            0: begin
                if (btn_in) begin
                    pressed <= 1;  // Generate a single pulse when the press is detected
                    state <= 1;
                    counter <= 0;
                end else begin
                    pressed <= 0;
                end
            end
            1: begin
                pressed <= 0;  // Do not output further pulses during debounce
                if (counter < DEBOUNCE_COUNT) begin
                    counter <= counter + 1;
                end else begin
                    // After 200 ms have elapsed, wait for the button to be released before rearming
                    if (!btn_in) begin
                        state <= 0;
                    end
                end
            end
        endcase
    end
endmodule

module clk_divider(
  input clk,
  input [31:0] m,
  output reg slow_clk
);
    reg [31:0] count;
    
    initial begin
        slow_clk = 0;
        count = 0;
    end

  always @(posedge clk) begin
    if (count == m) begin
      count <= 0;
      slow_clk <= ~slow_clk;
    end else count <= count + 1;
  end
endmodule



//turn on led[n] when sw[n] is pressed. i have 15 led and sw
module led_switch(
  input clk, [15:0]sw,
  output reg [15:0] led
);
    reg [15:0] sw_reg;
    always @(posedge clk) begin
        sw_reg <= sw;
        led <= sw_reg;
    end
    endmodule

module seven_seg_controller(
    input clk,          
    output reg [7:0] seg,
    output reg [3:0] an  
);

  parameter M = 150000;
  
  wire slow_clk;
  clk_divider cd_inst (
    .clk(clk),
    .m(M),
    .slow_clk(slow_clk)
  );
  
  reg [1:0] digit;
  
  always @(posedge slow_clk) begin
    digit <= digit + 1;
  end
  
  always @(*) begin
    case(digit)
      2'b00: begin
        an  = 4'b1110;  
        seg = 8'b11111001;//1, B and C are on
      end
      2'b01: begin
        an  = 4'b1101;  
        seg = 8'b11111001; //1 
      end
      2'b10: begin
        an  = 4'b1011;    // Enable anode 2
        seg = 8'b00110000; //display 3 and the dp
      end
      2'b11: begin
        an  = 4'b0111;    // Enable anode 3
        seg = 8'b1001111; //1001 0010
      end
      default: begin
        an  = 4'b1111;
        seg = 8'b1111111;
      end
    endcase
  end
endmodule