"""
2D Second-Order Dynamics for UHTP

XY-independent dynamics:
  Mx*c̈x + Bx*ċx + Kx*cx = uhx + usysx + wx  (X-axis)
  My*c̈y + By*ċy + Ky*cy = uhy + usysy + wy  (Y-axis)

State vector: [cx, cy, vx, vy]ᵀ ∈ ℝ⁴
"""

using StaticArrays

"""
Physics parameters for one axis.
"""
struct AxisParams
    M::Float64  # Mass [kg]
    B::Float64  # Damping [Ns/m]
    K::Float64  # Stiffness [N/m]
end

"""
Physics parameters for 2D dynamics.
"""
struct PhysicsParams
    x::AxisParams
    y::AxisParams
end

# Default parameters
const DEFAULT_PARAMS = PhysicsParams(
    AxisParams(1.0, 5.0, 0.0),  # X-axis: M=1kg, B=5Ns/m, K=0
    AxisParams(1.0, 5.0, 0.0)   # Y-axis: M=1kg, B=5Ns/m, K=0
)

"""
2D State: position and velocity for X and Y axes.
Uses StaticArrays for zero-allocation.
"""
struct State2D
    cx::Float64  # X position [m]
    cy::Float64  # Y position [m]
    vx::Float64  # X velocity [m/s]
    vy::Float64  # Y velocity [m/s]
end

# Zero state
const ZERO_STATE = State2D(0.0, 0.0, 0.0, 0.0)

"""
2D Input force.
"""
struct Input2D
    ux::Float64  # X force [N]
    uy::Float64  # Y force [N]
end

const ZERO_INPUT = Input2D(0.0, 0.0)

"""
    compute_acceleration(axis::AxisParams, c, v, u) -> Float64

Compute acceleration for one axis.
  a = (u - B*v - K*c) / M
"""
@inline function compute_acceleration(axis::AxisParams, c::Float64, v::Float64, u::Float64)::Float64
    return (u - axis.B * v - axis.K * c) / axis.M
end

"""
    step_rk4(state::State2D, params::PhysicsParams, input::Input2D, dt::Float64) -> State2D

Advance state by dt using RK4 integration.
Zero-allocation implementation.
"""
function step_rk4(state::State2D, params::PhysicsParams, input::Input2D, dt::Float64)::State2D
    # Current state
    cx, cy, vx, vy = state.cx, state.cy, state.vx, state.vy
    ux, uy = input.ux, input.uy

    # RK4 for X-axis
    ax1 = compute_acceleration(params.x, cx, vx, ux)
    vx1 = vx
    ax2 = compute_acceleration(params.x, cx + 0.5*dt*vx1, vx + 0.5*dt*ax1, ux)
    vx2 = vx + 0.5*dt*ax1
    ax3 = compute_acceleration(params.x, cx + 0.5*dt*vx2, vx + 0.5*dt*ax2, ux)
    vx3 = vx + 0.5*dt*ax2
    ax4 = compute_acceleration(params.x, cx + dt*vx3, vx + dt*ax3, ux)
    vx4 = vx + dt*ax3

    new_cx = cx + dt/6.0 * (vx1 + 2*vx2 + 2*vx3 + vx4)
    new_vx = vx + dt/6.0 * (ax1 + 2*ax2 + 2*ax3 + ax4)

    # RK4 for Y-axis
    ay1 = compute_acceleration(params.y, cy, vy, uy)
    vy1 = vy
    ay2 = compute_acceleration(params.y, cy + 0.5*dt*vy1, vy + 0.5*dt*ay1, uy)
    vy2 = vy + 0.5*dt*ay1
    ay3 = compute_acceleration(params.y, cy + 0.5*dt*vy2, vy + 0.5*dt*ay2, uy)
    vy3 = vy + 0.5*dt*ay2
    ay4 = compute_acceleration(params.y, cy + dt*vy3, vy + dt*ay3, uy)
    vy4 = vy + dt*ay3

    new_cy = cy + dt/6.0 * (vy1 + 2*vy2 + 2*vy3 + vy4)
    new_vy = vy + dt/6.0 * (ay1 + 2*ay2 + 2*ay3 + ay4)

    return State2D(new_cx, new_cy, new_vx, new_vy)
end

"""
    step_euler(state::State2D, params::PhysicsParams, input::Input2D, dt::Float64) -> State2D

Advance state by dt using Euler integration (faster but less accurate).
"""
function step_euler(state::State2D, params::PhysicsParams, input::Input2D, dt::Float64)::State2D
    ax = compute_acceleration(params.x, state.cx, state.vx, input.ux)
    ay = compute_acceleration(params.y, state.cy, state.vy, input.uy)

    new_vx = state.vx + dt * ax
    new_vy = state.vy + dt * ay
    new_cx = state.cx + dt * state.vx
    new_cy = state.cy + dt * state.vy

    return State2D(new_cx, new_cy, new_vx, new_vy)
end
