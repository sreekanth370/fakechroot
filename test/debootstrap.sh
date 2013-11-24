#!/bin/sh

# This script setups new environment with debootstrap, installs necessary
# packages with APT, downloads source package for hello, and builds the
# binary package.
#
# It should work with any Debian-based system.

srcdir=${srcdir:-.}
abs_srcdir=${abs_srcdir:-`cd "$srcdir" 2>/dev/null && pwd -P`}

test -d "$abs_srcdir/bin" && export PATH="$abs_srcdir/bin:$PATH"

run () {
    HOME=/root fakechroot chroot $destdir "$@"
}

die () {
    echo "$@" 1>&2
    exit 1
}

command -v debootstrap >/dev/null 2>&1 || die 'debootstrap command is missing (sudo apt-get install debootstrap)'
command -v fakeroot    >/dev/null 2>&1 || die 'fakeroot command is missing (sudo apt-get install fakeroot)'
command -v lsb_release >/dev/null 2>&1 || die 'lsb_release command is missing (sudo apt-get install lsb-release)'
command -v xzcat       >/dev/null 2>&1 || die 'xzcat command is missing (sudo apt-get install xz-utils)'

vendor=${VENDOR:-`lsb_release -s -i`}
release=${RELEASE:-`lsb_release -s -c`}
variant=$VARIANT
type=`dpkg-architecture -qDEB_HOST_GNU_TYPE 2>/dev/null`
systype=${type#*-}
arch=${ARCH:-`dpkg-architecture -t$(arch)-$systype -qDEB_HOST_ARCH 2>/dev/null`}

if [ $# -gt 0 ]; then
    destdir=$1
    shift
else
    destdir="$abs_srcdir/testtree"
fi

if [ -n "$DEBOOTSTRAP_CACHE" ]; then
    mkdir -p "$DEBOOTSTRAP_CACHE"
fi

tarball=`test -d "$DEBOOTSTRAP_CACHE" && cd "$DEBOOTSTRAP_CACHE"; pwd`/$vendor-$release${variant:+-$variant}-$arch.debs.tgz

export FAKECHROOT_AF_UNIX_PATH=/tmp

if ! command -v chroot >/dev/null 2>&1; then
    PATH=$PATH:/usr/sbin:/sbin
    export PATH
fi

debootstrap_opts="--arch=$arch ${variant:+--variant=$variant}"
if [ ! -f $tarball ]; then
    FAKECHROOT=true fakeroot debootstrap --download-only --make-tarball=$tarball --include=build-essential,devscripts,fakeroot,gnupg $debootstrap_opts $release $destdir "$@"
fi

rm -rf $destdir

ls -l $tarball

fakechroot fakeroot debootstrap --unpack-tarball="$tarball" $debootstrap_opts $release $destdir || cat $destdir/debootstrap/debootstrap.log

HOME=/root fakechroot fakeroot /usr/sbin/chroot $destdir apt-get --force-yes -y --no-install-recommends install build-essential devscripts fakeroot gnupg

run sh -c 'cat /etc/apt/sources.list | sed "s/^deb/deb-src/" >> /etc/apt/sources.list'
run fakeroot apt-get --force-yes -y update
run sh -c 'cd /tmp && apt-get --force-yes -y source hello && cd hello-* && debuild --preserve-env -b -uc -us'
run fakeroot sh -c 'dpkg -i /tmp/hello_*.deb'
run sh -c 'hello'
