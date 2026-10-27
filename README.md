# LDDM

Codebase for the SHOC2 containerised version of [LDDM](https://github.com/LPDI-EPFL/lddm)
(Large Drug Discovery Model) — a pocket-conditioned 3D generative model for
structure-based drug design. Files:

- `lddm.def`: Apptainer definition file to build a container for LDDM
- `build_lddm.sh`: Bash script to build the LDDM container, fetch the checkpoint and register the kernel
- `lddm.ipynb`: Jupyter notebook to use LDDM interactively
- `run_lddm.sl`: SLURM script to run `lddm.ipynb` non-interactively

Suggested usage:

1. Run `./build_lddm.sh` and make sure `lddm.sif` is built
2. Go to https://ondemand.nesi.org.nz/public/ and select Jupyter Lab
    - Cluster: SLURM HPC
    - Project Code: uoa04517
    - JupyterLab Module: 2026.7.0-foss-2026-4.6.0
    - Number of Hours: 2
    - Number of Cores: 4
    - Memory per Job: 20 GB
    - GPU: L4
3. When Open OnDemand starts, select the file `lddm.ipynb` from the chooser
4. Modify the file to run your workflow
5. If you need to run for longer, or a GPU is not available, save changes in `lddm.ipynb`, open a terminal in Open OnDemand, and type:
6. `sbatch run_lddm.sl`

## What LDDM does

One model covers de novo design, fragment growing and linking, docking,
partial docking (covalent ligands), locally programmable design, and
synthesizable design in virtual chemical spaces. The notebook demonstrates
each of these against the bundled KRAS example.

Paper: [bioRxiv 2026.09.15.751537](https://www.biorxiv.org/content/10.64898/2026.09.15.751537v1)

## How this differs from the other SHOC2 packages

**The environment is uv-managed, not conda.** Upstream builds a `.venv` in the
working directory with `uv sync --extra cuda --frozen`. Here that `.venv` is
baked into the image at `/opt/lddm/.venv` and put on `PATH`, so the kernel
starts without any per-user setup. The lockfile is installed `--frozen`, so
there is no resolution at build time and the build is reproducible.

**The checkpoint is not in the image.** The main checkpoint (`CD+BB+BN`) is
CC-BY-NC 4.0 licensed because it was partly trained on BindingNet, so baking it
into a `.sif` we push to GHCR would redistribute it. `build_lddm.sh` downloads
it from Zenodo into a bind-mounted `checkpoints/` directory instead. The
MIT-licensed `CD+BB` checkpoint (`lddm_CDBB.ckpt`) is available as a drop-in
alternative — change `CKPT` in `build_lddm.sh`.

**Only data directories are writable.** The code and `.venv` stay read-only in
the image; `examples/`, `configs/`, `checkpoints/`, `data/` and `output/` are
bound in from project space. This matters for `data/validity3d/` in particular:
the geometry evaluator caches compiled reference distributions beside
`ligands.sdf` on first use, which takes a while, and the bind mount means that
cache survives between runs.

**Gnina and Reduce are included.** Both are required for the programmable
design workflows, and both come from the upstream Dockerfile's versions
(Gnina v1.1, Reduce v4.15).

**The base image is plain Ubuntu, not nvidia/cuda.** The `torch==2.6.0+cu124`
wheel vendors the entire CUDA 12.4 userspace (cuBLAS, cuDNN, NCCL, cuSPARSE and
friends) as `nvidia-*-cu12` pip packages — that is most of the 6.5 GB venv. A
CUDA base image would add a second, unused copy that can shadow the wheel's.
Only the host driver is needed, and `apptainer --nv` provides it.

Expect the built `.sif` to be roughly 4-5 GB (6.5 GB venv, compressed by
SquashFS), so make sure there is room in project space before building.

## Paths must not contain spaces

Apptainer bind strings are comma-separated and parsed unquoted. A space
anywhere in the project path splits the bind list, Apptainer treats the
fragment after the space as the image path, and the kernel fails with:

```
Kernel died before replying to kernel_info
```

`build_lddm.sh` and `run_lddm.sl` both check for this and fail with a clear
message rather than a confusing Apptainer error. Keep directory names like
`1_Molecules_generated` rather than `1. Molecules generated`.
