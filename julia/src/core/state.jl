"""
State Management for UHTP

Manages experiment state, trial state, and timing.
"""

"""
Experiment configuration.
"""
struct ExperimentConfig
    control_rate_hz::Float64  # Control loop rate [Hz]
    dt::Float64               # Time step [s]
    physics::PhysicsParams    # Physics parameters
    udp_dest_ip::String       # UDP destination IP
    udp_dest_port::Int        # UDP destination port
end

"""
    default_config() -> ExperimentConfig

Create default experiment configuration.
"""
function default_config()
    return ExperimentConfig(
        1000.0,              # 1kHz control loop
        0.001,               # 1ms time step
        DEFAULT_PARAMS,      # Default physics
        "127.0.0.1",         # Localhost
        12345                # Default port
    )
end

"""
Mutable experiment state.
"""
mutable struct ExperimentState
    # Timing
    start_time_ns::UInt64
    current_time_us::Float64
    loop_count::UInt64

    # Physics state
    cursor::State2D

    # Target
    target_x::Float64
    target_y::Float64

    # Task state
    task_state::TaskState
    trial_number::UInt32

    # Input
    last_input::Input2D

    # Running flag
    running::Bool
end

"""
    ExperimentState() -> ExperimentState

Create initial experiment state.
"""
function ExperimentState()
    return ExperimentState(
        UInt64(0),
        0.0,
        UInt64(0),
        ZERO_STATE,
        0.0, 0.0,
        TASK_IDLE,
        UInt32(0),
        ZERO_INPUT,
        false
    )
end

"""
    reset!(state::ExperimentState)

Reset experiment state to initial values.
"""
function reset!(state::ExperimentState)
    state.start_time_ns = time_ns()
    state.current_time_us = 0.0
    state.loop_count = 0
    state.cursor = ZERO_STATE
    state.target_x = 0.0
    state.target_y = 0.0
    state.task_state = TASK_IDLE
    state.trial_number = 0
    state.last_input = ZERO_INPUT
end

"""
    update_time!(state::ExperimentState)

Update current time from system clock.
"""
function update_time!(state::ExperimentState)
    if state.start_time_ns == 0
        state.start_time_ns = time_ns()
    end
    elapsed_ns = time_ns() - state.start_time_ns
    state.current_time_us = elapsed_ns / 1000.0
end

"""
    to_message(state::ExperimentState) -> UDPMessage

Convert experiment state to UDP message.
"""
function to_message(state::ExperimentState)::UDPMessage
    return create_message(
        state.current_time_us,
        state.cursor.cx, state.cursor.cy,
        state.cursor.vx, state.cursor.vy,
        state.target_x, state.target_y,
        state.task_state,
        state.trial_number
    )
end
