"""
Abstract Task Interface for UHTP

All experiment tasks must implement this interface.
"""

"""
Abstract type for experiment tasks.
"""
abstract type AbstractTask end

"""
Task type enumeration.
"""
@enum TaskType::UInt8 begin
    TASK_TYPE_SOS = 1
    TASK_TYPE_CIT = 2
    TASK_TYPE_FITTS = 3
end

"""
    get_target(task::AbstractTask, t::Float64) -> (Float64, Float64)

Get target position (x, y) at time t.
"""
function get_target(task::AbstractTask, t::Float64)::Tuple{Float64, Float64}
    error("get_target not implemented for $(typeof(task))")
end

"""
    update!(task::AbstractTask, state::State2D, dt::Float64) -> TaskState

Update task state and return current task status.
"""
function update!(task::AbstractTask, state::State2D, dt::Float64)::TaskState
    error("update! not implemented for $(typeof(task))")
end

"""
    reset!(task::AbstractTask)

Reset task to initial state.
"""
function reset!(task::AbstractTask)
    # Default: do nothing
end

"""
    is_complete(task::AbstractTask) -> Bool

Check if task is complete.
"""
function is_complete(task::AbstractTask)::Bool
    return false
end

"""
    get_metrics(task::AbstractTask) -> NamedTuple

Get task-specific performance metrics.
"""
function get_metrics(task::AbstractTask)
    return (;)
end
