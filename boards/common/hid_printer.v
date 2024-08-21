
module hid_printer (
    output uart_tx,
    input clk,
    input resetn,
    input [1:0] usb_type, 
    input usb_report,
    input [7:0] key_modifiers,
    input [7:0] key1, key2, key3, key4,
    input [7:0] mouse_btn,
    input signed [7:0] mouse_dx,
    input signed [7:0] mouse_dy,
    input game_l, game_r, game_u, game_d,
    input game_a, game_b, game_x, game_y, 
    input game_sel, game_sta,
    input game_shl, game_shr,
    input dbg_connected,
    input [63:0] dbg_hid_report,
    input dbg_active
);


`include "print.vh"

assign print_clk = clk;
assign uart_tx = uart_txp;

`include "utils.vh"                 // scancode2ascii()

reg [19:0] timer;
reg signed [10:0] mouse_x, mouse_y; // 0-1023 and negative(!) to detect overflow
wire signed [10:0] mouse_x2 = mouse_x + mouse_dx;
wire signed [10:0] mouse_y2 = mouse_y + mouse_dy;
reg [7:0] last_dx, last_dy; 

reg start_print;
reg [7:0] key_active[2];
reg [7:0] keydown;                  // scancode of key just pressed
reg [7:0] keyascii;                 // ascii of key just pressed

reg  [11:0] game_btns_r;
wire [11:0] game_btns = {game_l, game_r, game_u, game_d, game_a, game_b, 
                         game_x, game_y, game_sel, game_sta, game_shl, game_shr};

reg [22:0] cnt; // print raw reports

always @(posedge clk) begin
    if (~resetn) begin
        `print("usb_hid_host demo. Connect keyboard, mouse or gamepad.\x0d\x0a",STR); // "\r\n" does not work
    end else begin
        // Sequence timer for print delay
        if (timer == 20'hfffff) begin
            if (start_print) begin
                timer <= 0;
                start_print <= 0;
            end
        end else
            timer <= ((timer + 1) & 20'hfffff);

        // print raw reports
        cnt <= ((cnt + 1) & 23'h7fffff);

        // Simple ways to handle HID inputs
        if (usb_report) begin
            case (usb_type) 
            1: begin        // keyboard
                // just catch all keydown events. no auto-repeat. no capslock. 
                // only 2 simultaneous keys. no special keys like arrows/insert/delete/keypad
                if (key1 != 0 && key1 != key_active[0] && key1 != key_active[1]) begin
                    keydown <= key1; keyascii <= scancode2char(key1, key_modifiers);
                end else if (key2 != 0 && key2 != key_active[0] && key2 != key_active[1]) begin
                    keydown <= key2; keyascii <= scancode2char(key2, key_modifiers);
                end
                key_active[0] <= key1; key_active[1] <= key2;
                start_print <= 1;
            end
            2: begin         // mouse
                last_dx <= mouse_dx; last_dy <= mouse_dy;
                mouse_x <= mouse_x2; mouse_y <= mouse_y2;
                if (mouse_x[10:9] == 2'b01 && mouse_x2 < 0) mouse_x <= 1023;  // overflow
                else if (mouse_x2 < 0) mouse_x <= 0;
                if (mouse_y[10:9] == 2'b01 && mouse_y2 < 0) mouse_y <= 1023;
                else if (mouse_y2 < 0) mouse_y <= 0;
                start_print <= 1;
            end
            3: begin        // gamepad
                // check if button status is changed
                if (game_btns != game_btns_r)
                    start_print <= 1;
                game_btns_r <= game_btns;
            end
            endcase // usb_type
        end // if usb_report

        // print result to UART
        case (usb_type)
        1: if (start_print && keyascii != 0) begin
            `print(keyascii, STR);
            keyascii <= 0;
            start_print <= 0;
           end
        2: case (timer)                                    // print mouse position
           20'h00000: `print("\x0dMouse: x=", STR);        // Print CR (\r) to start at line
           20'h10000: `print({6'b0, mouse_x[9:0]}, 2);
           20'h20000: `print(", y=", STR);
           20'h30000: `print({6'b0, mouse_y[9:0]}, 2);
           20'h40000: `print(mouse_btn[0] ? " L" : " _", STR);
           20'h50000: `print(mouse_btn[1] ? " R" : " _", STR);
           20'h60000: `print(mouse_btn[2] ? " M" : " _", STR);
           20'h70000: `print("\x0d\x0a", STR);             // CRLF (\r\n)
           endcase
        3: case(timer)                                      // print gamepad status
           20'h00000: `print("\x0dGamepad:", STR);
           20'h10000: `print(game_l ? " L" : " _", STR);
           20'h20000: `print(game_u ? " U" : " _", STR);
           20'h30000: `print(game_r ? " R" : " _", STR);
           20'h40000: `print(game_d ? " D" : " _", STR);
           20'h50000: `print(game_a ? " A" : " _", STR);
           20'h60000: `print(game_b ? " B" : " _", STR);
           20'h70000: `print(game_x ? " X" : " _", STR);
           20'h80000: `print(game_y ? " Y" : " _", STR);
           20'h90000: `print(game_sel ? " SE" : " __", STR);
           20'ha0000: `print(game_sta ? " ST" : " __", STR);
           20'hb0000: `print(game_shl ? " sL" : " __", STR);
           20'hc0000: `print(game_shr ? " sR" : " __", STR);
           20'hd0000: `print("\x0d\x0a", STR);
           endcase
        endcase // usb_type

        // print raw reports
        if (dbg_active && dbg_connected && cnt[22:20] == 3'b100) begin
            case (cnt[19:0])
            20'h00000: `print("Last USB HID report: ", STR);
            20'h10000: `print(dbg_hid_report, 8); 
            20'h20000: `print(", type=", STR); 
            20'h30000: `print({6'b0, usb_type}, HEX); 
            20'h40000: `print("\x0d\x0a", STR); 
            endcase
        end

    end // resetn not active
end



endmodule
