# Existing board PCLK is routed through a regular IO pin.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hier -filter {NAME =~ *cam_pclk_IBUF*}]
# No multicycle exceptions: new motion processing must meet one-cycle timing.
