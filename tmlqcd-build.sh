#!/bin/bash -ex
export http_proxy=http://localhost:13128 
export https_proxy=http://localhost:13128

MASKS=(
"" \
"ff00000000000000ff000000000000" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000,ff00000000000000ff0000" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000,ff00000000000000ff0000,ff00000000000000ff000000" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000,ff00000000000000ff0000,ff00000000000000ff000000,ff00000000000000ff" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000,ff00000000000000ff0000,ff00000000000000ff000000,ff00000000000000ff,ff00000000000000ff00" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000,ff00000000000000ff0000,ff00000000000000ff000000,ff00000000000000ff,ff00000000000000ff00,ff00000000000000ff00000000" \
"ff00000000000000ff000000000000,ff00000000000000ff00000000000000,ff00000000000000ff0000,ff00000000000000ff000000,ff00000000000000ff,ff00000000000000ff00,ff00000000000000ff00000000,ff00000000000000ff0000000000")


base=$(pwd)
conda_location=$base/miniconda3
wd=$base

set_base_environment () {
  cd $wd
  mkdir -p $wd/mymodules/myrocm
  cat > $wd/mymodules/myrocm/default.sh << EOF
#!/bin/bash -e

module purge
module load PrgEnv-gnu/8.3.3
module load craype-accel-amd-gfx90a
module load amd/5.2.3

EOF
  source $wd/mymodules/myrocm/default.sh
}

set_mpi_environment () {
  return
  
  mkdir -p $wd/mymodules/myopenmpi
  cat > $wd/mymodules/myopenmpi/tmlqcd.lua << EOF
whatis("Name: myopenmpi")
whatis("Version: 5.0.0rc2")
whatis("Category: library")
whatis("Description: An open source Message Passing Interface implementation")
whatis("URL: https://github.com/open-mpi/ompi.git")

depends_on("gcc/10.2.0")
depends_on("cuda/11.3.0")
depends_on("rocm/rocm-5.3-53")

local base = "$wd/mpi"

prepend_path("LD_LIBRARY_PATH", pathJoin(base, "lib"))
prepend_path("LIBRARY_PATH", pathJoin(base, "lib"))
prepend_path("C_INCLUDE_PATH", pathJoin(base, "include"))
prepend_path("CPLUS_INCLUDE_PATH", pathJoin(base, "include"))
prepend_path("CPATH", pathJoin(base, "include"))
prepend_path("INCLUDE", pathJoin(base, "include"))
prepend_path("PATH", pathJoin(base, "bin"))
prepend_path("PKG_CONFIG_PATH", pathJoin(base, "lib", "pkgconfig"))
pushenv("THERA_OMPI_DIR", base)
pushenv("THERA_OMPI_PATH", base)
EOF

    cat > $wd/mymodules/myrocm/default2.sh << EOF
#!/bin/bash -e

set +x
module use $wd/mymodules
module load myopenmpi/tmlqcd
set -x

EOF
  source $wd/mymodules/myrocm/default2.sh
}

set_quda_environment () {
  type=$1
  export PATH=$wd/quda-$type/bin:$PATH
  export LD_LIBRARY_PATH=$wd/quda-$type/lib:$LD_LIBRARY_PATH
}

set_tmlqcd_environment () {
  export PATH=$wd/tmlqcd/bin:$PATH
}

#
# Checkout components
#

checkout_cmake () {
  rm -rf $wd/cmake
  mkdir -p $wd/cmake
  cd $wd/cmake
  
  curl -LO https://github.com/Kitware/CMake/releases/download/v3.23.0/cmake-3.23.0-linux-x86_64.sh
  bash cmake-3.23.0-linux-x86_64.sh --skip-license --prefix=$wd/cmake
}

checkout_quda () {
  cd $wd
  
  rm -rf quda-src 
  git clone --recursive https://github.com/lattice/quda quda-src 
  cd  quda-src 
  git checkout -b mydev 508a1f8
  git submodule sync
  git submodule update --init --recursive --jobs 0
}
checkout_tmlqcd () {
  cd $wd
  
  rm -rf tmlqcd-src 
  git clone --recursive https://github.com/etmc/tmLQCD tmlqcd-src 
  cd  tmlqcd-src 
  git checkout -b mydev 1120110 #0e0230f
  git submodule sync
  git submodule update --init --recursive --jobs 0
  autoconf
}
checkout_lime () {
  cd $wd
  rm -rf lime-src 
  git clone --recursive https://github.com/usqcd-software/c-lime lime-src
  cd  lime-src 
  git checkout -b mydev 924aa0f
  git submodule sync
  git submodule update --init --recursive --jobs 0
  ./autogen.sh
}

#
# Set conda environments
#
conda_base () {
  set +x
  cd $wd
  if [ ! -d $conda_location ] ; then
    curl -LO https://repo.anaconda.com/miniconda/Miniconda3-py39_4.10.3-Linux-x86_64.sh
    bash Miniconda3-py39_4.10.3-Linux-x86_64.sh -b -p $conda_location -s
  fi
  source $conda_location/bin/activate
  if [ ! -d $conda_location/envs/tmlqcd-rocm-base ] ; then
    conda create -y -n tmlqcd-rocm-base python=3.9
    conda activate tmlqcd-rocm-base
    conda install -y ninja mkl=2021.4.0=h06a4308_640 mkl-include=2021.4.0=h06a4308_640
  else
    conda activate tmlqcd-rocm-base
  fi
  set -x
}

#
# Build components 
#

build_lime () {
  rm -rf $wd/lime-src/build
  mkdir $wd/lime-src/build
  cd $wd/lime-src/build
  
  ../configure --prefix=$wd/lime CC=$(which g++) CFLAGS=-O3

  nice make -j
  
  rm -rf $wd/lime
  nice make -j install
}

build_quda_rocm () {
  rm -rf $wd/quda-src/build-rocm
  mkdir $wd/quda-src/build-rocm
  cd $wd/quda-src/build-rocm

  #module load cmake/3.23.0
  
  CMAKE_PREFIX_PATH="$CRAY_MPICH_PREFIX:$CMAKE_PREFIX_PATH" \
  $wd/cmake/bin/cmake \
    -DCMAKE_C_COMPILER=$(which cc) \
    -DCMAKE_CXX_COMPILER=$(which hipcc) \
    -DCMAKE_HIP_COMPILER=$ROCM_PATH/llvm/bin/clang++ \
    -DCMAKE_BUILD_TYPE=DEVEL \
    -DQUDA_TARGET_TYPE=HIP \
    -DCMAKE_INSTALL_PREFIX=$wd/quda-rocm \
    -DQUDA_BUILD_ALL_TESTS=ON \
    -DQUDA_MULTIGRID=ON \
    -DQUDA_MPI=ON \
    -DQUDA_GPU_ARCH=gfx90a \
    -DAMDGPU_TARGETS=gfx90a \
    -DGPU_TARGETS=gfx90a \
    -GNinja \
    $wd/quda-src |& tee sam-cmake.log

  nice ninja
  
  rm -rf $wd/quda-rocm
  nice ninja install
}


build_tmlqcd () {
  rm -rf $wd/tmlqcd-src/build
  mkdir $wd/tmlqcd-src/build
  cd $wd/tmlqcd-src/build
  

  top_builddir=$(pwd) \
  CC=$(which gcc)\
  CXX=$(which g++) \
  ../configure \
    --prefix=$wd/tmlqcd \
    --enable-sse2 \
    --enable-sse3 \
    --enable-omp \
    --enable-mpi \
    --enable-quda_experimental \
    --with-qudadir=$wd/quda-rocm \
    --with-hipdir=$HIP_PATH \
    --with-limedir=$wd/lime
    
  CC=$(which gcc) CXX=$(which g++) nice make -j
  
  rm -rf $wd/tmlqcd
  CC=$(which gcc) CXX=$(which g++) nice make -j install

}

# salloc -p caldera -w TheraC10 -N 1 --gpus 2 --mem 128G --mem-bind none --cpus-per-gpu 32 --gpu-bind=map_gpu:0,1 --time 10:00:00
# salloc -p MI250 -w TheraC60 -N 1 --gpus 4 --mem 128G --mem-bind none --cpus-per-gpu 12 --gpu-bind=map_gpu:0,1,2,3 --time 10:00:00
run_dslash () {
  type=$1
  ngpus=$2
  folder="test-dslash-$type-${ngpus}gpus"
  
  rm -rf $wd/$folder
  #mkdir $wd/$folder
  cp -rf $wd/postprocess/initial-runs-1strun/$folder $wd/$folder
  cd $wd/$folder
  
  if [ "$type" = "rocm" ] ; then
    cat > hostfile << EOF
$(hostname)
$(hostname)
$(hostname)
$(hostname)
EOF
    cat > rankfile << EOF
rank 0=$(hostname) slot=24-25
rank 1=$(hostname) slot=26-27
rank 2=$(hostname) slot=28-29
rank 3=$(hostname) slot=30-31
EOF
  else
    cat > hostfile << EOF
$(hostname)
$(hostname)
EOF
    cat > rankfile << EOF
rank 0=$(hostname) slot=16
rank 1=$(hostname) slot=0
EOF
  fi
  
  for L in 16 24 32 48 ; do
    cat > cmd-$L.sh << EOF
#!/bin/bash -ex

echo Rank \$SLURM_PROCID \$(taskset -p \$\$)

if [ "$type" = "cuda" ] ; then
  export CUDA_VISIBLE_DEVICES=0,1
  
  # Post process with nsys stats  --report gputrace --format csv nsys.out.qdrep 
  pcmd="/usr/local/bin/nsys profile \
     -o L$L-nsys.out \
     --stats=true \
     --sample=none \
     --trace=cuda,nvtx,mpi \
     --capture-range=none"
       
     # --kernel-regex-base function \
     # --kernel-id ::regex:kCalcPMEOrthoNBFrc16_kernel:5000 -f \
     # --export kCalcPMEOrthoNBFrc16_kernel \
     #
     
#   pcmd="ncu \
#     --target-processes all \
#     --set full \
#     --import-source yes \
#     --kernel-regex-base function \
#     --kernel-id ::regex::100 \
#     -f --export L$L-all-kernels"
else
  unset ROCR_VISIBLE_DEVICES
  #export ROCR_VISIBLE_DEVICES=0,1,2,3
  unset HIP_VISIBLE_DEVICES
  export HIP_VISIBLE_DEVICES=0,1,2,3
   
  # pcmd="rocprof --hip-trace --basenames on -o L$L-rocprof-results.csv"
  pcmd="rocprof --stats --basenames on -i $wd/counters.txt -o L$L-rocprof-results.csv"
fi  

echo "Rank \$SLURM_PROCID \$(taskset -p \$\$) - GPUs \$HIP_VISIBLE_DEVICES"

export QUDA_ENABLE_TUNING=1
export QUDA_RESOURCE_PATH=$(pwd)

if [ \$SLURM_PROCID  -ne 0 ] ; then
  pcmd=''
fi

\$pcmd \
$wd/quda-$type/bin/dslash_test \
  --dim $L $L $(( L / $ngpus )) $(( $L / 4 )) \
  --gridsize 1 1 1 $ngpus \
  --niter $(( 100000 / $L )) \
  --prec single \
  --dslash-type twisted-clover |& tee L${L}-rank\$SLURM_PROCID.out
EOF
    chmod +x cmd-$L.sh
    srun -N 1 -n $ngpus \
      --exclusive \
      --gpus=8 \
      --cpus-per-task=$((128/$ngpus))  --cpu-bind=mask_cpu:${MASKS[$ngpus]} \
      ./cmd-$L.sh |& tee log-$L.out
  done
}

run_multigrid () {
  type=$1
  ngpus=$2
  folder="test-multigrid-$type-${ngpus}gpus"
  
  rm -rf $wd/$folder
  #mkdir $wd/$folder
  cp -rf $wd/postprocess/initial-runs-1strun/$folder $wd/$folder
  cd $wd/$folder
  
  cat > gdb.commands << EOF
set index-cache directory /home/sfantao/gdb-index
set index-cache on

set pagination off
set can-use-hw-watchpoints 0

target remote localhost:12345
set sysroot /

layout src

b main
commands
silent
end
c 

EOF
  
  if [ "$type" = "rocm" ] ; then
    cat > hostfile << EOF
$(hostname)
$(hostname)
$(hostname)
$(hostname)
EOF
    cat > rankfile << EOF
rank 0=$(hostname) slot=24-25
rank 1=$(hostname) slot=26-27
rank 2=$(hostname) slot=28-29
rank 3=$(hostname) slot=30-31
EOF
  else
    cat > hostfile << EOF
$(hostname)
$(hostname)
EOF
    cat > rankfile << EOF
rank 0=$(hostname) slot=16
rank 1=$(hostname) slot=0
EOF
  fi
  
  for L in 8 16 ; do
    cat > cmd-$L.sh << EOF
#!/bin/bash -ex

echo Rank \$SLURM_PROCID \$(taskset -p \$\$)

if [ "$type" = "cuda" ] ; then
  export CUDA_VISIBLE_DEVICES=0,1
  
  pcmd="/usr/local/bin/nsys profile \
     -o L$L-nsys.out \
     --stats=true \
     --sample=none \
     --trace=cuda,nvtx,mpi \
     --capture-range=none"
       
     # --kernel-regex-base function \
     # --kernel-id ::regex:kCalcPMEOrthoNBFrc16_kernel:5000 -f \
     # --export kCalcPMEOrthoNBFrc16_kernel \
     #
     
#   pcmd="ncu \
#     --target-processes all \
#     --set full \
#     --import-source yes \
#     --kernel-regex-base function \
#     --kernel-id ::regex::100 \
#     -f --export L$L-all-kernels"
else
  unset ROCR_VISIBLE_DEVICES
  #export ROCR_VISIBLE_DEVICES=0,1,2,3
  unset HIP_VISIBLE_DEVICES
  export HIP_VISIBLE_DEVICES=0,1,2,3
  
  pcmd="rocprof --stats --basenames on -i $wd/counters.txt -o L$L-rocprof-results.csv"
  # pcmd="rocprof --hip-trace --basenames on -o L$L-rocprof-results.csv"
  
  
  # echo "gdb -x gdb.commands $wd/quda-$type/bin/multigrid_benchmark_test"
#   pcmd="gdbserver --once localhost:12345"
fi  

echo "Rank \$SLURM_PROCID \$(taskset -p \$\$) - GPUs \$HIP_VISIBLE_DEVICES"

export QUDA_ENABLE_TUNING=1
export QUDA_RESOURCE_PATH=$(pwd)

if [ \$SLURM_PROCID  -ne 0 ] ; then
  pcmd=''
fi

\$pcmd \
$wd/quda-$type/bin/multigrid_benchmark_test \
  --dim $L $L $L $(( $L / $ngpus / 2 )) \
  --gridsize 1 1 1 $ngpus \
  --niter 100000 \
  --prec single \
  --dslash-type twisted-clover |& tee L${L}-rank\$SLURM_PROCID.out
EOF
    chmod +x cmd-$L.sh
    srun -N 1 -n $ngpus \
      --exclusive \
      --gpus=8 \
      --cpus-per-task=$((128/$ngpus))  --cpu-bind=mask_cpu:${MASKS[$ngpus]} \
      ./cmd-$L.sh |& tee log-$L.out
      
  done
}


set_base_environment

# checkout_cmake
# checkout_quda
# checkout_tmlqcd
# checkout_lime

conda_base

set_mpi_environment


# build_quda_rocm

# {
#   set_quda_environment "rocm" 
#   build_tmlqcd
#   set_tmlqcd_environment
# }


if ! which nvidia-smi &> /dev/null ; then
(
  set_quda_environment "rocm" 
  run_dslash "rocm" 1
  run_dslash "rocm" 2
  run_dslash "rocm" 4
  true
)
fi

if ! which nvidia-smi &> /dev/null ; then
(
  set_quda_environment "rocm" 
  run_multigrid "rocm" 1
  run_multigrid "rocm" 2
  run_multigrid "rocm" 4
  true
)
fi



