"""
Fitts' Law Task (ISO 9241-9) for UHTP

Measures ballistic prediction and movement planning.
13 targets on circle, alternating between opposite sides.
"""

"""
Fitts task configuration.
"""
struct FittsConfig
    # Number of targets on circle
    num_targets::Int
    # Circle radius (m)
    radius::Float64
    # Target width/diameter (m)
    target_width::Float64
    # Dwell time for success (s)
    dwell_time::Float64
    # Number of movements per trial
    movements_per_trial::Int
end

# Default configuration from spec
const DEFAULT_FITTS_CONFIG = FittsConfig(
    13,    # N = 13 targets
    0.08,  # R = 80mm radius
    0.008, # W = 8mm target width
    0.1,   # 100ms dwell time
    26     # 26 movements (each target twice, circular)
)

"""
Fitts' Law Task.
"""
mutable struct FittsTask <: AbstractTask
    config::FittsConfig
    # Target positions (pre-computed)
    targets::Vector{Tuple{Float64, Float64}}
    # Current target index
    current_target::Int
    # Movement sequence (indices into targets)
    sequence::Vector{Int}
    # Current movement in sequence
    current_movement::Int
    # Timing
    elapsed_time::Float64
    dwell_timer::Float64
    movement_start_time::Float64
    # Running state
    task_state::TaskState
    # Per-movement metrics
    movement_times::Vector{Float64}
    movement_errors::Vector{Bool}
    # Inside target flag
    inside_target::Bool
end

"""
    FittsTask(config=DEFAULT_FITTS_CONFIG) -> FittsTask

Create Fitts' Law task.
"""
function FittsTask(config::FittsConfig=DEFAULT_FITTS_CONFIG)
    # Pre-compute target positions on circle
    targets = Vector{Tuple{Float64, Float64}}(undef, config.num_targets)
    for i in 1:config.num_targets
        angle = 2π * (i - 1) / config.num_targets - π/2  # Start at top
        x = config.radius * cos(angle)
        y = config.radius * sin(angle)
        targets[i] = (x, y)
    end

    # Create alternating sequence (opposite targets)
    # For 13 targets: 1, 8, 2, 9, 3, 10, ... (skip by ~half)
    sequence = Int[]
    skip = config.num_targets ÷ 2 + 1  # 7 for 13 targets
    current = 1
    for _ in 1:config.movements_per_trial
        push!(sequence, current)
        current = mod1(current + skip, config.num_targets)
    end

    return FittsTask(
        config,
        targets,
        1,
        sequence,
        1,
        0.0, 0.0, 0.0,
        TASK_IDLE,
        Float64[],
        Bool[],
        false
    )
end

"""
    get_target(task::FittsTask, t::Float64) -> (Float64, Float64)

Get current target position.
"""
function get_target(task::FittsTask, t::Float64)::Tuple{Float64, Float64}
    if task.current_movement <= length(task.sequence)
        target_idx = task.sequence[task.current_movement]
        return task.targets[target_idx]
    else
        return (0.0, 0.0)
    end
end

"""
    is_inside_target(task::FittsTask, cx::Float64, cy::Float64) -> Bool

Check if cursor is inside current target.
"""
function is_inside_target(task::FittsTask, cx::Float64, cy::Float64)::Bool
    if task.current_movement > length(task.sequence)
        return false
    end

    tx, ty = get_target(task, 0.0)
    distance = sqrt((cx - tx)^2 + (cy - ty)^2)
    return distance <= task.config.target_width / 2
end

"""
    update!(task::FittsTask, state::State2D, dt::Float64) -> TaskState

Update Fitts task - check target acquisition.
"""
function update!(task::FittsTask, state::State2D, dt::Float64)::TaskState
    if task.task_state == TASK_IDLE
        task.task_state = TASK_RUNNING
        task.elapsed_time = 0.0
        task.current_movement = 1
        task.dwell_timer = 0.0
        task.movement_start_time = 0.0
        task.inside_target = false
        empty!(task.movement_times)
        empty!(task.movement_errors)
    end

    if task.task_state == TASK_RUNNING
        task.elapsed_time += dt

        # Check if inside target
        inside = is_inside_target(task, state.cx, state.cy)

        if inside
            if !task.inside_target
                # Just entered target
                task.inside_target = true
                task.dwell_timer = 0.0
            else
                # Accumulate dwell time
                task.dwell_timer += dt
            end

            # Check for successful acquisition
            if task.dwell_timer >= task.config.dwell_time
                # Record movement time
                mt = task.elapsed_time - task.movement_start_time
                push!(task.movement_times, mt)
                push!(task.movement_errors, false)

                # Move to next target
                task.current_movement += 1
                task.movement_start_time = task.elapsed_time
                task.dwell_timer = 0.0
                task.inside_target = false

                # Check completion
                if task.current_movement > length(task.sequence)
                    task.task_state = TASK_COMPLETED
                end
            end
        else
            # Outside target
            if task.inside_target
                # Just exited - reset dwell timer
                task.dwell_timer = 0.0
            end
            task.inside_target = false
        end
    end

    return task.task_state
end

function reset!(task::FittsTask)
    task.elapsed_time = 0.0
    task.task_state = TASK_IDLE
    task.current_movement = 1
    task.dwell_timer = 0.0
    task.movement_start_time = 0.0
    task.inside_target = false
    empty!(task.movement_times)
    empty!(task.movement_errors)
end

function is_complete(task::FittsTask)::Bool
    return task.task_state == TASK_COMPLETED
end

"""
    compute_fitts_metrics(task::FittsTask) -> NamedTuple

Compute Fitts' Law metrics.
"""
function compute_fitts_metrics(task::FittsTask)
    # Distance between opposite targets
    D = 2 * task.config.radius * sin(π * (task.config.num_targets ÷ 2 + 1) / task.config.num_targets)
    W = task.config.target_width

    # Index of Difficulty
    ID = log2(D / W + 1)

    # Movement times
    if isempty(task.movement_times)
        mean_mt = 0.0
        throughput = 0.0
    else
        mean_mt = sum(task.movement_times) / length(task.movement_times)
        throughput = ID / mean_mt  # bits/s
    end

    # Error rate
    error_count = count(task.movement_errors)
    error_rate = length(task.movement_errors) > 0 ? error_count / length(task.movement_errors) : 0.0

    return (
        ID = ID,
        mean_movement_time = mean_mt,
        throughput = throughput,
        error_rate = error_rate,
        movements_completed = length(task.movement_times)
    )
end

function get_metrics(task::FittsTask)
    fitts = compute_fitts_metrics(task)

    return (
        task_type = :fitts,
        duration = task.elapsed_time,
        ID = fitts.ID,
        mean_movement_time = fitts.mean_movement_time,
        throughput = fitts.throughput,
        error_rate = fitts.error_rate,
        movements_completed = fitts.movements_completed,
        movements_total = length(task.sequence)
    )
end
