"""
Auto-PD Input Device for UHTP

Automatic PD controller with configurable noise.
Useful for system testing and baseline measurements.
"""

using Random

"""
Auto-PD controller parameters.
"""
struct AutoPDParams
    Kp::Float64  # Proportional gain
    Kd::Float64  # Derivative gain
    noise_std::Float64  # Noise standard deviation [N]
end

const DEFAULT_AUTO_PD = AutoPDParams(10.0, 5.0, 0.1)

"""
Auto-PD input device.
Generates PD control + noise based on error from target.
"""
mutable struct AutoPDDevice <: AbstractInputDevice
    params::AutoPDParams
    rng::MersenneTwister
    target_x::Float64
    target_y::Float64
end

"""
    AutoPDDevice(params=DEFAULT_AUTO_PD, seed=nothing) -> AutoPDDevice

Create Auto-PD input device.
"""
function AutoPDDevice(params::AutoPDParams=DEFAULT_AUTO_PD; seed::Union{Int,Nothing}=nothing)
    rng = isnothing(seed) ? MersenneTwister() : MersenneTwister(seed)
    return AutoPDDevice(params, rng, 0.0, 0.0)
end

"""
    set_target!(device::AutoPDDevice, tx, ty)

Set target position for PD controller.
"""
function set_target!(device::AutoPDDevice, tx::Float64, ty::Float64)
    device.target_x = tx
    device.target_y = ty
end

"""
    compute_input(device::AutoPDDevice, state::State2D) -> Input2D

Compute PD control input based on current state and target.
"""
function compute_input(device::AutoPDDevice, state::State2D)::Input2D
    p = device.params

    # Position error
    ex = device.target_x - state.cx
    ey = device.target_y - state.cy

    # Velocity (derivative of error, assuming target is stationary)
    vx = -state.vx
    vy = -state.vy

    # PD control
    ux = p.Kp * ex + p.Kd * vx
    uy = p.Kp * ey + p.Kd * vy

    # Add noise
    if p.noise_std > 0
        ux += p.noise_std * randn(device.rng)
        uy += p.noise_std * randn(device.rng)
    end

    return Input2D(ux, uy)
end

# For compatibility with AbstractInputDevice interface
function read_input(device::AutoPDDevice)::Input2D
    # This requires state, so return zero
    # Use compute_input(device, state) instead
    return ZERO_INPUT
end

function reset!(device::AutoPDDevice)
    device.target_x = 0.0
    device.target_y = 0.0
end
