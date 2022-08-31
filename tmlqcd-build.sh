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

export LANGUAGE="en_US.utf8"
export LC_ALL="en_US.utf8"
export LC_CTYPE="en_US.utf8"
export LANG="en_US.utf8"

module purge
module load CrayEnv

module load buildtools/22.08

module load PrgEnv-gnu craype-accel-amd-gfx90a 

export CMAKE_PREFIX_PATH=/appl/lumi/SW/CrayEnv/EB/buildtools/22.08
module use /pfs/lustrep2/projappl/project_462000125/samantao-public/mymodules
module load rocm/5.2.3

set -x
EOF
  source $wd/mymodules/myrocm/default.sh
}

set_quda_environment () {
  export PATH=$wd/quda/bin:$PATH
  export LD_LIBRARY_PATH=$wd/quda/lib:$LD_LIBRARY_PATH
}

set_tmlqcd_environment () {
  export PATH=$wd/tmlqcd/bin:$PATH
}

#
# Checkout components
#
checkout_libncurses () {
  rm -rf $wd/deps
  mkdir $wd/deps
  cd $wd/deps

  for i in \
    libncurses6-6.1-5.6.2.x86_64.rpm \
    ncurses-devel-6.1-5.6.2.x86_64.rpm \
  ; do
    curl -LO https://download.opensuse.org/distribution/leap/15.3/repo/oss/x86_64/$i
    rpm2cpio $i | cpio -idmv 
  done
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
    conda install -y ninja 
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
  
  ../configure --prefix=$wd/lime CC=$(which cc) CFLAGS=-O3

  nice make -j
  nice make -j install
}

build_quda () {
  rm -rf $wd/quda-src/build
  mkdir $wd/quda-src/build
  cd $wd/quda-src/build
  
  which cmake
  which hipcc

  cmake \
    -DCMAKE_C_COMPILER=$(which cc) \
    -DCMAKE_CXX_COMPILER=$(which hipcc) \
    -DCMAKE_HIP_COMPILER=$(which clang++) \
    -DCMAKE_BUILD_TYPE=Release \
    -DQUDA_TARGET_TYPE=HIP \
    -DCMAKE_INSTALL_PREFIX=$wd/quda \
    -DQUDA_BUILD_ALL_TESTS=ON \
    -DQUDA_MPI=ON \
    -DQUDA_GPU_ARCH=gfx90a \
    -DAMDGPU_TARGETS=gfx90a \
    -DGPU_TARGETS=gfx90a \
    -GNinja \
    $wd/quda-src

  nice ninja
  
  rm -rf $wd/quda
  nice ninja install
}

build_tmlqcd () {
  rm -rf $wd/tmlqcd-src/build
  mkdir $wd/tmlqcd-src/build
  cd $wd/tmlqcd-src/build
  

  top_builddir=$(pwd) \
  CC=$(which cc)\
  CXX=$(which CC) \
  ../configure \
    --prefix=$wd/tmlqcd \
    --enable-sse2 \
    --enable-sse3 \
    --enable-omp \
    --enable-mpi \
    --enable-quda_experimental \
    --with-qudadir=$wd/quda \
    --with-hipdir=$HIP_PATH \
    --with-limedir=$wd/lime
    
  CC=$(which cc) CXX=$(which CC) nice make -j
  
  rm -rf $wd/tmlqcd
  CC=$(which cc) CXX=$(which CC) nice make -j install

}

set_base_environment

# checkout_libncurses
# checkout_quda
# checkout_tmlqcd
# checkout_lime

conda_base
# build_lime

# build_quda
set_quda_environment

# build_tmlqcd
set_tmlqcd_environment
