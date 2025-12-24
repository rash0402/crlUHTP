"""
HDF5 Data Writer for UHTP

Logs experiment data in HDF5 format.
"""

import h5py
import numpy as np
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any
from dataclasses import dataclass, field

from ..network.protocol import UDPMessage, TaskState


@dataclass
class TrialData:
    """Container for trial time series data."""
    timestamps: list = field(default_factory=list)
    cursor_x: list = field(default_factory=list)
    cursor_y: list = field(default_factory=list)
    cursor_vx: list = field(default_factory=list)
    cursor_vy: list = field(default_factory=list)
    target_x: list = field(default_factory=list)
    target_y: list = field(default_factory=list)
    error_x: list = field(default_factory=list)
    error_y: list = field(default_factory=list)

    def append(self, msg: UDPMessage):
        """Append a message to the trial data."""
        self.timestamps.append(msg.timestamp_us)
        self.cursor_x.append(msg.cursor_x)
        self.cursor_y.append(msg.cursor_y)
        self.cursor_vx.append(msg.cursor_vx)
        self.cursor_vy.append(msg.cursor_vy)
        self.target_x.append(msg.target_x)
        self.target_y.append(msg.target_y)
        self.error_x.append(msg.cursor_x - msg.target_x)
        self.error_y.append(msg.cursor_y - msg.target_y)

    def clear(self):
        """Clear all data."""
        self.timestamps.clear()
        self.cursor_x.clear()
        self.cursor_y.clear()
        self.cursor_vx.clear()
        self.cursor_vy.clear()
        self.target_x.clear()
        self.target_y.clear()
        self.error_x.clear()
        self.error_y.clear()

    def to_arrays(self) -> Dict[str, np.ndarray]:
        """Convert to numpy arrays."""
        return {
            'timestamp': np.array(self.timestamps, dtype=np.float64),
            'cursor_x': np.array(self.cursor_x, dtype=np.float64),
            'cursor_y': np.array(self.cursor_y, dtype=np.float64),
            'cursor_vx': np.array(self.cursor_vx, dtype=np.float64),
            'cursor_vy': np.array(self.cursor_vy, dtype=np.float64),
            'target_x': np.array(self.target_x, dtype=np.float64),
            'target_y': np.array(self.target_y, dtype=np.float64),
            'error_x': np.array(self.error_x, dtype=np.float64),
            'error_y': np.array(self.error_y, dtype=np.float64),
        }

    def compute_rmse(self) -> tuple:
        """Compute RMSE for X and Y axes."""
        if not self.error_x:
            return 0.0, 0.0, 0.0
        ex = np.array(self.error_x)
        ey = np.array(self.error_y)
        rmse_x = np.sqrt(np.mean(ex**2))
        rmse_y = np.sqrt(np.mean(ey**2))
        rmse_total = np.sqrt(np.mean(ex**2 + ey**2))
        return rmse_x, rmse_y, rmse_total


class HDF5Writer:
    """
    HDF5 writer for experiment data.
    """

    def __init__(
        self,
        output_dir: str = "./data",
        subject_id: str = "unknown",
        task_type: str = "sos"
    ):
        """Initialize HDF5 writer."""
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.subject_id = subject_id
        self.task_type = task_type

        # Current file and trial
        self.file: Optional[h5py.File] = None
        self.filename: Optional[Path] = None
        self.trial_number = 0
        self.trial_data = TrialData()

        # Recording state
        self.recording = False

    def start_experiment(self, config: Optional[Dict[str, Any]] = None):
        """Start a new experiment file."""
        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.filename = self.output_dir / f"experiment_{timestamp}.h5"

        # Create HDF5 file
        self.file = h5py.File(self.filename, 'w')

        # Write metadata
        meta = self.file.create_group('metadata')
        meta.attrs['subject_id'] = self.subject_id
        meta.attrs['experiment_date'] = datetime.now().isoformat()
        meta.attrs['task_type'] = self.task_type
        if config:
            import json
            meta.attrs['config'] = json.dumps(config)

        # Create trials group
        self.file.create_group('trials')

        self.trial_number = 0
        print(f"HDF5: Started experiment -> {self.filename}")

    def start_trial(self, parameters: Optional[Dict[str, float]] = None):
        """Start recording a new trial."""
        if self.file is None:
            self.start_experiment()

        self.trial_number += 1
        self.trial_data.clear()
        self.recording = True

        print(f"HDF5: Started trial {self.trial_number}")

    def record(self, msg: UDPMessage):
        """Record a message to current trial."""
        if self.recording:
            self.trial_data.append(msg)

    def end_trial(self, success: bool = True, extra_metrics: Optional[Dict] = None):
        """End current trial and write to HDF5."""
        if not self.recording or self.file is None:
            return

        self.recording = False

        # Create trial group
        trial_name = f"trial_{self.trial_number:03d}"
        trial_group = self.file['trials'].create_group(trial_name)

        # Write task type
        trial_group.attrs['task_type'] = self.task_type
        trial_group.attrs['success'] = success

        # Write timeseries
        ts_group = trial_group.create_group('timeseries')
        arrays = self.trial_data.to_arrays()
        for name, data in arrays.items():
            ts_group.create_dataset(name, data=data, compression='gzip')

        # Write summary
        summary = trial_group.create_group('summary')
        rmse_x, rmse_y, rmse_total = self.trial_data.compute_rmse()
        summary.attrs['rmse_x'] = rmse_x
        summary.attrs['rmse_y'] = rmse_y
        summary.attrs['rmse_total'] = rmse_total
        summary.attrs['sample_count'] = len(self.trial_data.timestamps)

        if self.trial_data.timestamps:
            duration = (self.trial_data.timestamps[-1] - self.trial_data.timestamps[0]) / 1e6
            summary.attrs['duration_s'] = duration

        if extra_metrics:
            for k, v in extra_metrics.items():
                summary.attrs[k] = v

        # Flush to disk
        self.file.flush()

        print(f"HDF5: Ended trial {self.trial_number} (RMSE: {rmse_total*1000:.2f}mm)")

    def end_experiment(self):
        """End experiment and close file."""
        if self.file is not None:
            self.file.close()
            self.file = None
            print(f"HDF5: Experiment saved -> {self.filename}")

    def close(self):
        """Close writer."""
        self.end_experiment()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False
