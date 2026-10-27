#!/bin/bash -e

# Build the LDDM container, stage its writable data directories, download the
# checkpoint and geometry reference, and register the JupyterLab kernel.

# Location to install the container and work folders into.
# NOTE: no spaces anywhere in this path. Apptainer bind strings are
# comma-separated and unquoted internally, so a space in a project path
# silently splits the bind list and the kernel fails to start.
PROJDIR=/nesi/project/uoa04517/SHOC2/LDDM

# Group/project the data and container should be readable by
GROUP=uoa04517

case "$PROJDIR" in
    *" "*) echo "ERROR: PROJDIR contains a space; Apptainer binds will break." >&2
           exit 1 ;;
esac

mkdir -p "$PROJDIR"
cd "$PROJDIR"

# Set up cache folders
unset APPTAINER_BIND
export APPTAINER_CACHEDIR=$(mktemp -d)
export APPTAINER_TMPDIR=${APPTAINER_CACHEDIR}

# Build container
apptainer build --force lddm.sif lddm.def
chmod 640 lddm.sif
# Should also be available publicly via github actions:
# apptainer pull lddm.sif oras://ghcr.io/acsrc-shoc2/lddm/lddm:latest

# ---------------------------------------------------------------------------
# Writable work folders. The LDDM code and the .venv stay read-only inside the
# image; only these directories are bound in, so results land in project space.
# ---------------------------------------------------------------------------
# Where the project lives inside the image. NOT named APPTAINER_HOME: every
# APPTAINER_* name is reserved as apptainer's own configuration, and
# APPTAINER_HOME in particular overrides the container's home directory. As a
# plain shell variable it was harmless, but exporting it -- or running this
# script somewhere it is already set -- silently reconfigures the home mount
# and makes unrelated binds fail with "destination ... doesn't exist in
# container".
CONTAINER_HOME="/opt/lddm"

for d in examples configs; do
    if [ ! -d "$PROJDIR/$d" ]; then
        echo "Staging $d from the container"
        apptainer exec lddm.sif cp -r "$CONTAINER_HOME/$d" "$PROJDIR/$d"
    fi
done

mkdir -p "$PROJDIR/checkpoints" \
         "$PROJDIR/output" \
         "$PROJDIR/data/validity3d" \
         "$PROJDIR/data/synspace"

# ---------------------------------------------------------------------------
# Checkpoint and reference data.
#
# These are deliberately NOT baked into the .sif. The main checkpoint
# (CD+BB+BN) is CC-BY-NC 4.0 because it was partly trained on BindingNet, so it
# should not be redistributed inside a container image we push to GHCR.
# lddm_CDBB.ckpt is the MIT-licensed alternative; swap CKPT below to use it.
# ---------------------------------------------------------------------------
ZENODO=https://zenodo.org/records/22754501/files
CKPT=lddm.ckpt       # or lddm_CDBB.ckpt for the MIT-licensed model

if [ ! -f "$PROJDIR/checkpoints/$CKPT" ]; then
    echo "Downloading checkpoint $CKPT"
    wget -P "$PROJDIR/checkpoints/" "$ZENODO/$CKPT"
fi

# Geometry reference, needed for programmable design, synthesizable design and
# 3D validity evaluation. On first use LDDM compiles reference distributions and
# caches them next to this file, which is why data/ must be writable.
if [ ! -f "$PROJDIR/data/validity3d/ligands.sdf" ]; then
    echo "Downloading 3D validity geometry reference"
    wget -P "$PROJDIR/data/validity3d/" "$ZENODO/ligands.sdf"
fi

# SynSpace chemical space for the synthesizable design demo. Five files,
# about 12 MB in total, so there is little reason to skip it. The large
# download is the geometry reference above (228 MB), which also grows roughly
# 900 MB of cache beside itself the first time programmable or synthesizable
# design runs.
for f in building_blocks.csv building_blocks.pkl reactions.json \
         reaction_to_building_blocks.csv reaction_to_building_blocks.pkl; do
    if [ ! -f "$PROJDIR/data/synspace/$f" ]; then
        echo "Downloading SynSpace $f"
        wget -P "$PROJDIR/data/synspace/" "$ZENODO/$f"
    fi
done

chgrp -R "$GROUP" "$PROJDIR"
chmod -R g+rwX "$PROJDIR"

# Verify every data file the notebook needs actually arrived. Running only
# part of this script, or losing a download partway, otherwise shows up much
# later as a missing-file error inside a notebook cell.
MISSING=0
for f in checkpoints/$CKPT \
         data/validity3d/ligands.sdf \
         data/synspace/building_blocks.pkl \
         data/synspace/reactions.json \
         data/synspace/reaction_to_building_blocks.pkl; do
    if [ ! -s "$PROJDIR/$f" ]; then
        echo "MISSING: $f" >&2
        MISSING=1
    fi
done
if [ "$MISSING" -ne 0 ]; then
    echo "ERROR: data files are missing; re-run this script to fetch them." >&2
    echo "The de novo, fragment and docking workflows still work without" >&2
    echo "data/synspace; synthesizable design does not." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Register the JupyterLab kernel
# ---------------------------------------------------------------------------
module load JupyterLab/2026.7.0-foss-2026-4.6.0

BIND_STRING="-B $PROJDIR/examples:$CONTAINER_HOME/examples"
BIND_STRING="$BIND_STRING,$PROJDIR/configs:$CONTAINER_HOME/configs"
BIND_STRING="$BIND_STRING,$PROJDIR/checkpoints:$CONTAINER_HOME/checkpoints"
BIND_STRING="$BIND_STRING,$PROJDIR/data:$CONTAINER_HOME/data"
BIND_STRING="$BIND_STRING,$PROJDIR/output:$CONTAINER_HOME/output"

rm -rf /nesi/project/uoa04517/.jupyter/share/jupyter/kernels/lddm
nesi-add-kernel lddm -cp lddm.sif \
    --container-args="--nv --pwd $CONTAINER_HOME $BIND_STRING" \
    --shared -a "$GROUP"

echo To bind local folders to inside container, use the following:
echo "$BIND_STRING"
echo "$BIND_STRING" > bind_syntax.txt
