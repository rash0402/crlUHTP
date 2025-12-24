"""
UDP Sender for UHTP

Sends state updates to Python Viewer at 1kHz.
"""

using Sockets

"""
UDP Sender with pre-allocated buffer for zero-allocation sends.
"""
mutable struct UDPSender
    socket::UDPSocket
    dest_ip::IPv4
    dest_port::UInt16
    buffer::Vector{UInt8}
    send_count::UInt64
    error_count::UInt64
end

"""
    UDPSender(dest_ip::String, dest_port::Int) -> UDPSender

Create a new UDP sender.
"""
function UDPSender(dest_ip::String="127.0.0.1", dest_port::Int=12345)
    socket = UDPSocket()
    buffer = zeros(UInt8, MESSAGE_SIZE)

    return UDPSender(
        socket,
        IPv4(dest_ip),
        UInt16(dest_port),
        buffer,
        UInt64(0),
        UInt64(0)
    )
end

"""
    send!(sender::UDPSender, msg::UDPMessage) -> Bool

Send a UDP message. Returns true on success.
Zero-allocation after warmup.
"""
function send!(sender::UDPSender, msg::UDPMessage)::Bool
    try
        serialize_message!(sender.buffer, msg)
        Sockets.send(sender.socket, sender.dest_ip, sender.dest_port, sender.buffer)
        sender.send_count += 1
        return true
    catch e
        sender.error_count += 1
        return false
    end
end

"""
    close!(sender::UDPSender)

Close the UDP socket.
"""
function close!(sender::UDPSender)
    close(sender.socket)
end

"""
    stats(sender::UDPSender) -> NamedTuple

Get sender statistics.
"""
function stats(sender::UDPSender)
    return (
        send_count = sender.send_count,
        error_count = sender.error_count,
        error_rate = sender.error_count / max(sender.send_count, 1)
    )
end
