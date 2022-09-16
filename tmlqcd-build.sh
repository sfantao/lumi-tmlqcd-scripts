#!/bin/bash -ex

base=$(pwd)
conda_location=$base/miniconda3
wd=$base

set_base_environment () {
  cd $wd
  mkdir -p $wd/mymodules/myrocm
  cat > $wd/mymodules/myrocm/default.sh << EOF
#!/bin/bash -e

set +x
module purge
module load gcc/10.2.0
module load cuda/11.3.0
module load rocm/5.2.3
set -x

EOF
  source $wd/mymodules/myrocm/default.sh
}

set_mpi_environment () {
  mkdir -p $wd/mymodules/myopenmpi
  cat > $wd/mymodules/myopenmpi/tmlqcd.lua << EOF
whatis("Name: myopenmpi")
whatis("Version: 5.0.0rc2")
whatis("Category: library")
whatis("Description: An open source Message Passing Interface implementation")
whatis("URL: https://github.com/open-mpi/ompi.git")

depends_on("gcc/10.2.0")
depends_on("rocm/5.2.3")

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

checkout_ucx () {
  cd $wd
  
  rm -rf ucx-src 
  git clone --recursive https://github.com/openucx/ucx.git ucx-src 
  cd  ucx-src 
  git checkout -b mydev v1.13.1
  git submodule sync
  git submodule update --init --recursive --jobs 0
  ./autogen.sh
}

checkout_mpi () {
  cd $wd
  
  rm -rf openmpi-5.0.0rc2* mpi*
  curl -LO https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-5.0.0rc2.tar.gz
  tar -xf openmpi-5.0.0rc2.tar.gz
  ln -s openmpi-5.0.0rc2 mpi-src
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
build_ucx () {
  rm -rf $wd/ucx-src/build
  mkdir $wd/ucx-src/build
  cd $wd/ucx-src/build
  
  ../configure \
    --prefix=$wd/ucx \
    --disable-logging \
    --disable-debug \
    --disable-assertions \
    --disable-params-check \
    --enable-optimizations \
    --enable-mt \
    --disable-logging \
    --disable-debug \
    --disable-assertions \
    --disable-params-check \
    --enable-optimizations \
    --with-rocm=$ROCM_PATH \
    --with-cuda=$THERA_CUDA_PATH \
    --with-verbs=/share/modules/mlnxofed/5.2-2.2.0.0/ \
    --with-knem=/share/modules/knem/1.1.4/

  nice make -j
  nice make -j install
}

build_mpi () {
  rm -rf $wd/mpi-src/build
  mkdir $wd/mpi-src/build
  cd $wd/mpi-src/build
  
  ../configure \
    --prefix=$wd/mpi \
    --with-slurm=/share/opt/slurm/20.11.4 \
    --with-verbs=/share/modules/mlnxofed/5.2-2.2.0.0 \
    --with-hwloc-libdir=/share/modules/hwloc/2.4.1/lib \
    --with-ucx=$wd/ucx

  nice make -j
  nice make -j install
}

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

  module load cmake/3.23.0
  cmake \
    -DCMAKE_C_COMPILER=$(which gcc) \
    -DCMAKE_CXX_COMPILER=$(which hipcc) \
    -DCMAKE_HIP_COMPILER=$ROCM_PATH/llvm/bin/clang++ \
    -DCMAKE_BUILD_TYPE=DEVEL \
    -DQUDA_TARGET_TYPE=HIP \
    -DCMAKE_INSTALL_PREFIX=$wd/quda-rocm \
    -DQUDA_BUILD_ALL_TESTS=ON \
    -DQUDA_MPI=ON \
    -DQUDA_GPU_ARCH=gfx90a \
    -DAMDGPU_TARGETS=gfx90a \
    -DGPU_TARGETS=gfx90a \
    -GNinja \
    $wd/quda-src

  nice ninja
  
  rm -rf $wd/quda-rocm
  nice ninja install
}

build_quda_cuda () {
  rm -rf $wd/quda-src/build-cuda
  mkdir $wd/quda-src/build-cuda
  cd $wd/quda-src/build-cuda

  module load cmake/3.20.0
  cmake \
    -DCMAKE_C_COMPILER=$(which gcc) \
    -DCMAKE_CXX_COMPILER=$(which g++) \
    -DCMAKE_BUILD_TYPE=DEVEL \
    -DQUDA_TARGET_TYPE=CUDA \
    -DCMAKE_INSTALL_PREFIX=$wd/quda-cuda \
    -DQUDA_BUILD_ALL_TESTS=ON \
    -DQUDA_MPI=ON \
    -DQUDA_GPU_ARCH=80 \
    -GNinja \
    $wd/quda-src

  nice ninja
  
  rm -rf $wd/quda-cuda
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
  mkdir $wd/$folder
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
  
  for L in 16 24 32 48; do
    cat > cmd-$L.sh << EOF
#!/bin/bash -ex

echo Rank \$OMPI_COMM_WORLD_RANK \$(taskset -p \$\$)

if [ "$type" = "cuda" ] ; then
  export CUDA_VISIBLE_DEVICES=0,1
  
  
  pcmd-"/usr/local/bin/nsys profile \
     -o $wd/nsys.out \
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
#     -f --export all-kernels"
else
  unset ROCR_VISIBLE_DEVICES
  #export ROCR_VISIBLE_DEVICES=0,1,2,3
  unset HIP_VISIBLE_DEVICES
  export HIP_VISIBLE_DEVICES=0,1,2,3
   
  pcmd="rocprof --hip-trace --basenames on -o $wd/rocprof-results.csv"
  #pcmd="rocprof --stats --basenames on -i $wd/counters.txt -o $wd/rocprof-results.csv"
fi  

echo "Rank \$OMPI_COMM_WORLD_RANK \$(taskset -p \$\$) - GPUs \$HIP_VISIBLE_DEVICES"

export QUDA_ENABLE_TUNING=1
export QUDA_RESOURCE_PATH=$(pwd)
$wd/quda-$type/bin/dslash_test \
  --dim $L $L $(( L / $ngpus )) $(( $L / 4 )) \
  --gridsize 1 1 1 $ngpus \
  --niter $(( 100000 / $L )) \
  --prec single \
  --dslash-type twisted-clover |& tee L${L}-rank\$OMPI_COMM_WORLD_RANK.out
EOF
    chmod +x cmd-$L.sh
    mpirun --display bind,allocation --np $ngpus --hostfile hostfile --rankfile rankfile cmd-$L.sh |& tee log-$L.out
  done
}

run_multigrid () {
  type=$1
  ngpus=$2
  folder="test-multigrid-$type-${ngpus}gpus"
  
  rm -rf $wd/$folder
  mkdir $wd/$folder
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
  
  for L in 16; do
    cat > cmd-$L.sh << EOF
#!/bin/bash -ex

echo Rank \$OMPI_COMM_WORLD_RANK \$(taskset -p \$\$)

if [ "$type" = "cuda" ] ; then
  export CUDA_VISIBLE_DEVICES=0,1
  
  pcmd-"/usr/local/bin/nsys profile \
     -o $wd/nsys.out \
     --stats=true \
     --sample=none \
     --trace=cuda,nvtx,mpi \
     --capture-range=none"
       
     # --kernel-regex-base function \
     # --kernel-id ::regex:kCalcPMEOrthoNBFrc16_kernel:5000 -f \
     # --export kCalcPMEOrthoNBFrc16_kernel \
     #
     
  pcmd="ncu \
    --target-processes all \
    --set full \
    --import-source yes \
    --kernel-regex-base function \
    --kernel-id ::regex::100 \
    -f --export all-kernels"
else
  unset ROCR_VISIBLE_DEVICES
  #export ROCR_VISIBLE_DEVICES=0,1,2,3
  unset HIP_VISIBLE_DEVICES
  export HIP_VISIBLE_DEVICES=0,1,2,3
  
  pcmd="rocprof --stats --basenames on -i $wd/counters.txt -o rocprof-results.csv"
  pcmd="rocprof --hip-trace --basenames on -o rocprof-results.csv"
fi  

echo "Rank \$OMPI_COMM_WORLD_RANK \$(taskset -p \$\$) - GPUs \$HIP_VISIBLE_DEVICES"

export QUDA_ENABLE_TUNING=1
export QUDA_RESOURCE_PATH=$(pwd)

if [ \$OMPI_COMM_WORLD_RANK  -ne 0 ] ; then
  pcmd=''
fi

\$pcmd \
$wd/quda-$type/bin/dslash_test \
  --dim $L $L $L $(( $L / $ngpus )) \
  --gridsize 1 1 1 $ngpus \
  --niter $(( 100000 / $L )) \
  --prec single \
  --dslash-type twisted-clover |& tee L${L}-rank\$OMPI_COMM_WORLD_RANK.out

EOF
    chmod +x cmd-$L.sh
    mpirun --display bind,allocation --np $ngpus --hostfile hostfile --rankfile rankfile cmd-$L.sh |& tee log-$L.out
  done
}


set_base_environment

# checkout_ucx
# checkout_mpi
# checkout_quda
# checkout_tmlqcd
# checkout_lime

conda_base

# build_ucx
# build_mpi

set_mpi_environment

# build_lime

# build_quda_rocm
# build_quda_cuda

# {
#   set_quda_environment "rocm" 
#   build_tmlqcd
#   set_tmlqcd_environment
# }

# {
#   set_quda_environment "rocm" 
#   run_dslash "rocm" 1
#   run_dslash "rocm" 2
#   run_dslash "rocm" 4
# }

# {
#   set_quda_environment "cuda" 
#   run_dslash "cuda" 1
#   run_dslash "cuda" 2
# }

{
  set_quda_environment "rocm" 
#   run_multigrid "rocm" 1
#   run_multigrid "rocm" 2
  run_multigrid "rocm" 4
}

# {
#   set_quda_environment "cuda" 
#   run_multigrid "cuda" 1
#   run_multigrid "cuda" 2
# }


