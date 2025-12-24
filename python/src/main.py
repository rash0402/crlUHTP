"""
UHTP Python Viewer - Main Entry Point

60Hz visualization and GUI for UHTP experiments.
"""

import sys
import time
import argparse

from .network import UDPReceiver
from .visualization import Renderer


__version__ = "0.1.0"


def main():
    """Main entry point for UHTP Python Viewer."""
    parser = argparse.ArgumentParser(description="UHTP Python Viewer")
    parser.add_argument(
        "--port", type=int, default=12345,
        help="UDP port to listen on (default: 12345)"
    )
    parser.add_argument(
        "--width", type=int, default=1280,
        help="Window width (default: 1280)"
    )
    parser.add_argument(
        "--height", type=int, default=720,
        help="Window height (default: 720)"
    )
    args = parser.parse_args()

    print("=" * 50)
    print("  UHTP Python Viewer")
    print(f"  Version: {__version__}")
    print("=" * 50)
    print()

    # Create renderer
    from .visualization.renderer import RenderConfig
    config = RenderConfig(
        width=args.width,
        height=args.height,
        origin_x=args.width // 2,
        origin_y=args.height // 2
    )
    renderer = Renderer(config)

    # Create UDP receiver
    receiver = UDPReceiver(port=args.port)

    print(f"Listening on UDP port {args.port}...")
    print("Waiting for Julia Core...")
    print("Press ESC or close window to exit.")
    print()

    try:
        # Initialize
        if not renderer.init():
            print("Failed to initialize renderer")
            return 1

        receiver.start()

        # Main loop
        frame_count = 0
        last_stats_time = time.time()

        while renderer.running:
            # Get latest message
            msg = receiver.get_latest()

            # Update display
            if not renderer.update(msg):
                break

            frame_count += 1

            # Print stats every 5 seconds
            now = time.time()
            if now - last_stats_time >= 5.0:
                fps = frame_count / (now - last_stats_time)
                print(
                    f"FPS: {fps:.1f} | "
                    f"UDP recv: {receiver.receive_count} | "
                    f"Errors: {receiver.error_count}"
                )
                frame_count = 0
                last_stats_time = now

    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        receiver.close()
        renderer.close()

    print("\nUHTP Python Viewer stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
