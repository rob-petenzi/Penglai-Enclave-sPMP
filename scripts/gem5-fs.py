"""Configure Penglai sPMP boot artifacts on the shared gem5 baseline board."""

import argparse
from pathlib import Path
from runpy import run_path

from gem5.resources.resource import (
    BootloaderResource,
    DiskImageResource,
    KernelResource,
)
from gem5.simulate.simulator import Simulator

parser = argparse.ArgumentParser(
    description="Run Penglai sPMP on shared gem5 baseline"
)
parser.add_argument(
    "--buildroot-dir",
    type=Path,
    required=True,
    help="Directory containing Penglai sPMP Buildroot outputs",
)
args = parser.parse_args()

buildroot_dir = args.buildroot_dir.resolve()
images_dir = buildroot_dir / "images"
build_dir = buildroot_dir / "build"
firmware_path = images_dir / "fw_jump.elf"
kernel_path = build_dir / "linux-custom" / "vmlinux"
rootfs_path = images_dir / "rootfs.ext2"
for path in (firmware_path, kernel_path, rootfs_path):
    if not path.is_file():
        parser.error(f"Missing boot artifact: {path}")

# Load the shared hyphenated board script relative to this file, not cwd.
baseline_board_path = (
    Path(__file__).resolve().parents[2] / "gem5-baseline/baseline-board.py"
)
BaselineBoard = run_path(str(baseline_board_path))["BaselineBoard"]

board = BaselineBoard()
board.set_kernel_disk_workload(
    kernel=KernelResource(local_path=str(kernel_path)),
    disk_image=DiskImageResource(
        local_path=str(rootfs_path),
        root_partition=None,
    ),
    bootloader=BootloaderResource(local_path=str(firmware_path)),
    kernel_args=["console=ttyS0", "root=/dev/vda", "rw"],
)

Simulator(board=board).run()
