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

# Print an informational progress message.
_P=0
progress () {
    echo "[$_P] $*"
    _P=$(($_P + 1))
}

info () {
    echo "I: $*"
}

# Print a warning message.
warn () {
    echo "W: $*" 1>&2
}

# Print an error message.
error () {
    echo "E: $*" 1>&2
}

# Print an error message and exit.
fatal () {
    echo "fatal error: $*" 1>&2
    exit 1
}

# Refresh package database.
fetch_update_info () {
    progress "Fetching info about available DNF/RPM updates..."
    sudo dnf updateinfo # --refresh
}

# latest_kernel_version
latest_kernel_srpm () {
    KERNEL_SRPM=$(sudo dnf info kernel | sed 's/ *: */:/g' |
                         grep ^Source: | cut -d ':' -f2 | sort | tail -1)
}

# fetch the kernel source RPM
fetch_kernel_srpm () {
    if [ ! -f $KERNEL_SRPM ]; then
        progress "Fetching $KERNEL_SRPM..."
        dnf download --source kernel
    else
        info "Using existing $KERNEL_SRPM..."
    fi
}

# detect kernel, source rpm, aufs4 versions
setup () {
    FEDORA_RELEASE=$(cat /etc/fedora-release | cut -d ' ' -f 3)
    ARCH=$(uname -m)
    KERNEL_VERSION=${KERNEL_SRPM#kernel-}
    KERNEL_VERSION=${KERNEL_VERSION%.fc[0-9]*.src.rpm}
    KERNEL_VANILLA=${KERNEL_VERSION%-*}
    AUFS_VERSION=${KERNEL_VERSION%.*}
    KERNEL_RUNNING=$(uname -r | sed 's/.fc[0-9].*$//')
    
    info "Detected configuration:"
    info "  SRC_DIR: $SRC_DIR"
    info "  ARCH: $ARCH"
    info "  KERNEL_VERSION: $KERNEL_VERSION"
    info "  KERNEL_VANILLA: $KERNEL_VANILLA"
    info "  KERNEL_SRPM: $KERNEL_SRPM"
    info "  AUFS_VERSION: $AUFS_VERSION"
    info "  KERNEL_RUNNING: $KERNEL_RUNNING"

    if [ "$KERNEL_VERSION" != "$KERNEL_RUNNING" -a \
         "$KERNEL_VERSION" != "$KERNEL_RUNNING+aufs" ]; then
        warn "Running ($KERNEL_RUNNING) is not the latest ($KERNEL_VERSION)."
        warn "Will build aufs-enabled $KERNEL_VERSION..."
    fi
    sleep 5
}

# extract the kernel source rpm
extract_kernel_srpm () {
    progress "Extracting $KERNEL_SRPM..."
    rpm -ivh $KERNEL_SRPM
}

# clone aufs4
clone_aufs () {
    if [ ! -d $AUFS_DIR ]; then
        progress "Cloning AUFS4 repo $AUFS_$REPO..."
        git clone $AUFS_REPO
     else
        progress "Pulling from AUFS4 repo $AUFS_$REPO..."
        cd $AUFS_DIR
        git pull
        cd -
    fi
}

# checkout the right aufs version
checkout_aufs () {
    progress "$Checking out version $AUFS_VERSION of AUFS4..."
    cd $AUFS_DIR
    git checkout aufs$AUFS_VERSION
    tar -cvzf $AUFS_TARBALL $AUFS_SOURCES
    cd -
}

# patch the kernel spec file for aufs support
patch_kernel_spec () {
    progress "Patching the kernel SPEC for AUFS4 support..."

    cd $SPEC_DIR
    for v in kernel-$KERNEL_VERSION \
             kernel-$KERNEL_VANILLA \
             kernel; do
        if [ -f $SRC_DIR/$v-spec.patch ]; then
            patch -p0 < $SRC_DIR/$v-spec.patch
            break
        fi
    done
    mv kernel.spec kernel.spec.in
    cat kernel.spec.in | \
      sed 's/^%global fedora_build.*$/%global fedora_build %{baserelease}+aufs/'\
        > kernel.spec
    cd - 
}

# copy in the missing aufs4 and our bits
patch_and_copy_aufs () {
    progress "Copying external AUFS4 source and config bits..."

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
    progress "Rebuilding the kernel RPM..."
    rpmbuild -bb $SPEC_DIR/kernel.spec --without debug --without debuginfo
}


#########################
# main script

set -e

fetch_update_info
latest_kernel_srpm
setup
fetch_kernel_srpm
clone_aufs
extract_kernel_srpm
checkout_aufs
patch_kernel_spec
patch_and_copy_aufs
rebuild_kernel_rpm

