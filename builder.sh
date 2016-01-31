#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "This tool must be run as root"
    exit
fi

DISTNAME=@1
ISOTYPE=@2
ARCH=@3
BUILDISO=$DISTNAME-$ARCH.iso


get_iso() {
    wget http://archive.ubuntu.com/ubuntu/dists/$DISTNAME/main/installer-$ARCH/current/images/netboot/mini.iso \
        -O build/$BUILDISO
}


base_setup() {
    # TODO: mount base iso and sync files
    if [ -e "build/$BUILDISO" ]; then
        cd "build" && mkdir "mnt" "extract"
        mount -o loop $BUILDISO mnt
        rsync --exclude=/casper/filesystem.squashfs -a mnt extract
        unsquashfs "mnt/casper/filesystem.squashfs"
        mv squashfs-root edit
        cp -r ../pkglists mnt
    else
        echo "$BUILDISO not found! Exiting."
        exit
    fi
}


chroot_setup() {
    echo "Setting up the chroot..."
    rm "edit/etc/resolv.conf"
    echo "Copying resolv.conf..."
    cp "/etc/resolv.conf" "edit/etc/"
    echo "Copying hosts file..."
    cp "/etc/hosts" "edit/etc/"
    echo "binding /dev..."
    mount --bind "/dev" "edit/dev"
    echo "binding /tmp..."
    mount --bind "/tmp" "edit/tmp"
    echo "mounting proc..."
    mount -t proc proc edit/proc
    echo "mounting sysfs..."
    mount -t sysfs none edit/sys
    echo "mounting devpts..."
    mount -t devpts none edit/pts
    echo "entering chroot..."
    chroot edit
}

dpkg_setup() {
    dbus-uuidget > "/var/lib/dbus/machine-id"
    dpkg-divert --local --rename --add /sbin/initctl
    ln -s /bin/true /sbin/initctl
}


libpam_hack() {
    sed -i 's/"exit 100"/"exit 0"/g' /usr/sbin/invoke-rc.d
    ln -s /usr/share/initramfs-tools/scripts /scripts
}


undo_libpam_hack() {
    sed -i 's/"exit 0"/"exit 100"/g' /usr/sbin/invoke-rc.d
    rm -rf /scripts
}


edit_sources() {
    # TODO: Use ISOTYPE to determine PPA source to add to sources.list

    apt-get update
    apt-get upgrade
}


enable_lts() {
    apt-get install --install-recommends linux-generic-lts-$DISTNAME xserver-xorg-lts-$DISTNAME \
        libgl1-mesa-glx-$DISTNAME libgl1-mesa-drivers-lts-$DISTNAME
}

include_pkgs() {
    apt-get install $(cat /pkglists/common.txt)
    apt-get install $(cat /pkglists/$ARCH.txt)
}


fudge() {
    sed -i 's/"min_disk_size = size * 2"/"min_disk_size = size * 1.4"/g' /usr/lib/ubiquity/ubiquity/misc.py
}
