"""
Keyboard Input Device for UHTP

Arrow keys provide discrete force input.
Uses UDP to receive key states from Python GUI.
"""

using Sockets

"""
Keyboard input device.
Receives key states via UDP from Python GUI.
"""
mutable struct KeyboardDevice <: AbstractInputDevice
    socket::UDPSocket
    port::UInt16
    force_magnitude::Float64
    # Current key states
    up::Bool
    down::Bool
    left::Bool
    right::Bool
    # Last received input
    last_input::Input2D
end

"""
    KeyboardDevice(port::Int=12346, force::Float64=1.0) -> KeyboardDevice

Create keyboard input device.
"""
function KeyboardDevice(port::Int=12346, force::Float64=1.0)
    socket = UDPSocket()
    bind(socket, ip"127.0.0.1", UInt16(port))

    return KeyboardDevice(
        socket,
        UInt16(port),
        force,
        false, false, false, false,
        ZERO_INPUT
    )
end

"""
    update!(device::KeyboardDevice)

Non-blocking update of key states from UDP.
Message format: 4 bytes (up, down, left, right) as UInt8 (0 or 1)
"""
function update!(device::KeyboardDevice)
    # Non-blocking receive
    while true
        try
            # Check if data available (non-blocking)
            if !isopen(device.socket)
                break
            end
            # Try to receive with timeout
            data = recv(device.socket)
            if length(data) >= 4
                device.up = data[1] != 0
                device.down = data[2] != 0
                device.left = data[3] != 0
                device.right = data[4] != 0
            end
        catch e
            if isa(e, Base.IOError)
                break
            end
            break
        end
    end
end

"""
    read_input(device::KeyboardDevice) -> Input2D

Convert current key states to force input.
"""
function read_input(device::KeyboardDevice)::Input2D
    ux = 0.0
    uy = 0.0
    f = device.force_magnitude

    if device.right
        ux += f
    end
    if device.left
        ux -= f
    end
    if device.up
        uy += f
    end
    if device.down
        uy -= f
    end

    device.last_input = Input2D(ux, uy)
    return device.last_input
end

function reset!(device::KeyboardDevice)
    device.up = false
    device.down = false
    device.left = false
    device.right = false
    device.last_input = ZERO_INPUT
end

function close!(device::KeyboardDevice)
    close(device.socket)
end
