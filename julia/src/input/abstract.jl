"""
Abstract Input Device Interface for UHTP

All input devices must implement this interface.
"""

"""
Abstract type for input devices.
"""
abstract type AbstractInputDevice end

"""
Device types enumeration.
"""
@enum DeviceType::UInt8 begin
    DEVICE_MOUSE = 1
    DEVICE_KEYBOARD = 2
    DEVICE_TRACKPAD = 3
    DEVICE_AUTO_PD = 4
    DEVICE_UDP_HAPTIC = 5
end

"""
    read_input(device::AbstractInputDevice) -> Input2D

Read current input from device.
"""
function read_input(device::AbstractInputDevice)::Input2D
    error("read_input not implemented for $(typeof(device))")
end

"""
    reset!(device::AbstractInputDevice)

Reset device state.
"""
function reset!(device::AbstractInputDevice)
    # Default: do nothing
end

"""
    close!(device::AbstractInputDevice)

Close device and release resources.
"""
function close!(device::AbstractInputDevice)
    # Default: do nothing
end
