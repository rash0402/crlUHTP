"""
Main Control Loop for UHTP

1kHz real-time control loop with zero-allocation design.
Supports SoS, CIT, and Fitts tasks.
"""

"""
Control loop context.
"""
mutable struct ControlLoop
    config::ExperimentConfig
    state::ExperimentState
    sender::UDPSender
    auto_pd::AutoPDDevice

    # Current task (Union for flexibility)
    current_task::Union{SoSTask, CITTask, FittsTask, Nothing}
    task_type::TaskType

    # Performance metrics
    loop_times_us::Vector{Float64}
    max_loop_time_us::Float64
    overrun_count::UInt64
end

"""
    ControlLoop(config=default_config(); task_type=TASK_TYPE_SOS) -> ControlLoop

Create control loop with configuration and task type.
"""
function ControlLoop(config::ExperimentConfig=default_config(); task_type::TaskType=TASK_TYPE_SOS)
    sender = UDPSender(config.udp_dest_ip, config.udp_dest_port)
    state = ExperimentState()
    auto_pd = AutoPDDevice()

    # Create task based on type
    task = create_task(task_type)

    return ControlLoop(
        config,
        state,
        sender,
        auto_pd,
        task,
        task_type,
        Float64[],
        0.0,
        0
    )
end

"""
    create_task(task_type::TaskType) -> AbstractTask

Create a task instance based on type.
"""
function create_task(task_type::TaskType)
    if task_type == TASK_TYPE_SOS
        return SoSTask()
    elseif task_type == TASK_TYPE_CIT
        return CITTask()
    elseif task_type == TASK_TYPE_FITTS
        return FittsTask()
    else
        return SoSTask()  # Default
    end
end

"""
    set_task!(loop::ControlLoop, task_type::TaskType)

Change current task.
"""
function set_task!(loop::ControlLoop, task_type::TaskType)
    loop.task_type = task_type
    loop.current_task = create_task(task_type)
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

    # 2. Get target from task
    if !isnothing(loop.current_task)
        t_sec = loop.state.current_time_us / 1e6
        tx, ty = get_target(loop.current_task, t_sec)
        loop.state.target_x = tx
        loop.state.target_y = ty
    end

    # 3. Get input
    if loop.task_type == TASK_TYPE_CIT && !isnothing(loop.current_task)
        # CIT: Input controls CIT dynamics directly
        set_target!(loop.auto_pd, 0.0, 0.0)  # Target is origin for CIT
        cit_task = loop.current_task::CITTask
        cit_cx, cit_cy = get_cit_state(cit_task)
        # Create pseudo-state for Auto-PD
        cit_state = State2D(cit_cx, cit_cy, 0.0, 0.0)
        input = compute_input(loop.auto_pd, cit_state)
        loop.state.last_input = input

        # Update CIT dynamics
        update_with_input!(cit_task, input, loop.config.dt)

        # Sync CIT state to main state for display
        loop.state.cursor = State2D(cit_cx, cit_cy, 0.0, 0.0)
    else
        # SoS/Fitts: Normal physics with Auto-PD tracking target
        set_target!(loop.auto_pd, loop.state.target_x, loop.state.target_y)
        input = compute_input(loop.auto_pd, loop.state.cursor)
        loop.state.last_input = input

        # Physics update
        loop.state.cursor = step_rk4(
            loop.state.cursor,
            loop.config.physics,
            input,
            loop.config.dt
        )
    end

    # 4. Update task state
    if !isnothing(loop.current_task)
        task_status = update!(loop.current_task, loop.state.cursor, loop.config.dt)
        loop.state.task_state = task_status
    end

    # 5. Send UDP message
    msg = to_message(loop.state)
    send!(loop.sender, msg)

    # 6. Performance tracking
    t_end = time_ns()
    loop_time_us = (t_end - t_start) / 1000.0
    loop.max_loop_time_us = max(loop.max_loop_time_us, loop_time_us)

    if length(loop.loop_times_us) < 10000
        push!(loop.loop_times_us, loop_time_us)
    end

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
    if !isnothing(loop.current_task)
        reset!(loop.current_task)
    end

    loop.state.running = true
    loop.state.task_state = TASK_RUNNING
    loop.state.trial_number = 1

    target_dt_ns = round(UInt64, loop.config.dt * 1e9)
    end_time_ns = time_ns() + round(UInt64, duration_s * 1e9)

    task_name = string(loop.task_type)
    println("Starting control loop at $(loop.config.control_rate_hz) Hz...")
    println("Task: $task_name")
    println("Duration: $(duration_s) s")
    println("Press Ctrl+C to stop")

    try
        while loop.state.running && time_ns() < end_time_ns
            t_loop_start = time_ns()

            # Execute one step
            step!(loop)

            # Check if task completed early
            if !isnothing(loop.current_task) && is_complete(loop.current_task)
                println("\nTask completed!")
                break
            end

            # Wait for next period (busy wait for precision)
            while time_ns() - t_loop_start < target_dt_ns
                # Spin
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
        if loop.state.task_state == TASK_RUNNING
            loop.state.task_state = TASK_COMPLETED
        end
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
    println("Task: $(loop.task_type)")
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

    # Print task metrics
    if !isnothing(loop.current_task)
        println("\n" * "-" ^ 50)
        println("  Task Metrics")
        println("-" ^ 50)
        metrics = get_metrics(loop.current_task)
        for (k, v) in pairs(metrics)
            if v isa Float64
                println("$k: $(round(v, digits=4))")
            else
                println("$k: $v")
            end
        end
    end
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
