# Vivado/XSim LED-only regression runner for the CPU project.
#
# From the Vivado Tcl Console:
#   source xilinx_project/run_test_suite.tcl
#   run_cpu_test smoke
#   run_cpu_suite
#
# From a shell with Vivado on PATH:
#   vivado -mode batch -source xilinx_project/run_test_suite.tcl -tclargs all
#   vivado -mode batch -source xilinx_project/run_test_suite.tcl -tclargs smoke

set ::cpu_vivado_script_dir [file dirname [file normalize [info script]]]

proc cpu_repo_root {} {
    return [file normalize [file join $::cpu_vivado_script_dir ..]]
}

proc cpu_project_file {} {
    return [file normalize [file join $::cpu_vivado_script_dir xilinx_project.xpr]]
}

proc cpu_open_project_if_needed {} {
    if {[llength [get_projects -quiet]] == 0} {
        set project_file [cpu_project_file]
        if {![file exists $project_file]} {
            error "Vivado project not found: $project_file"
        }
        open_project $project_file
    }
}

proc cpu_test_names {} {
    set tests_root [file join [cpu_repo_root] tests]
    set tests {}

    foreach test_dir [glob -nocomplain -types d -directory $tests_root *] {
        set test_name [file tail $test_dir]
        set mem_file [file join $test_dir "${test_name}.mem"]

        if {[file exists $mem_file]} {
            lappend tests $test_name
        }
    }

    return [lsort $tests]
}

proc cpu_sim_log {} {
    return [file normalize [file join [cpu_xsim_dir] simulate.log]]
}

proc cpu_xsim_dir {} {
    set project_dir [get_property DIRECTORY [current_project]]
    set project_name [get_property NAME [current_project]]
    return [file normalize [file join $project_dir "${project_name}.sim" sim_1 behav xsim]]
}

proc cpu_read_file {path} {
    if {![file exists $path]} {
        return ""
    }

    set fh [open $path r]
    set data [read $fh]
    close $fh
    return $data
}

proc cpu_write_xsim_batch_tcl {} {
    set batch_tcl [file join [cpu_xsim_dir] test_bench.tcl]
    set fh [open $batch_tcl w]
    puts $fh "run all"
    puts $fh "quit"
    close $fh
}

proc cpu_run_xsim_script {script_base} {
    set xsim_dir [cpu_xsim_dir]
    set old_dir [pwd]

    if {[file exists [file join $xsim_dir "${script_base}.bat"]]} {
        set cmd "cmd /c ${script_base}.bat 2>@1"
    } elseif {[file exists [file join $xsim_dir "${script_base}.sh"]]} {
        set cmd "sh ${script_base}.sh 2>@1"
    } else {
        error "Generated XSim script not found: $script_base"
    }

    cd $xsim_dir
    set status [catch {
        set pipe [open "|$cmd" r]
        while {[gets $pipe line] >= 0} {
            puts $line
            flush stdout
        }
        close $pipe
    } output]
    cd $old_dir

    if {$status != 0} {
        error $output
    }
}

proc cpu_prepare_sim {} {
    cpu_open_project_if_needed

    set simset [get_filesets sim_1]
    set_property top test_bench $simset
    set_property -dict [list xsim.simulate.xsim.more_options ""] $simset

    catch {close_sim}

    launch_simulation -simset sim_1 -mode behavioral -scripts_only
    cpu_write_xsim_batch_tcl
    puts "Compiling simulation snapshot"
    cpu_run_xsim_script compile
    puts "Elaborating simulation snapshot"
    cpu_run_xsim_script elaborate
}

proc cpu_run_one_test {test_name} {
    set repo_root [cpu_repo_root]
    set test_dir [file normalize [file join $repo_root tests $test_name]]
    set program [file normalize [file join $test_dir "${test_name}.mem"]]

    if {![file exists $program]} {
        error "Program file not found: $program"
    }

    set sim_status [catch {
        file copy -force $program [file join [cpu_xsim_dir] machine_code.mem]
        set uart_stimulus [file join [cpu_xsim_dir] uart_rx_stimulus.hex]
        file delete -force $uart_stimulus
        if {$test_name eq "mmio_uart_rx_poll"} {
            set stimulus_fh [open $uart_stimulus w]
            puts $stimulus_fh "41"
            close $stimulus_fh
        } elseif {$test_name eq "mmio_uart_rx_interrupt"} {
            set stimulus_fh [open $uart_stimulus w]
            puts $stimulus_fh "5a"
            close $stimulus_fh
        }
        puts "  Simulating $test_name"
        cpu_run_xsim_script simulate
    } sim_error]

    set log_file [cpu_sim_log]
    set log_data [cpu_read_file $log_file]
    set test_log [file join $test_dir vivado_sim.log]
    if {[file exists $log_file]} {
        file copy -force $log_file $test_log
    }

    catch {close_sim}

    if {$sim_status != 0} {
        return [dict create ok 0 test $test_name program $program log $test_log message "XSim error: $sim_error"]
    }

    if {[regexp {\[PASS\][^\n\r]*cycle ([0-9]+)} $log_data pass_line cycles]} {
        return [dict create ok 1 test $test_name program $program log $test_log message $pass_line cycles $cycles]
    }

    if {[regexp {\[PASS\][^\n\r]*} $log_data pass_line]} {
        return [dict create ok 1 test $test_name program $program log $test_log message $pass_line cycles "?"]
    }

    if {[regexp {\[FAIL\][^\n\r]*} $log_data fail_line]} {
        set message $fail_line
    } else {
        set message "No LED pass message found in simulation log"
    }

    return [dict create ok 0 test $test_name program $program log $test_log message $message]
}

proc run_cpu_test {test_name} {
    puts "---------------------------------------------"
    puts "Running CPU test: $test_name"

    cpu_prepare_sim
    set result [cpu_run_one_test $test_name]

    if {[dict get $result ok]} {
        puts "\[PASS\] $test_name"
        puts "  [dict get $result message]"
        return 1
    }

    puts "\[FAIL\] $test_name"
    puts "  [dict get $result message]"
    puts "  Log: [dict get $result log]"
    return 0
}

proc run_cpu_suite {{tests ""}} {
    if {$tests eq ""} {
        set tests [cpu_test_names]
    }

    if {[llength $tests] == 0} {
        error "No runnable tests found"
    }

    set pass_count 0
    set fail_count 0
    set passed {}
    set failed {}
    set failures {}
    set total_count [llength $tests]
    set test_index 0

    puts "Preparing simulation snapshot"
    cpu_prepare_sim

    foreach test_name $tests {
        incr test_index
        puts "Running CPU test $test_index/$total_count: $test_name"

        set result [cpu_run_one_test $test_name]

        if {[dict get $result ok]} {
            incr pass_count
            lappend passed $result
        } else {
            incr fail_count
            lappend failed $test_name
            lappend failures $result
        }
    }

    puts "---------------------------------------------"
    puts "$pass_count passed, $fail_count failed"
    puts ""

    puts "Passed tests:"
    if {[llength $passed] == 0} {
        puts "  none"
    } else {
        foreach result $passed {
            puts "  [dict get $result test]: [dict get $result cycles] cycles"
        }
    }

    puts ""
    puts "Failed tests:"
    if {[llength $failures] == 0} {
        puts "  none"
    } else {
        foreach result $failures {
            puts "  [dict get $result test]: [dict get $result message]"
            puts "    Log: [dict get $result log]"
        }
    }

    if {$fail_count != 0} {
        return -code error "CPU regression failed"
    }
}

if {[info exists ::argc] && $::argc > 0 && [lindex $::argv 0] eq "all"} {
    run_cpu_suite
} elseif {[info exists ::argc] && $::argc > 0} {
    run_cpu_suite $::argv
} else {
    puts "CPU test helpers loaded. Try: run_cpu_test smoke"
    puts "Run the full suite with: run_cpu_suite"
}
