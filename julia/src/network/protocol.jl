"""
UDP Message Protocol for UHTP

Binary format (little-endian, 64 bytes total):
- timestamp_us: Float64 (8 bytes)
- cursor_x: Float64 (8 bytes)
- cursor_y: Float64 (8 bytes)
- cursor_vx: Float64 (8 bytes)
- cursor_vy: Float64 (8 bytes)
- target_x: Float64 (8 bytes)
- target_y: Float64 (8 bytes)
- task_state: UInt32 (4 bytes)
- trial_number: UInt32 (4 bytes)
"""

# Task state enumeration
@enum TaskState::UInt32 begin
    TASK_IDLE = 0
    TASK_RUNNING = 1
    TASK_PAUSED = 2
    TASK_COMPLETED = 3
    TASK_FAILED = 4
end

"""
UDP message structure (64 bytes, cache-line aligned)
"""
struct UDPMessage
    timestamp_us::Float64
    cursor_x::Float64
    cursor_y::Float64
    cursor_vx::Float64
    cursor_vy::Float64
    target_x::Float64
    target_y::Float64
    task_state::UInt32
    trial_number::UInt32
end

# Message size constant
const MESSAGE_SIZE = 64

"""
    serialize_message(msg::UDPMessage) -> Vector{UInt8}

Serialize UDPMessage to bytes (little-endian).
Zero-allocation version uses pre-allocated buffer.
"""
function serialize_message!(buffer::Vector{UInt8}, msg::UDPMessage)
    @assert length(buffer) >= MESSAGE_SIZE "Buffer too small"

    # Use reinterpret for zero-copy serialization
    ptr = pointer(buffer)
    unsafe_store!(Ptr{Float64}(ptr), msg.timestamp_us)
    unsafe_store!(Ptr{Float64}(ptr + 8), msg.cursor_x)
    unsafe_store!(Ptr{Float64}(ptr + 16), msg.cursor_y)
    unsafe_store!(Ptr{Float64}(ptr + 24), msg.cursor_vx)
    unsafe_store!(Ptr{Float64}(ptr + 32), msg.cursor_vy)
    unsafe_store!(Ptr{Float64}(ptr + 40), msg.target_x)
    unsafe_store!(Ptr{Float64}(ptr + 48), msg.target_y)
    unsafe_store!(Ptr{UInt32}(ptr + 56), msg.task_state)
    unsafe_store!(Ptr{UInt32}(ptr + 60), msg.trial_number)

    return buffer
end

"""
    create_message(state, target, task_state, trial) -> UDPMessage

Create a UDP message from current state.
"""
function create_message(
    timestamp_us::Float64,
    cursor_x::Float64, cursor_y::Float64,
    cursor_vx::Float64, cursor_vy::Float64,
    target_x::Float64, target_y::Float64,
    task_state::TaskState,
    trial_number::UInt32
)
    return UDPMessage(
        timestamp_us,
        cursor_x, cursor_y,
        cursor_vx, cursor_vy,
        target_x, target_y,
        UInt32(task_state),
        trial_number
    )
end
