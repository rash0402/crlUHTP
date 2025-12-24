"""
Sum-of-Sines (SoS) Tracking Task for UHTP

Frequency response analysis using prime-multiple frequencies.
X and Y axes use different frequency sets.
"""

using Random

"""
SoS task configuration.
"""
struct SoSConfig
    # X-axis frequencies (Hz) - prime multiples
    freqs_x::Vector{Float64}
    # Y-axis frequencies (Hz) - different prime multiples
    freqs_y::Vector{Float64}
    # Base amplitude (m)
    base_amplitude::Float64
    # Duration (s)
    duration::Float64
end

# Default configuration from spec
const DEFAULT_SOS_CONFIG = SoSConfig(
    [0.1, 0.23, 0.37, 0.61, 1.03, 1.61],  # X-axis frequencies
    [0.13, 0.29, 0.43, 0.71, 1.13, 1.73], # Y-axis frequencies
    0.05,  # 5cm base amplitude
    60.0   # 60 seconds duration
)

"""
SoS tracking task.
"""
mutable struct SoSTask <: AbstractTask
    config::SoSConfig
    # Amplitudes (scaled by 1/f)
    amps_x::Vector{Float64}
    amps_y::Vector{Float64}
    # Random phases
    phases_x::Vector{Float64}
    phases_y::Vector{Float64}
    # Current time
    elapsed_time::Float64
    # Running state
    task_state::TaskState
    # Metrics
    error_sum_x::Float64
    error_sum_y::Float64
    sample_count::Int
end

"""
    SoSTask(config=DEFAULT_SOS_CONFIG; seed=nothing) -> SoSTask

Create SoS tracking task.
"""
function SoSTask(config::SoSConfig=DEFAULT_SOS_CONFIG; seed::Union{Int,Nothing}=nothing)
    rng = isnothing(seed) ? MersenneTwister() : MersenneTwister(seed)

    # Compute amplitudes (1/f scaling for low-frequency emphasis)
    amps_x = [config.base_amplitude / f for f in config.freqs_x]
    amps_y = [config.base_amplitude / f for f in config.freqs_y]

    # Random phases
    phases_x = 2π .* rand(rng, length(config.freqs_x))
    phases_y = 2π .* rand(rng, length(config.freqs_y))

    return SoSTask(
        config,
        amps_x, amps_y,
        phases_x, phases_y,
        0.0,
        TASK_IDLE,
        0.0, 0.0, 0
    )
end

"""
    get_target(task::SoSTask, t::Float64) -> (Float64, Float64)

Compute target position at time t using sum of sines.
"""
function get_target(task::SoSTask, t::Float64)::Tuple{Float64, Float64}
    # X-axis: sum of sines
    tx = 0.0
    for i in eachindex(task.config.freqs_x)
        tx += task.amps_x[i] * sin(2π * task.config.freqs_x[i] * t + task.phases_x[i])
    end

    # Y-axis: sum of sines
    ty = 0.0
    for j in eachindex(task.config.freqs_y)
        ty += task.amps_y[j] * sin(2π * task.config.freqs_y[j] * t + task.phases_y[j])
    end

    return (tx, ty)
end

"""
    update!(task::SoSTask, state::State2D, dt::Float64) -> TaskState

Update task state and compute metrics.
"""
function update!(task::SoSTask, state::State2D, dt::Float64)::TaskState
    if task.task_state == TASK_IDLE
        task.task_state = TASK_RUNNING
        task.elapsed_time = 0.0
        task.error_sum_x = 0.0
        task.error_sum_y = 0.0
        task.sample_count = 0
    end

    if task.task_state == TASK_RUNNING
        task.elapsed_time += dt

        # Get target
        tx, ty = get_target(task, task.elapsed_time)

        # Compute error
        ex = state.cx - tx
        ey = state.cy - ty

        # Accumulate for RMSE
        task.error_sum_x += ex^2
        task.error_sum_y += ey^2
        task.sample_count += 1

        # Check completion
        if task.elapsed_time >= task.config.duration
            task.task_state = TASK_COMPLETED
        end
    end

    return task.task_state
end

function reset!(task::SoSTask)
    task.elapsed_time = 0.0
    task.task_state = TASK_IDLE
    task.error_sum_x = 0.0
    task.error_sum_y = 0.0
    task.sample_count = 0

    # Regenerate random phases
    rng = MersenneTwister()
    task.phases_x .= 2π .* rand(rng, length(task.phases_x))
    task.phases_y .= 2π .* rand(rng, length(task.phases_y))
end

function is_complete(task::SoSTask)::Bool
    return task.task_state == TASK_COMPLETED
end

function get_metrics(task::SoSTask)
    n = max(task.sample_count, 1)
    rmse_x = sqrt(task.error_sum_x / n)
    rmse_y = sqrt(task.error_sum_y / n)
    rmse_total = sqrt((task.error_sum_x + task.error_sum_y) / n)

    return (
        task_type = :sos,
        duration = task.elapsed_time,
        rmse_x = rmse_x,
        rmse_y = rmse_y,
        rmse_total = rmse_total,
        sample_count = task.sample_count
    )
end
