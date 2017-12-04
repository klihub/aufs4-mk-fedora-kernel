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
    if [ -z "$NO_FETCH" ]; then
        progress "Fetching info about available DNF/RPM updates..."
        sudo dnf $DNF_RELEASE updateinfo # --refresh
    fi
}

# latest_kernel_version
latest_kernel_srpm () {
    if [ -z "$KERNEL_VERSION" ]; then
        KERNEL_SRPM=$(sudo dnf $DNF_RELEASE info kernel | sed 's/ *: */:/g' |
                             grep ^Source: | cut -d ':' -f2 | tail -1)
    else
        KERNEL_SRPM=kernel-$KERNEL_VERSION.$FEDORA_VERSION.src.rpm
    fi
}

# fetch the kernel source RPM
fetch_kernel_srpm () {
    if [ -z "$NO_FETCH" ]; then
        if [ ! -f $KERNEL_SRPM ]; then
            progress "Fetching $KERNEL_SRPM..."
            dnf $DNF_RELEASE download --source kernel
        else
            info "Using existing $KERNEL_SRPM..."
        fi
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
        if [ -z "$NO_PULL" ]; then
            progress "Pulling from AUFS4 repo $AUFS_$REPO..."
            cd $AUFS_DIR
            git pull
            cd -
        fi
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

# Put any necessary finishing touches on the kernel spec file
finalize_kernel_spec () {
    progress "Finalizing kernel.spec..."
    sed -i "s/ listnewconfig_fail 1/ listnewconfig_fail $NEWCFG_FAIL/" \
        ~/rpmbuild/SPECS/kernel.spec
    sed -i "s/ configmismatch_fail 1/ configmismatch_fail $CFGMISMATCH_FAIL/" \
        ~/rpmbuild/SPECS/kernel.spec
}

# rebuild the kernel rpm
rebuild_kernel_rpm () {
    progress "Rebuilding the kernel RPM..."
    rpmbuild -bb $SPEC_DIR/kernel.spec \
        --without debug --without debuginfo \
        --define "listnewconfig_fail $LISTNEWCONFIG_FAIL" 
}

# build a source rpm of the kernel
build_kernel_srpm () {
    if [ -z "$NO_SRPM" ]; then
        progress "Build kernel source RPM..."
        rpmbuild -bs $SPEC_DIR/kernel.spec
    fi
}

# print ehlp on usage
print_usage () {
    local _msg="$*"

    if [ -n "$_msg" ]; then
        echo "error: $_msg"
    fi

    cat <<EOF
$0 [options], where the possible options are:

    --debug             extra verbose execution of this script (shell set -x)
    --kernel <version>  patch and compile the given kernel version
    --fedora <version>  use the repos for the given fedora version
    --dont-fetch        don't fetch DNF updates or the kernel source rpm
    --dont-pull         don't pull git repos before compiling
    --local             equals --dont-fetch --dont-pull
    --relaxed, -r       force listnewconfig_fail and configmismatch_fail to 0
    --relaxed, -r       if given twice, force configmismatch_fail to 0
    --no-srpm           don't build a final source RPM
    --help              print this help message
EOF

    if [ -n "$_msg" ]; then
        exit 1
    else
        exit 0
    fi
}

# parse the command line for options
parse_cmdline () {
    while [ -n "$1" ]; do
        case $1 in
            --debug|-d) set -x; shift 1;;
            --kernel|-K) KERNEL_VERSION=$2; shift 2;;
            --fedora|-F) FEDORA_VERSION=$2; shift 2;;
            --dont-fetch|--no-fetch) NO_FETCH=1; shift 1;;
            --dont-pull|--no-pull) NO_PULL=1; shift 1;;
            --local) NO_PULL=1; NO_FETCH=1; shift 1;;
            --relaxed|-r)
                if [ "$NEWCFG_FAIL" != "0" ]; then
                    NEWCFG_FAIL=0
                else
                    CFGMISMATCH_FAIL=0
                fi
                shift 1
                ;;
            --no-srpm) NO_SRPM=1; shift 1;;
            --help|-h) print_usage "";;
            *)
              print_usage "unknown option $1"
              ;;
        esac
    done

    if [ -z "$FEDORA_VERSION" ]; then
        version_id=$(cat /etc/os-release | grep VERSION_ID | cut -d '=' -f2)
        FEDORA_VERSION=$version_id
    fi

    DNF_RELEASE="--releasever $FEDORA_VERSION"
}

#########################
# main script

NEWCFG_FAIL=1
CFGMISMATCH_FAIL=1

set -e

parse_cmdline $*
fetch_update_info
latest_kernel_srpm
setup
fetch_kernel_srpm
clone_aufs
extract_kernel_srpm
checkout_aufs
patch_kernel_spec
patch_and_copy_aufs
finalize_kernel_spec
rebuild_kernel_rpm
build_kernel_srpm

