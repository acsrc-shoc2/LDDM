#!/bin/bash -e

#SBATCH --time          2:00:00
#SBATCH --mem           20GB
#SBATCH --cpus-per-task 4
#SBATCH --account       uoa04517
#SBATCH --gpus-per-node H100:1
#SBATCH --job-name      lddm
#SBATCH --output        lddm.log

# The container is CUDA 12.4; A100, H100 and L4 all work. Swap the --gpus-per-node
# line above if H100s are busy. To run without a GPU, drop it and add
# --device cpu to the sample.py calls in the notebook (5-10x slower).

module load JupyterLab/2026.7.0-foss-2026-4.6.0

# Where the shared lddm kernel is registered
export JUPYTER_PATH=/nesi/project/uoa04517/.jupyter/share/jupyter

# Apptainer bind strings are comma-separated and parsed unquoted, so a space
# anywhere in the submit directory splits the bind list and the kernel dies with
# "Kernel died before replying to kernel_info". Fail early and clearly instead.
case "$SLURM_SUBMIT_DIR" in
    *" "*) echo "ERROR: submit directory contains a space: $SLURM_SUBMIT_DIR" >&2
           echo "Rename it (e.g. 1._Foo -> 1_Foo) and resubmit." >&2
           exit 1 ;;
esac

papermill lddm.ipynb output_lddm.ipynb --kernel lddm
