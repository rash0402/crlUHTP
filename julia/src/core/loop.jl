"""
Main Control Loop for UHTP

1kHz real-time control loop with zero-allocation design.
"""

"""
Control loop context.
"""
mutable struct ControlLoop
    config::ExperimentConfig
    state::ExperimentState
    sender::UDPSender
    auto_pd::AutoPDDevice

    # Performance metrics
    loop_times_us::Vector{Float64}
    max_loop_time_us::Float64
    overrun_count::UInt64
end

"""
    ControlLoop(config=default_config()) -> ControlLoop

Create control loop with configuration.
"""
function ControlLoop(config::ExperimentConfig=default_config())
    sender = UDPSender(config.udp_dest_ip, config.udp_dest_port)
    state = ExperimentState()
    auto_pd = AutoPDDevice()

    return ControlLoop(
        config,
        state,
        sender,
        auto_pd,
        Float64[],
        0.0,
        0
    )
end

"""
    step!(loop::ControlLoop) -> Nothing

Execute one control loop iteration.
"""
function step!(loop::ControlLoop)
    t_start = time_ns()

    # 1. Update timing
    update_time!(loop.state)
    loop.state.loop_count += 1

    # 2. Get input (Auto-PD for now)
    set_target!(loop.auto_pd, loop.state.target_x, loop.state.target_y)
    input = compute_input(loop.auto_pd, loop.state.cursor)
    loop.state.last_input = input

    # 3. Physics update
    loop.state.cursor = step_rk4(
        loop.state.cursor,
        loop.config.physics,
        input,
        loop.config.dt
    )

    # 4. Send UDP message
    msg = to_message(loop.state)
    send!(loop.sender, msg)

    # 5. Performance tracking
    t_end = time_ns()
    loop_time_us = (t_end - t_start) / 1000.0
    loop.max_loop_time_us = max(loop.max_loop_time_us, loop_time_us)

    if length(loop.loop_times_us) < 10000
        push!(loop.loop_times_us, loop_time_us)
    end

    # Check for overrun (> 900μs is risky for 1ms loop)
    if loop_time_us > 900.0
        loop.overrun_count += 1
    end

    return nothing
end

"""
    run!(loop::ControlLoop, duration_s::Float64)

Run control loop for specified duration.
"""
function run!(loop::ControlLoop, duration_s::Float64)
    reset!(loop.state)
    loop.state.running = true
    loop.state.task_state = TASK_RUNNING
    loop.state.trial_number = 1

    target_dt_ns = round(UInt64, loop.config.dt * 1e9)
    end_time_ns = time_ns() + round(UInt64, duration_s * 1e9)

    println("Starting control loop at $(loop.config.control_rate_hz) Hz...")
    println("Duration: $(duration_s) s")
    println("Press Ctrl+C to stop")

    try
        while loop.state.running && time_ns() < end_time_ns
            t_loop_start = time_ns()

            # Execute one step
            step!(loop)

            # Wait for next period
            elapsed_ns = time_ns() - t_loop_start
            if elapsed_ns < target_dt_ns
                sleep_ns = target_dt_ns - elapsed_ns
                # Busy wait for precision (sleep() is too coarse)
                while time_ns() - t_loop_start < target_dt_ns
                    # Spin
                end
            end
        end
    catch e
        if isa(e, InterruptException)
            println("\nInterrupted by user")
        else
            rethrow(e)
        end
    finally
        loop.state.running = false
        loop.state.task_state = TASK_COMPLETED
    end

    # Print statistics
    print_stats(loop)
end

"""
    print_stats(loop::ControlLoop)

Print loop performance statistics.
"""
function print_stats(loop::ControlLoop)
    println("\n" * "=" ^ 50)
    println("  Control Loop Statistics")
    println("=" ^ 50)
    println("Total loops: $(loop.state.loop_count)")
    println("Max loop time: $(round(loop.max_loop_time_us, digits=1)) μs")

    if !isempty(loop.loop_times_us)
        mean_time = sum(loop.loop_times_us) / length(loop.loop_times_us)
        sorted = sort(loop.loop_times_us)
        p99 = sorted[min(length(sorted), round(Int, 0.99 * length(sorted)))]
        println("Mean loop time: $(round(mean_time, digits=1)) μs")
        println("99th percentile: $(round(p99, digits=1)) μs")
    end

    println("Overruns (>900μs): $(loop.overrun_count)")

    s = stats(loop.sender)
    println("UDP packets sent: $(s.send_count)")
    println("UDP errors: $(s.error_count)")
end

"""
    stop!(loop::ControlLoop)

Stop the control loop.
"""
function stop!(loop::ControlLoop)
    loop.state.running = false
end

"""
    close!(loop::ControlLoop)

Close all resources.
"""
function close!(loop::ControlLoop)
    close!(loop.sender)
end
