"""
UHTP - Unified HMI Tracking Platform

Julia Core Process for 1kHz real-time control.
"""
module UHTP

using StaticArrays
using Sockets
using YAML
using Random

# Version
const VERSION = v"0.1.0"

# Export core types and functions
export TaskState, TASK_IDLE, TASK_RUNNING, TASK_PAUSED, TASK_COMPLETED, TASK_FAILED
export UDPMessage, MESSAGE_SIZE, create_message, serialize_message!
export UDPSender, send!, stats
export State2D, Input2D, ZERO_STATE, ZERO_INPUT
export AxisParams, PhysicsParams, DEFAULT_PARAMS
export step_rk4, step_euler, compute_acceleration
export AbstractInputDevice, DeviceType
export KeyboardDevice, AutoPDDevice, AutoPDParams, DEFAULT_AUTO_PD
export set_target!, compute_input
export ExperimentConfig, ExperimentState, default_config
export ControlLoop, step!, run!, stop!

# Include modules in dependency order
include("network/protocol.jl")
include("network/udp_sender.jl")
include("physics/dynamics.jl")
include("input/abstract.jl")
include("input/keyboard.jl")
include("input/auto_pd.jl")
include("core/state.jl")
include("core/loop.jl")

"""
    main(; duration=10.0, demo_mode=false)

Main entry point for UHTP Julia Core.
"""
function main(; duration::Float64=10.0, demo_mode::Bool=false)
    println("=" ^ 50)
    println("  UHTP - Unified HMI Tracking Platform")
    println("  Version: $VERSION")
    println("  Julia Core (1kHz Control Loop)")
    println("=" ^ 50)
    println()

    # Create control loop
    config = default_config()
    loop = ControlLoop(config)

    if demo_mode
        # Demo mode: moving target
        println("Demo mode: Auto-PD tracking moving target")
        loop.state.target_x = 0.05  # 5cm offset
        loop.state.target_y = 0.0
    end

    try
        # Run control loop
        run!(loop, duration)
    finally
        close!(loop)
    end

    println("\nUHTP Julia Core stopped.")
end

# Handle command line arguments
function parse_args()
    duration = 10.0
    demo_mode = false

    for arg in ARGS
        if startswith(arg, "--duration=")
            duration = parse(Float64, split(arg, "=")[2])
        elseif arg == "--demo"
            demo_mode = true
        elseif arg == "--help" || arg == "-h"
            println("""
UHTP Julia Core

Usage: julia src/UHTP.jl [options]

Options:
  --duration=N  Run for N seconds (default: 10)
  --demo        Demo mode with moving target
  --help, -h    Show this help message
            """)
            exit(0)
        end
    end

    return (duration=duration, demo_mode=demo_mode)
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    args = parse_args()
    main(; duration=args.duration, demo_mode=args.demo_mode)
end

end # module UHTP
