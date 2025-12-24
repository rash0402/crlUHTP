"""
CSV Summary Writer for UHTP

Writes trial summaries to CSV for quick analysis.
"""

import csv
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any


class CSVWriter:
    """
    CSV writer for trial summaries.
    """

    def __init__(
        self,
        output_dir: str = "./data",
        subject_id: str = "unknown",
        task_type: str = "sos"
    ):
        """Initialize CSV writer."""
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.subject_id = subject_id
        self.task_type = task_type

        # Current file
        self.filename: Optional[Path] = None
        self.file = None
        self.writer = None
        self.trial_number = 0

    def start_experiment(self):
        """Start a new experiment CSV file."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.filename = self.output_dir / f"summary_{timestamp}.csv"

        self.file = open(self.filename, 'w', newline='')
        self.writer = csv.writer(self.file)

        # Write header
        self.writer.writerow([
            'trial', 'task_type', 'subject_id', 'timestamp',
            'duration_s', 'rmse_x_mm', 'rmse_y_mm', 'rmse_total_mm',
            'sample_count', 'success', 'extra_info'
        ])

        self.trial_number = 0
        print(f"CSV: Started summary -> {self.filename}")

    def write_trial(
        self,
        duration_s: float,
        rmse_x: float,
        rmse_y: float,
        rmse_total: float,
        sample_count: int,
        success: bool = True,
        extra_info: str = ""
    ):
        """Write a trial summary row."""
        if self.writer is None:
            self.start_experiment()

        self.trial_number += 1

        self.writer.writerow([
            self.trial_number,
            self.task_type,
            self.subject_id,
            datetime.now().isoformat(),
            f"{duration_s:.3f}",
            f"{rmse_x * 1000:.3f}",
            f"{rmse_y * 1000:.3f}",
            f"{rmse_total * 1000:.3f}",
            sample_count,
            'success' if success else 'failed',
            extra_info
        ])

        self.file.flush()

    def end_experiment(self):
        """End experiment and close file."""
        if self.file is not None:
            self.file.close()
            self.file = None
            self.writer = None
            print(f"CSV: Summary saved -> {self.filename}")

    def close(self):
        """Close writer."""
        self.end_experiment()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False
