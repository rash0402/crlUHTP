"""
UHTP - Unified HMI Tracking Platform

Julia Core Process for 1kHz real-time control.
"""
module UHTP

using StaticArrays
using Sockets
using YAML

# Version
const VERSION = v"0.1.0"

# Placeholder for future modules
# include("physics/dynamics.jl")
# include("input/abstract.jl")
# include("tasks/abstract.jl")
# include("network/udp_sender.jl")
# include("core/loop.jl")

function main()
    println("=" ^ 50)
    println("  UHTP - Unified HMI Tracking Platform")
    println("  Version: $VERSION")
    println("=" ^ 50)
    println()
    println("Status: Placeholder - Implementation pending")
    println()
    println("Press Ctrl+C to exit...")

    # Keep running until interrupted
    try
        while true
            sleep(1)
        end
    catch e
        if isa(e, InterruptException)
            println("\nShutting down UHTP...")
        else
            rethrow(e)
        end
    end
end

# Run main if executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

end # module UHTP
