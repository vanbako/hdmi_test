# 27 MHz board clock
create_clock -name clk27 -period 37.037 [get_ports {clk_27m}]

# Pixel clock ~74.25 MHz defined on TMDS TX input pin
# create_clock -name pixclk -period 13.468 [get_pins {u_dvi/I_rgb_clk}]
create_clock -name pixclk -period 13.468 [get_nets {clk_pix}]

# TMDS 5x serial clock ~371.25 MHz defined on TMDS TX input pin
# create_clock -name tmds5x -period 2.6936 [get_pins {u_dvi/I_serial_clk}]
create_clock -name tmds5x -period 2.6936 [get_nets {clk_serial}]

# Optional: ignore async reset for timing
set_false_path -from [get_ports {rst_n}]
