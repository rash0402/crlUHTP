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
const VERSION = v"0.2.0"

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
export ControlLoop, step!, run!, stop!, set_task!

# Export task types
export AbstractTask, TaskType
export TASK_TYPE_SOS, TASK_TYPE_CIT, TASK_TYPE_FITTS
export SoSTask, SoSConfig, DEFAULT_SOS_CONFIG
export CITTask, CITConfig, DEFAULT_CIT_CONFIG
export FittsTask, FittsConfig, DEFAULT_FITTS_CONFIG
export get_target, get_metrics, is_complete

# Include modules in dependency order
include("network/protocol.jl")
include("network/udp_sender.jl")
include("physics/dynamics.jl")
include("input/abstract.jl")
include("input/keyboard.jl")
include("input/auto_pd.jl")
include("tasks/abstract.jl")
include("tasks/sos.jl")
include("tasks/cit.jl")
include("tasks/fitts.jl")
include("core/state.jl")
include("core/loop.jl")

"""
    main(; duration=10.0, task="sos")

Main entry point for UHTP Julia Core.
"""
function main(; duration::Float64=10.0, task::String="sos")
    println("=" ^ 50)
    println("  UHTP - Unified HMI Tracking Platform")
    println("  Version: $VERSION")
    println("  Julia Core (1kHz Control Loop)")
    println("=" ^ 50)
    println()

    # Parse task type
    task_type = if lowercase(task) == "sos"
        TASK_TYPE_SOS
    elseif lowercase(task) == "cit"
        TASK_TYPE_CIT
    elseif lowercase(task) == "fitts"
        TASK_TYPE_FITTS
    else
        println("Unknown task: $task, using SoS")
        TASK_TYPE_SOS
    end

    # Create control loop with task
    config = default_config()
    loop = ControlLoop(config; task_type=task_type)

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
    task = "sos"

    for arg in ARGS
        if startswith(arg, "--duration=")
            duration = parse(Float64, split(arg, "=")[2])
        elseif startswith(arg, "--task=")
            task = String(split(arg, "=")[2])
        elseif arg == "--help" || arg == "-h"
            println("""
UHTP Julia Core

Usage: julia src/UHTP.jl [options]

Options:
  --duration=N     Run for N seconds (default: 10)
  --task=TYPE      Task type: sos, cit, fitts (default: sos)
  --help, -h       Show this help message

Tasks:
  sos    Sum-of-Sines tracking (frequency response analysis)
  cit    Critical Instability Task (control limit measurement)
  fitts  Fitts' Law Task (ballistic movement measurement)
            """)
            exit(0)
        end
    end

    return (duration=duration, task=task)
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    args = parse_args()
    main(; duration=args.duration, task=args.task)
end

end # module UHTP
