#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "click==8.1.8",
#   "pyyaml==6.0.1",
#   "rich==14.0.0",
# ]
# ///
"""
Dynamically generates a variant configuration and runs rattler-build.

This script takes a package name and an MPI variant, creates a temporary
variant file for that specific build, and executes rattler-build.
It's designed to be used in CI/CD matrix builds.
"""

import copy
import logging
import os
import subprocess
import sys
import tempfile
from enum import StrEnum
from pathlib import Path

import click
import yaml
from rich.logging import RichHandler

# --- 1. Set up constants and structured logging ---
# By convention, constants are in UPPER_SNAKE_CASE.
VARIANTS_FILENAME = "variants.yaml"
BASE_CONFIG_FILENAME = "conda_build_config.yaml"

# Configure logging to use rich for beautiful, clear output.
logging.basicConfig(
    level="INFO",
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True, show_path=False, markup=True)],
)

# Use an Enum to represent the fixed set of choices for MPI variants.
# This is more robust and readable than using raw strings.
class MPIVariant(StrEnum):
    MPICH = "mpich"
    OPENMPI = "openmpi"
    NOMPI = "nompi"


# --- 2. Define the core logic in a 'main' function with Click ---
# The @click decorators turn the main function into a powerful CLI.
@click.command()
@click.argument("package_name", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.argument("mpi_variant", type=click.Choice(MPIVariant))
def main(package_name: Path, mpi_variant: MPIVariant):
    """
    Builds a conda package for a specific MPI_VARIANT.

    PACKAGE_NAME: The path to the package recipe directory.
    MPI_VARIANT: The MPI implementation to build for.
    """
    log = logging.getLogger("rich")
    log.info(f"🚀 Starting build for '{package_name.name}' with MPI variant: [bold cyan]{mpi_variant.value}[/]")

    # --- 3. Read and process configuration files ---
    variants_file_path = package_name / VARIANTS_FILENAME
    log.info(f"Reading base variants from '{variants_file_path}'")
    try:
        with open(variants_file_path, "r") as f:
            all_variants = yaml.safe_load(f)
            # Use an 'assert' for internal sanity checks during development.
            assert "mpi" in all_variants, f"'mpi' key not found in {variants_file_path}"
    except FileNotFoundError:
        log.critical(f"Variant file not found: '{variants_file_path}'")
        sys.exit(1)
    except Exception as e:
        log.critical(f"Failed to read or parse variant file: {e}")
        sys.exit(1)


    # --- 4. Generate the specific variant configuration ---
    variant_config = copy.deepcopy(all_variants)
    variant_config["mpi"] = [mpi_variant.value]

    # Prune keys for other MPI implementations to avoid conflicts.
    for key in MPIVariant:
        if key.value != mpi_variant.value:
            variant_config.pop(key.value, None)

    log.info(f"Generated specific config for [bold cyan]{mpi_variant.value}[/]")


    # --- 5. Execute the build in a controlled subprocess ---
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False, prefix="variant_") as temp_f:
        yaml.dump(variant_config, temp_f)
        temp_variant_filename = temp_f.name
        log.debug(f"Temporary variant file created at: {temp_variant_filename}")

    try:
        # Prepare the command and environment
        build_command = [
            "rattler-build", "build",
            "--experimental",
            "-m", BASE_CONFIG_FILENAME,
            "-m", temp_variant_filename,
            "--no-build-id",
            "--recipe", str(package_name),
        ]

        env = os.environ.copy()
        env["USE_SCCACHE"] = "1"

        log.info(f"Executing command: [yellow]{' '.join(build_command)}[/]")
        subprocess.run(build_command, env=env, check=True)
        log.info(f"✅ [bold green]Build successful for {package_name.name} ({mpi_variant.value})![/]")

    except subprocess.CalledProcessError:
        log.critical(f"❌ [bold red]Build failed for {package_name.name} ({mpi_variant.value}).[/]")
        sys.exit(1)
    except FileNotFoundError:
        log.critical("❌ [bold red]Error: 'rattler-build' command not found.[/] Is rattler-build installed and in your PATH?")
        sys.exit(1)
    finally:
        # Ensure the temporary file is always cleaned up.
        os.remove(temp_variant_filename)
        log.debug(f"Cleaned up temporary file: {temp_variant_filename}")


# --- 6. Use the standard entry point guard ---
if __name__ == "__main__":
    main()
