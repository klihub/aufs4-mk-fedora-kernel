#!/bin/bash

# Our stuff is right next to us.
SRC_DIR=$(realpath ${0%/*})

# rpm directories
SPEC_DIR=$HOME/rpmbuild/SPECS
SOURCE_DIR=$HOME/rpmbuild/SOURCES

# aufs4 git repo, directory name, patches, extra source and config
AUFS_REPO="https://github.com/sfjro/aufs4-standalone"
AUFS_DIR="${AUFS_REPO##*/}"
AUFS_PATCHES="kbuild base mmap standalone"
AUFS_TARBALL="aufs4-sources.tar.gz"
AUFS_SOURCES="Documentation fs include/uapi/linux/aufs_type.h"
AUFS_CONFIG="aufs4.config aufs4-module.config"
AUFS_SPEC_PATCH="kernel-spec.patch"

# detect_versions
# fetch_kernel_srpm
# extract_kernel
# clone_aufs
# checkout_aufs
# patch_kernel_spec
# copy_aufs_extras
# build_kernel_rpm

# detect kernel, source rpm, aufs4 versions
setup () {
    FEDORA_RELEASE=$(cat /etc/fedora-release | cut -d ' ' -f 3)
    ARCH=$(uname -m)
    KERNEL=$(uname -r)
    KERNEL_RELEASE=${KERNEL%.${MACHINE}}
    KERNEL_RELEASE=${KERNEL_RELEASE%.fc[0-9]*}
    KERNEL_SRPM=kernel-$KERNEL_RELEASE.fc$FEDORA_RELEASE.src.rpm
    KERNEL_VERSION=${KERNEL_RELEASE%-*}
    KERNEL_BASERELEASE=${KERNEL_RELEASE#*-}
    AUFS_VERSION=${KERNEL_VERSION%.*}

    echo "Detected configuration:"
    echo "  SRC_DIR: $SRC_DIR"
    echo "  ARCH: $ARCH"
    echo "  KERNEL: $KERNEL"
    echo "  KERNEL_RELEASE: $KERNEL_RELEASE"
    echo "  KERNEL_SRPM: $KERNEL_SRPM"
    echo "  KERNEL_VERSION: $KERNEL_VERSION"
    echo "  KERNEL_BASERELEASE: $KERNEL_BASERELEASE"
    echo "  AUFS_VERSION: $AUFS_VERSION"
    sleep 5
}

# fetch the kernel source RPM
fetch_kernel_srpm () {
    if [ ! -f $KERNEL_SRPM ]; then
        echo "Fetching $KERNEL_SRPM..."
        dnf download --source kernel
    else
        echo "Using existing $KERNEL_SRPM..."
    fi
}

# extract the kernel source rpm
extract_kernel_srpm () {
    echo "Extracting $KERNEL_SRPM..."
    rpm -ivh $KERNEL_SRPM
}

# clone aufs4
clone_aufs () {
    if [ ! -d $AUFS_DIR ]; then
        echo "Cloning AUFS4 repo $AUFS_$REPO..."
        git clone $AUFS_REPO
     else
        echo "Pulling from AUFS4 repo $AUFS_$REPO..."
        cd $AUFS_DIR
        git pull
        cd -
    fi
}

# checkout the right aufs version
checkout_aufs () {
    echo "$Checking out version $AUFS_VERSION of AUFS4..."
    cd $AUFS_DIR
    git checkout aufs$AUFS_VERSION
    tar -cvzf $AUFS_TARBALL $AUFS_SOURCES
    cd -
}

# patch the kernel spec file for aufs support
patch_kernel_spec () {
    echo "Patching the kernel SPEC for AUFS4 support..."

    cd $SPEC_DIR
    patch -p0 < $SRC_DIR/$AUFS_SPEC_PATCH
    mv kernel.spec kernel.spec.in
    cat kernel.spec.in | \
      sed 's/^%global fedora_build.*$/%global fedora_build %{baserelease}+aufs/'\
        > kernel.spec
    cd - 
}

# copy in the missing aufs4 and our bits
patch_and_copy_aufs () {
    echo "Copying external AUFS4 source and config bits..."

    for p in $AUFS_PATCHES; do
        cp $AUFS_DIR/aufs4-$p.patch $SOURCE_DIR
    done
    for c in $AUFS_CONFIG; do
        cp $SRC_DIR/$c $SOURCE_DIR
    done

    cp $AUFS_DIR/$AUFS_TARBALL $SOURCE_DIR
}

# rebuild the kernel rpm
rebuild_kernel_rpm () {
    echo "Rebuilding the kernel RPM..."
    rpmbuild -bb $SPEC_DIR/kernel.spec --without debug --without debuginfo
}


#########################
# main script

set -e -o pipefail

setup
fetch_kernel_srpm
clone_aufs
extract_kernel_srpm
checkout_aufs
patch_kernel_spec
patch_and_copy_aufs
rebuild_kernel_rpm

