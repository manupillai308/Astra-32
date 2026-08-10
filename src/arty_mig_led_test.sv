`timescale 1ns / 1ps

module arty_mig_led_test (
    // ---------------------------------------------------------
    // Board clocks
    // ---------------------------------------------------------
    input  wire        clk_100mhz,
    input  wire        clk_12mhz,

    // Active-low pushbutton reset
    input  wire        reset_n,

    // ---------------------------------------------------------
    // LEDs
    //
    // led[0] = PASS
    // led[1] = FAIL
    //
    // both OFF = reset / calibration / test running
    // ---------------------------------------------------------
    output wire [1:0]  led,

    // ---------------------------------------------------------
    // DDR3 physical interface
    // ---------------------------------------------------------
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_n,
    inout  wire [1:0]  ddr3_dqs_p,

    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,

    output wire        ddr3_ras_n,
    output wire        ddr3_cas_n,
    output wire        ddr3_we_n,
    output wire        ddr3_reset_n,

    output wire [0:0]  ddr3_ck_p,
    output wire [0:0]  ddr3_ck_n,
    output wire [0:0]  ddr3_cke,
    output wire [0:0]  ddr3_cs_n,

    output wire [1:0]  ddr3_dm,
    output wire [0:0]  ddr3_odt
);


    // =========================================================
    // 1. Generate 200 MHz IDELAY reference clock
    // =========================================================

    wire clk_ref_200mhz;
    wire ref_clk_locked;

    clk_wiz_0 u_clk_wiz_ref (
        .clk_in1  (clk_12mhz),
        .clk_out1 (clk_ref_200mhz),
        .reset    (1'b0),
        .locked   (ref_clk_locked)
    );


    // =========================================================
    // 2. MIG reset
    // =========================================================
    //
    // Your MIG:
    //
    //     sys_rst = active LOW
    //
    // ref_clk_locked originates from the Clock Wizard domain,
    // so synchronize it into the 100 MHz system-clock domain.
    //
    // reset_n asynchronously ASSERTS reset.
    // Release occurs synchronously after ref clock lock.
    // =========================================================

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] ref_locked_sync;

    always_ff @(posedge clk_100mhz or negedge reset_n) begin

        if (!reset_n) begin
            ref_locked_sync <= 2'b00;
        end
        else begin
            ref_locked_sync[0] <= ref_clk_locked;
            ref_locked_sync[1] <= ref_locked_sync[0];
        end

    end


    wire mig_sys_rst_n;

    assign mig_sys_rst_n = ref_locked_sync[1];


    // =========================================================
    // 3. MIG application-interface signals
    // =========================================================

    wire        ui_clk;
    wire        ui_clk_sync_rst;
    wire        init_calib_complete;


    // Command interface
    logic [27:0] app_addr;
    logic [2:0]  app_cmd;
    logic        app_en;

    wire         app_rdy;


    // Write-data interface
    logic [63:0] app_wdf_data;
    logic        app_wdf_end;
    logic [7:0]  app_wdf_mask;
    logic        app_wdf_wren;

    wire         app_wdf_rdy;


    // Read-data interface
    wire [63:0]  app_rd_data;
    wire         app_rd_data_end;
    wire         app_rd_data_valid;


    // Other MIG signals
    wire         app_sr_active;
    wire         app_ref_ack;
    wire         app_zq_ack;

    wire [11:0]  device_temp;


    // =========================================================
    // 4. MIG instance
    // =========================================================

    mig_7series_0 u_mig (

        // -----------------------------------------------------
        // DDR3 physical pins
        // -----------------------------------------------------

        .ddr3_dq              (ddr3_dq),
        .ddr3_dqs_n           (ddr3_dqs_n),
        .ddr3_dqs_p           (ddr3_dqs_p),

        .ddr3_addr            (ddr3_addr),
        .ddr3_ba              (ddr3_ba),

        .ddr3_ras_n           (ddr3_ras_n),
        .ddr3_cas_n           (ddr3_cas_n),
        .ddr3_we_n            (ddr3_we_n),
        .ddr3_reset_n         (ddr3_reset_n),

        .ddr3_ck_p            (ddr3_ck_p),
        .ddr3_ck_n            (ddr3_ck_n),

        .ddr3_cke             (ddr3_cke),
        .ddr3_cs_n            (ddr3_cs_n),
        .ddr3_dm              (ddr3_dm),
        .ddr3_odt             (ddr3_odt),


        // -----------------------------------------------------
        // Clocks/reset
        // -----------------------------------------------------

        .sys_clk_i            (clk_100mhz),
        .clk_ref_i            (clk_ref_200mhz),
        .sys_rst              (mig_sys_rst_n),


        // -----------------------------------------------------
        // Command interface
        // -----------------------------------------------------

        .app_addr             (app_addr),
        .app_cmd              (app_cmd),
        .app_en               (app_en),
        .app_rdy              (app_rdy),


        // -----------------------------------------------------
        // Write-data interface
        // -----------------------------------------------------

        .app_wdf_data         (app_wdf_data),
        .app_wdf_end          (app_wdf_end),
        .app_wdf_mask         (app_wdf_mask),
        .app_wdf_wren         (app_wdf_wren),
        .app_wdf_rdy          (app_wdf_rdy),


        // -----------------------------------------------------
        // Read-data interface
        // -----------------------------------------------------

        .app_rd_data          (app_rd_data),
        .app_rd_data_end      (app_rd_data_end),
        .app_rd_data_valid    (app_rd_data_valid),


        // -----------------------------------------------------
        // Maintenance requests unused
        // -----------------------------------------------------

        .app_sr_req           (1'b0),
        .app_ref_req          (1'b0),
        .app_zq_req           (1'b0),

        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),


        // -----------------------------------------------------
        // MIG UI
        // -----------------------------------------------------

        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),

        .init_calib_complete  (init_calib_complete),
        .device_temp          (device_temp)
    );


    // =========================================================
    // 5. Test data
    // =========================================================

    localparam logic [27:0] TEST_ADDRESS =
        28'h0000000;

    localparam logic [63:0] TEST_WORD_0 =
        64'h0123_4567_89AB_CDEF;

    localparam logic [63:0] TEST_WORD_1 =
        64'hFEDC_BA98_7654_3210;


    localparam logic [2:0] MIG_CMD_WRITE = 3'b000;
    localparam logic [2:0] MIG_CMD_READ  = 3'b001;


    // =========================================================
    // 6. Main test FSM
    // =========================================================
    //
    // Force a simple sequential/binary encoding.
    //
    // Most importantly, app_rdy/app_wdf_rdy do NOT directly
    // determine the FSM's next state.
    //
    // They first update handshake registers.
    // =========================================================

    typedef enum logic [3:0] {

        ST_WAIT_CALIB,

        ST_LAUNCH_WRITE,
        ST_WAIT_WRITE,

        ST_LAUNCH_READ,
        ST_WAIT_READ_CMD,
        ST_WAIT_READ_DATA,

        ST_PASS,
        ST_FAIL

    } test_state_t;


    (* fsm_encoding = "sequential" *)
    test_state_t state;


    // ---------------------------------------------------------
    // Registered write handshake state
    // ---------------------------------------------------------

    logic write_cmd_done;
    logic write_second_beat;
    logic write_data_done;


    // ---------------------------------------------------------
    // Registered read-command handshake state
    // ---------------------------------------------------------

    logic read_cmd_done;


    // ---------------------------------------------------------
    // Read comparison status
    // ---------------------------------------------------------

    logic read_active;
    logic read_beat;
    logic read_error;
    logic read_done;


    // ---------------------------------------------------------
    // Final result
    // ---------------------------------------------------------

    logic test_pass;
    logic test_fail;


    // =========================================================
    // 7. Command/write control
    // =========================================================
    //
    // Everything here is registered.
    //
    // There is NO always_comb block generating app_en or
    // app_wdf_wren from MIG's ready signals.
    // =========================================================

    always_ff @(posedge ui_clk) begin

        if (ui_clk_sync_rst) begin

            state <= ST_WAIT_CALIB;


            // Command interface
            app_addr <= 28'b0;
            app_cmd  <= MIG_CMD_WRITE;
            app_en   <= 1'b0;


            // Write-data interface
            app_wdf_data <= 64'b0;
            app_wdf_end  <= 1'b0;
            app_wdf_mask <= 8'h00;
            app_wdf_wren <= 1'b0;


            // Write bookkeeping
            write_cmd_done    <= 1'b0;
            write_second_beat <= 1'b0;
            write_data_done   <= 1'b0;


            // Read command bookkeeping
            read_cmd_done <= 1'b0;


            // Result
            test_pass <= 1'b0;
            test_fail <= 1'b0;

        end
        else begin

            case (state)

                // =================================================
                // WAIT FOR MIG CALIBRATION
                // =================================================

                ST_WAIT_CALIB: begin

                    app_en       <= 1'b0;
                    app_wdf_wren <= 1'b0;
                    app_wdf_end  <= 1'b0;

                    write_cmd_done    <= 1'b0;
                    write_second_beat <= 1'b0;
                    write_data_done   <= 1'b0;

                    read_cmd_done <= 1'b0;

                    test_pass <= 1'b0;
                    test_fail <= 1'b0;


                    if (init_calib_complete) begin
                        state <= ST_LAUNCH_WRITE;
                    end

                end


                // =================================================
                // LAUNCH WRITE
                // =================================================
                //
                // This state does NOT check ready.
                //
                // It simply registers valid command/data.
                //
                // Starting next ui_clk cycle:
                //
                //     app_en       = 1
                //     app_wdf_wren = 1
                //
                // and they stay asserted until MIG accepts them.
                // =================================================

                ST_LAUNCH_WRITE: begin

                    // WRITE command
                    app_addr <= TEST_ADDRESS;
                    app_cmd  <= MIG_CMD_WRITE;
                    app_en   <= 1'b1;


                    // First 64-bit write-data beat
                    app_wdf_data <= TEST_WORD_0;
                    app_wdf_mask <= 8'h00;

                    app_wdf_wren <= 1'b1;
                    app_wdf_end  <= 1'b0;


                    // Clear transaction bookkeeping
                    write_cmd_done    <= 1'b0;
                    write_second_beat <= 1'b0;
                    write_data_done   <= 1'b0;


                    state <= ST_WAIT_WRITE;

                end


                // =================================================
                // WAIT FOR WRITE ACCEPTANCE
                // =================================================

                ST_WAIT_WRITE: begin

                    // ------------------------------------------------
                    // COMMAND HANDSHAKE
                    //
                    // app_en was already asserted by a register.
                    //
                    // app_rdy ONLY updates a tiny status register.
                    // ------------------------------------------------

                    if (app_en && app_rdy) begin

                        // Command was accepted at this edge.
                        app_en <= 1'b0;

                        write_cmd_done <= 1'b1;

                    end


                    // ------------------------------------------------
                    // WRITE-DATA HANDSHAKE
                    // ------------------------------------------------

                    if (app_wdf_wren && app_wdf_rdy) begin

                        if (!write_second_beat) begin

                            // First 64-bit word was accepted.
                            //
                            // Load second word for the NEXT cycle.

                            app_wdf_data <= TEST_WORD_1;

                            // Second word is the end of the BL8 write.
                            app_wdf_end <= 1'b1;

                            write_second_beat <= 1'b1;

                        end
                        else begin

                            // Second 64-bit word was accepted.

                            app_wdf_wren <= 1'b0;
                            app_wdf_end  <= 1'b0;

                            write_data_done <= 1'b1;

                        end

                    end


                    // ------------------------------------------------
                    // IMPORTANT TIMING CHANGE:
                    //
                    // We transition only from REGISTERED flags.
                    //
                    // app_rdy/app_wdf_rdy themselves are NOT in
                    // this state-transition logic.
                    // ------------------------------------------------

                    if (write_cmd_done && write_data_done) begin

                        state <= ST_LAUNCH_READ;

                    end

                end


                // =================================================
                // LAUNCH READ
                // =================================================

                ST_LAUNCH_READ: begin

                    app_addr <= TEST_ADDRESS;
                    app_cmd  <= MIG_CMD_READ;
                    app_en   <= 1'b1;

                    read_cmd_done <= 1'b0;

                    state <= ST_WAIT_READ_CMD;

                end


                // =================================================
                // WAIT FOR READ COMMAND ACCEPTANCE
                // =================================================

                ST_WAIT_READ_CMD: begin

                    // Again:
                    //
                    // ready only updates a register.

                    if (app_en && app_rdy) begin

                        app_en <= 1'b0;

                        read_cmd_done <= 1'b1;

                    end


                    // FSM moves based on REGISTERED result,
                    // therefore one cycle after the handshake.

                    if (read_cmd_done) begin

                        read_cmd_done <= 1'b0;

                        state <= ST_WAIT_READ_DATA;

                    end

                end


                // =================================================
                // WAIT FOR READ COMPARISON TO FINISH
                // =================================================

                ST_WAIT_READ_DATA: begin

                    // read_done is generated by a separate
                    // registered read-data block below.

                    if (read_done) begin

                        if (read_error) begin

                            test_pass <= 1'b0;
                            test_fail <= 1'b1;

                            state <= ST_FAIL;

                        end
                        else begin

                            test_pass <= 1'b1;
                            test_fail <= 1'b0;

                            state <= ST_PASS;

                        end

                    end

                end


                // =================================================
                // PASS
                // =================================================

                ST_PASS: begin

                    app_en       <= 1'b0;
                    app_wdf_wren <= 1'b0;

                    test_pass <= 1'b1;
                    test_fail <= 1'b0;

                    state <= ST_PASS;

                end


                // =================================================
                // FAIL
                // =================================================

                ST_FAIL: begin

                    app_en       <= 1'b0;
                    app_wdf_wren <= 1'b0;

                    test_pass <= 1'b0;
                    test_fail <= 1'b1;

                    state <= ST_FAIL;

                end


                // =================================================
                // Defensive fallback
                // =================================================

                default: begin

                    app_en       <= 1'b0;
                    app_wdf_wren <= 1'b0;

                    test_pass <= 1'b0;
                    test_fail <= 1'b1;

                    state <= ST_FAIL;

                end

            endcase

        end

    end


    // =========================================================
    // 8. Read-data capture/comparison
    // =========================================================
    //
    // Keep this separate from the main FSM.
    //
    // MIG read outputs therefore feed only this small group of
    // registers rather than a large FSM next-state cone.
    // =========================================================

    always_ff @(posedge ui_clk) begin

        if (ui_clk_sync_rst) begin

            read_active <= 1'b0;
            read_beat   <= 1'b0;
            read_error  <= 1'b0;
            read_done   <= 1'b0;

        end
        else begin

            // -----------------------------------------------------
            // Prepare for a new read
            // -----------------------------------------------------

            if (state == ST_LAUNCH_READ) begin

                read_active <= 1'b0;
                read_beat   <= 1'b0;
                read_error  <= 1'b0;
                read_done   <= 1'b0;

            end


            // -----------------------------------------------------
            // The command handshake has already been REGISTERED
            // into read_cmd_done.
            //
            // Start listening for returned data.
            // -----------------------------------------------------

            if (read_cmd_done) begin

                read_active <= 1'b1;

            end


            // -----------------------------------------------------
            // Capture valid returned data
            // -----------------------------------------------------

            if (read_active && app_rd_data_valid) begin

                // =================================================
                // First 64-bit word
                // =================================================

                if (!read_beat) begin

                    if (app_rd_data != TEST_WORD_0) begin
                        read_error <= 1'b1;
                    end


                    // For our 2:1 / BL8 configuration,
                    // first 64-bit word should NOT be the end.

                    if (app_rd_data_end) begin

                        read_error  <= 1'b1;
                        read_done   <= 1'b1;
                        read_active <= 1'b0;

                    end
                    else begin

                        read_beat <= 1'b1;

                    end

                end


                // =================================================
                // Second 64-bit word
                // =================================================

                else begin

                    if (app_rd_data != TEST_WORD_1) begin
                        read_error <= 1'b1;
                    end


                    // Second word should terminate the burst.

                    if (!app_rd_data_end) begin
                        read_error <= 1'b1;
                    end


                    // Whether pass or fail, comparison is finished.

                    read_done   <= 1'b1;
                    read_active <= 1'b0;

                end

            end

        end

    end


    // =========================================================
    // 9. LED result
    // =========================================================
    //
    // Button reset immediately blanks both LEDs.
    //
    // LED0 = data matched
    // LED1 = data mismatch / malformed returned burst
    //
    // Both OFF:
    //
    //     reset
    //     MIG calibration
    //     write in progress
    //     read in progress
    // =========================================================

    assign led[0] =
        reset_n &&
        mig_sys_rst_n &&
        test_pass;

    assign led[1] =
        reset_n &&
        mig_sys_rst_n &&
        test_fail;


endmodule