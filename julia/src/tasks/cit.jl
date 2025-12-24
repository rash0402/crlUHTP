"""
Critical Instability Task (CIT) for UHTP

Measures control limits using first-order unstable dynamics.
λ increases every step_interval until divergence.
"""

"""
CIT task configuration.
"""
struct CITConfig
    # Initial instability parameter (rad/s)
    lambda_start::Float64
    # Lambda increment (rad/s)
    lambda_step::Float64
    # Time between lambda increments (s)
    step_interval::Float64
    # Input gain
    input_gain::Float64
    # Divergence threshold (m)
    divergence_threshold::Float64
    # Maximum lambda before auto-stop
    lambda_max::Float64
end

# Default configuration from spec
const DEFAULT_CIT_CONFIG = CITConfig(
    0.5,   # λ starts at 0.5 rad/s
    0.2,   # Δλ = 0.2 rad/s
    30.0,  # Every 30 seconds
    1.0,   # K_u = 1.0
    0.08,  # c_max = 8cm
    10.0   # Max λ = 10 rad/s (safety limit)
)

"""
CIT state for first-order unstable dynamics.
Separate from physics State2D because CIT has its own dynamics.
"""
mutable struct CITState
    cx::Float64  # CIT X position
    cy::Float64  # CIT Y position
end

"""
Critical Instability Task.
"""
mutable struct CITTask <: AbstractTask
    config::CITConfig
    # Current lambda values
    lambda_x::Float64
    lambda_y::Float64
    # CIT-specific state (separate from physics)
    cit_state::CITState
    # Timing
    elapsed_time::Float64
    time_since_increment::Float64
    # Running state
    task_state::TaskState
    # Metrics
    divergence_time::Float64
    lambda_at_divergence::Float64
    increment_count::Int
end

"""
    CITTask(config=DEFAULT_CIT_CONFIG) -> CITTask

Create CIT task.
"""
function CITTask(config::CITConfig=DEFAULT_CIT_CONFIG)
    return CITTask(
        config,
        config.lambda_start,
        config.lambda_start,
        CITState(0.0, 0.0),
        0.0, 0.0,
        TASK_IDLE,
        0.0, 0.0, 0
    )
end

"""
    get_target(task::CITTask, t::Float64) -> (Float64, Float64)

CIT target is always the origin (stabilize at center).
"""
function get_target(task::CITTask, t::Float64)::Tuple{Float64, Float64}
    return (0.0, 0.0)
end

"""
    step_cit_dynamics!(task::CITTask, input::Input2D, dt::Float64)

Update CIT-specific first-order unstable dynamics.
ċ = λc + K_u·u
"""
function step_cit_dynamics!(task::CITTask, input::Input2D, dt::Float64)
    # First-order unstable dynamics (Euler integration)
    # ċx = λx·cx + Ku·ux
    dcx = task.lambda_x * task.cit_state.cx + task.config.input_gain * input.ux
    dcy = task.lambda_y * task.cit_state.cy + task.config.input_gain * input.uy

    task.cit_state.cx += dcx * dt
    task.cit_state.cy += dcy * dt
end

"""
    update!(task::CITTask, state::State2D, dt::Float64) -> TaskState

Update CIT task.
Note: For CIT, we use the CIT internal state, not the physics state.
The input should control the CIT dynamics.
"""
function update!(task::CITTask, state::State2D, dt::Float64)::TaskState
    if task.task_state == TASK_IDLE
        task.task_state = TASK_RUNNING
        task.elapsed_time = 0.0
        task.time_since_increment = 0.0
        task.cit_state.cx = 0.0
        task.cit_state.cy = 0.0
        task.lambda_x = task.config.lambda_start
        task.lambda_y = task.config.lambda_start
        task.increment_count = 0
    end

    if task.task_state == TASK_RUNNING
        task.elapsed_time += dt
        task.time_since_increment += dt

        # Check for lambda increment
        if task.time_since_increment >= task.config.step_interval
            task.lambda_x += task.config.lambda_step
            task.lambda_y += task.config.lambda_step
            task.time_since_increment = 0.0
            task.increment_count += 1

            # Check max lambda
            if task.lambda_x >= task.config.lambda_max
                task.task_state = TASK_COMPLETED
                task.divergence_time = task.elapsed_time
                task.lambda_at_divergence = task.lambda_x
            end
        end

        # Check for divergence
        distance = sqrt(task.cit_state.cx^2 + task.cit_state.cy^2)
        if distance > task.config.divergence_threshold
            task.task_state = TASK_FAILED
            task.divergence_time = task.elapsed_time
            task.lambda_at_divergence = task.lambda_x
        end
    end

    return task.task_state
end

"""
    update_with_input!(task::CITTask, input::Input2D, dt::Float64) -> TaskState

Update CIT with input (for CIT-specific dynamics).
"""
function update_with_input!(task::CITTask, input::Input2D, dt::Float64)::TaskState
    if task.task_state == TASK_RUNNING
        step_cit_dynamics!(task, input, dt)
    end
    return update!(task, State2D(task.cit_state.cx, task.cit_state.cy, 0.0, 0.0), dt)
end

"""
    get_cit_state(task::CITTask) -> (Float64, Float64)

Get current CIT cursor position.
"""
function get_cit_state(task::CITTask)::Tuple{Float64, Float64}
    return (task.cit_state.cx, task.cit_state.cy)
end

function reset!(task::CITTask)
    task.elapsed_time = 0.0
    task.time_since_increment = 0.0
    task.task_state = TASK_IDLE
    task.cit_state.cx = 0.0
    task.cit_state.cy = 0.0
    task.lambda_x = task.config.lambda_start
    task.lambda_y = task.config.lambda_start
    task.divergence_time = 0.0
    task.lambda_at_divergence = 0.0
    task.increment_count = 0
end

function is_complete(task::CITTask)::Bool
    return task.task_state == TASK_COMPLETED || task.task_state == TASK_FAILED
end

function get_metrics(task::CITTask)
    return (
        task_type = :cit,
        duration = task.elapsed_time,
        lambda_critical = task.lambda_at_divergence,
        lambda_current = task.lambda_x,
        increment_count = task.increment_count,
        diverged = task.task_state == TASK_FAILED,
        final_distance = sqrt(task.cit_state.cx^2 + task.cit_state.cy^2)
    )
end
