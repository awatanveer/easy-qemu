# easy-qemu - An easy to use qemu kvm guest launching utility.

easy-qemu provides a simplest way to launch a basic qemu guest on Linux systems instead of writing lengthy qemu commands. 
It supports simple qemu guests (launched from a disk image) or the guests launched from iscsi disks.
It supports an easy way to launch a qemu using either no network, tap devices or vfio-pci devices. Further, it supports the following features:
- Launch qemu guest with various disk types.
- Pre-launch mode
- Qemu guest with vTPM support (and fips support) 
- AMD SEV 
- and many other basic features for the convenience.
