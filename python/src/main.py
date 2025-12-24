"""
UHTP Python Viewer - Main Entry Point

60Hz visualization and data logging for UHTP experiments.
"""

import sys
import time
import argparse
from typing import Optional

from .network import UDPReceiver
from .network.protocol import UDPMessage, TaskState
from .visualization import Renderer
from .data import HDF5Writer, CSVWriter


__version__ = "0.2.0"


class ExperimentRecorder:
    """Manages experiment recording with trial detection."""

    def __init__(
        self,
        output_dir: str = "./data",
        subject_id: str = "unknown",
        task_type: str = "sos",
        enable_hdf5: bool = True,
        enable_csv: bool = True
    ):
        """Initialize experiment recorder."""
        self.enable_hdf5 = enable_hdf5
        self.enable_csv = enable_csv

        # Writers
        self.hdf5: Optional[HDF5Writer] = None
        self.csv: Optional[CSVWriter] = None

        if enable_hdf5:
            self.hdf5 = HDF5Writer(
                output_dir=output_dir,
                subject_id=subject_id,
                task_type=task_type
            )

        if enable_csv:
            self.csv = CSVWriter(
                output_dir=output_dir,
                subject_id=subject_id,
                task_type=task_type
            )

        # State tracking
        self.current_trial = 0
        self.current_state = TaskState.IDLE
        self.trial_active = False
        self.sample_count = 0

    def start(self, config: Optional[dict] = None):
        """Start experiment recording."""
        if self.hdf5:
            self.hdf5.start_experiment(config)
        if self.csv:
            self.csv.start_experiment()

    def process(self, msg: UDPMessage):
        """Process a message and manage trial state."""
        # Detect trial start
        if msg.task_state == TaskState.RUNNING:
            if not self.trial_active or msg.trial_number != self.current_trial:
                # New trial started
                if self.trial_active:
                    # End previous trial first
                    self._end_trial(success=True)

                self._start_trial(msg.trial_number)

            # Record data
            if self.hdf5 and self.trial_active:
                self.hdf5.record(msg)
                self.sample_count += 1

        # Detect trial end
        elif self.trial_active:
            if msg.task_state == TaskState.COMPLETED:
                self._end_trial(success=True)
            elif msg.task_state == TaskState.FAILED:
                self._end_trial(success=False)
            elif msg.task_state == TaskState.PAUSED:
                # Pause doesn't end trial, just stop recording
                pass

        # Update state
        self.current_state = msg.task_state
        self.current_trial = msg.trial_number

    def _start_trial(self, trial_number: int):
        """Start a new trial."""
        self.current_trial = trial_number
        self.trial_active = True
        self.sample_count = 0

        if self.hdf5:
            self.hdf5.start_trial()

    def _end_trial(self, success: bool = True):
        """End current trial."""
        if not self.trial_active:
            return

        self.trial_active = False

        # Get metrics from HDF5 writer
        if self.hdf5:
            rmse_x, rmse_y, rmse_total = self.hdf5.trial_data.compute_rmse()
            duration = 0.0
            if self.hdf5.trial_data.timestamps:
                ts = self.hdf5.trial_data.timestamps
                duration = (ts[-1] - ts[0]) / 1e6

            self.hdf5.end_trial(success=success)

            # Also write to CSV
            if self.csv:
                self.csv.write_trial(
                    duration_s=duration,
                    rmse_x=rmse_x,
                    rmse_y=rmse_y,
                    rmse_total=rmse_total,
                    sample_count=self.sample_count,
                    success=success
                )

    def stop(self):
        """Stop experiment recording."""
        # End any active trial
        if self.trial_active:
            self._end_trial(success=False)

        if self.hdf5:
            self.hdf5.close()
        if self.csv:
            self.csv.close()


def main():
    """Main entry point for UHTP Python Viewer."""
    parser = argparse.ArgumentParser(description="UHTP Python Viewer")

    # Display options
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

    # Logging options
    parser.add_argument(
        "--log", action="store_true",
        help="Enable data logging"
    )
    parser.add_argument(
        "--output-dir", type=str, default="./data",
        help="Output directory for data files (default: ./data)"
    )
    parser.add_argument(
        "--subject-id", type=str, default="test",
        help="Subject ID for logging (default: test)"
    )
    parser.add_argument(
        "--task", type=str, default="sos",
        choices=["sos", "cit", "fitts"],
        help="Task type (default: sos)"
    )
    parser.add_argument(
        "--no-hdf5", action="store_true",
        help="Disable HDF5 logging (CSV only)"
    )
    parser.add_argument(
        "--no-csv", action="store_true",
        help="Disable CSV logging (HDF5 only)"
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

    # Create recorder if logging enabled
    recorder: Optional[ExperimentRecorder] = None
    if args.log:
        recorder = ExperimentRecorder(
            output_dir=args.output_dir,
            subject_id=args.subject_id,
            task_type=args.task,
            enable_hdf5=not args.no_hdf5,
            enable_csv=not args.no_csv
        )
        print(f"Logging enabled:")
        print(f"  Output: {args.output_dir}")
        print(f"  Subject: {args.subject_id}")
        print(f"  Task: {args.task}")
        print(f"  HDF5: {'yes' if not args.no_hdf5 else 'no'}")
        print(f"  CSV: {'yes' if not args.no_csv else 'no'}")
        print()

    print(f"Listening on UDP port {args.port}...")
    print("Waiting for Julia Core...")
    print()
    print("Controls:")
    print("  T - Toggle trajectory trace")
    print("  P - Toggle error plot")
    print("  C - Clear trace")
    print("  ESC - Exit")
    print()

    try:
        # Initialize
        if not renderer.init():
            print("Failed to initialize renderer")
            return 1

        receiver.start()

        if recorder:
            recorder.start(config={
                "width": args.width,
                "height": args.height,
                "task": args.task
            })

        # Main loop
        frame_count = 0
        last_stats_time = time.time()
        msg_count = 0

        while renderer.running:
            # Get latest message
            msg = receiver.get_latest()

            if msg:
                msg_count += 1

                # Record if logging enabled
                if recorder:
                    recorder.process(msg)

            # Update display
            if not renderer.update(msg):
                break

            frame_count += 1

            # Print stats every 5 seconds
            now = time.time()
            if now - last_stats_time >= 5.0:
                fps = frame_count / (now - last_stats_time)
                rate = msg_count / (now - last_stats_time)

                status = f"FPS: {fps:.1f} | UDP: {rate:.0f} Hz"
                if recorder and recorder.trial_active:
                    status += f" | Trial {recorder.current_trial} [{recorder.sample_count}]"

                print(status)

                frame_count = 0
                msg_count = 0
                last_stats_time = now

    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        receiver.close()
        renderer.close()
        if recorder:
            recorder.stop()

    print("\nUHTP Python Viewer stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
