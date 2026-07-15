#!/bin/bash

get_cpu_arch() {
  local CPU_ARCH
  if [[ "$1" == *"-64" ]]; then
    CPU_ARCH="x86_64"
  elif [[ "$1" == *"-ppc64le" ]]; then
    CPU_ARCH="powerpc64le"
  elif [[ "$1" == *"-aarch64" ]]; then
    CPU_ARCH="aarch64"
  elif [[ "$1" == *"-s390x" ]]; then
    CPU_ARCH="s390x"
  elif [[ "$1" == *"-riscv64" ]]; then
    CPU_ARCH="riscv64"
  else
    echo "Unknown architecture"
    exit 1
  fi
  echo $CPU_ARCH
}

get_triplet() {
  if [[ "$1" == linux-* ]]; then
    echo "$(get_cpu_arch $1)-conda-linux-gnu"
  elif [[ "$1" == osx-64 ]]; then
    echo "x86_64-apple-darwin13.4.0"
  elif [[ "$1" == osx-arm64 ]]; then
    echo "arm64-apple-darwin20.0.0"
  elif [[ "$1" == win-64 ]]; then
    echo "x86_64-w64-mingw32"
  else
    echo "unknown platform"
    exit 1
  fi
}

export BUILD="$(get_triplet $build_platform)"
export HOST="$(get_triplet $target_platform)"
export TARGET_REF="$(get_triplet $cross_target_platform)"

if [[ "${TARGET}" != "${TARGET_REF}" ]]; then
  echo "TARGET: ${TARGET} does not match expected ${TARGET_REF}"
  exit 1
fi

export SDKROOT=${CONDA_BUILD_SYSROOT}
unset CONDA_BUILD_SYSROOT

extra_pkgs=()

export CF_PREFIX=$SRC_DIR/cf-compilers

if [[ ! -d ${SRC_DIR}/cf-compilers ]]; then
    if [[ "$build_platform" != "$target_platform" ]]; then
      # we need a compiler to target cross_target_platform.
      # when build_platform == target_platform, the compiler
      # just built can be used.
      # when build_platform != target_platform, the compiler
      # just built cannot be used, hence we need one that
      # can be used.
      extra_pkgs+=(
        "gcc_impl_${cross_target_platform}=${gcc_version}"
        "gxx_impl_${cross_target_platform}=${gcc_version}"
        "gfortran_impl_${cross_target_platform}=${gcc_version}"
      )
    fi
    if [[ "${cross_target_platform}" != "osx-"* ]]; then
      extra_pkgs+=(
        "binutils_impl_${cross_target_platform}=${binutils_version}"
        "${cross_target_stdlib}_${cross_target_platform}=${cross_target_stdlib_version}"
      )
    else
      extra_pkgs+=(
        "clang"
        "clangxx"
        "cctools_${cross_target_platform}"
        "ld64_${cross_target_platform}"
      )
    fi
    if [[ "${build_platform}" == "osx-"* ]]; then
      extra_pkgs+=(
        "make"
      )
    fi
    # Remove conda-forge/label/sysroot-with-crypt when GCC < 14 is dropped
    conda create -p ${CF_PREFIX} -c conda-forge/label/gcc-experimental -c conda-forge/label/sysroot-with-crypt -c conda-forge --use-local --yes --quiet \
      "gcc_impl_${build_platform}" \
      "gxx_impl_${build_platform}" \
      "gfortran_impl_${build_platform}" \
      "gcc_impl_${target_platform}" \
      "gxx_impl_${target_platform}" \
      "gfortran_impl_${target_platform}" \
      "${c_stdlib}_${target_platform}=${c_stdlib_version}" \
      gnuconfig \
      ${extra_pkgs[@]}

    if [[ "${TARGET}" == *darwin* ]]; then
      CONDA_OVERRIDE_OSX=15.5 CONDA_SUBDIR="${cross_target_platform}" conda create -p $SRC_DIR/cf-compilers-target -c conda-forge/label/sysroot-with-crypt -c conda-forge --use-local --yes --quiet libcxx-devel
      mkdir -p ${CF_PREFIX}/${TARGET}/lib
      ln -sf $SRC_DIR/cf-compilers-target/lib/libc++* ${CF_PREFIX}/${TARGET}/lib

    fi
    if [[ "${HOST}" == *darwin* && "${HOST}" != "${TARGET}" ]]; then
      CONDA_OVERRIDE_OSX=15.5 CONDA_SUBDIR="${target_platform}" conda create -p $SRC_DIR/cf-compilers-host -c conda-forge/label/sysroot-with-crypt -c conda-forge --use-local --yes --quiet libcxx-devel
      mkdir -p ${CF_PREFIX}/${HOST}/lib
      ln -sf $SRC_DIR/cf-compilers-host/lib/libc++* ${CF_PREFIX}/${HOST}/lib
    fi
    if [[ "${TARGET}" == *darwin* && ! -f "${CF_PREFIX}/bin/${TARGET}-clang" ]]; then
      ln -sf "${CF_PREFIX}/bin/clang" "${CF_PREFIX}/bin/${TARGET}-clang"
    fi
    if [[ "${TARGET}" == *darwin* && ! -f "${CF_PREFIX}/bin/${TARGET}-clang++" ]]; then
      ln -sf "${CF_PREFIX}/bin/${TARGET}-clang" "${CF_PREFIX}/bin/${TARGET}-clang++"
    fi
    if [[ "${HOST}" == *darwin* && ! -f "${CF_PREFIX}/bin/${HOST}-clang" ]]; then
      ln -sf "${CF_PREFIX}/bin/clang" "${CF_PREFIX}/bin/${HOST}-clang"
    fi
    if [[ "${HOST}" == *darwin* && ! -f "${CF_PREFIX}/bin/${HOST}-clang++" ]]; then
      ln -sf "${CF_PREFIX}/bin/${HOST}-clang" "${CF_PREFIX}/bin/${HOST}-clang++"
    fi
    if [[ "${BUILD}" == *darwin* && ! -f "${CF_PREFIX}/bin/${BUILD}-clang" ]]; then
      ln -sf "${CF_PREFIX}/bin/clang" "${CF_PREFIX}/bin/${BUILD}-clang"
    fi
    if [[ "${BUILD}" == *darwin* && ! -f "${CF_PREFIX}/bin/${BUILD}-clang++" ]]; then
      ln -sf "${CF_PREFIX}/bin/${BUILD}-clang" "${CF_PREFIX}/bin/${BUILD}-clang++"
    fi
fi

if [[ "${BUILD_PREFIX}" != "${PREFIX}" ]]; then
  ln -sfn ${CF_PREFIX}/${TARGET} ${BUILD_PREFIX}/${TARGET} || true
  # The build environment is not empty (it provides conda for this script),
  # so ${BUILD_PREFIX}/bin and ${BUILD_PREFIX}/share exist as real
  # directories: symlink the cf-compilers entries individually. A plain
  # `ln -sf` of the whole directory would silently nest the link inside the
  # existing directory (e.g. share/share) and hide gnuconfig and the
  # cross-tools from $BUILD_PREFIX. -n keeps this idempotent when this
  # script is sourced again.
  mkdir -p ${BUILD_PREFIX}/bin ${BUILD_PREFIX}/share
  for f in "${CF_PREFIX}"/bin/* "${CF_PREFIX}"/share/*; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "${BUILD_PREFIX}/${f#"${CF_PREFIX}"/}" || true
  done
fi

export PATH=$SRC_DIR/cf-compilers/bin:$PATH

if [[ "$target_platform" == "win-"* && "${PREFIX}" != *Library ]]; then
    export PREFIX=${PREFIX}/Library
fi

if [[ "$target_platform" == "win-64" ]]; then
  EXEEXT=".exe"
else
  EXEEXT=""
fi
SYSROOT_DIR=${PREFIX}/${TARGET}/sysroot

if [[ "$target_platform" == "osx-"* ]]; then
  STRIP_ARGS=""
else
  STRIP_ARGS="--strip-all"
fi
