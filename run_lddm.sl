#!/bin/bash -e

#SBATCH --time          2:00:00
#SBATCH --mem           20GB
#SBATCH --cpus-per-task 4
#SBATCH --account       uoa04517
#SBATCH --gpus-per-node l4:1
##SBATCH --gpus-per-node h100:1
#SBATCH --job-name      lddm
#SBATCH --output        lddm.log

# The container is CUDA 12.4, verified against NeSI driver 580.95.05; l4,
# h100, a100 and pro_6000 all work, and the gres type is case-insensitive.
#
# l4 is the default because it is both quicker to get and fast enough: the
# notebook's de novo and docking examples each took ~50s on an l4, against
# upstream's quoted 1m20s and 55s on an H100. Uncomment the h100 line above
# for larger --n_samples runs or the longer programmable design workflows.
#
# To run without a GPU, drop the line entirely and add --device cpu to the
# sample.py calls in the notebook (5-10x slower).

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
