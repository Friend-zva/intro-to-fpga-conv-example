//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.03
//IP Version: 1.0
//Part Number: GW5AST-LV138FPG676AC1/I0
//Device: GW5AST-138
//Device Version: B
//Created Time: Mon Aug 10 16:52:30 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    Gowin_ROM your_instance_name(
        .dout(dout), //output [31:0] dout
        .clk(clk), //input clk
        .oce(oce), //input oce
        .ce(ce), //input ce
        .reset(reset), //input reset
        .ad(ad) //input [3:0] ad
    );

//--------Copy end-------------------
