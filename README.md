# easy-qemu - An easy to use qemu kvm guest launching utility for Linux.

easy-qemu provides a simplest way to launch a basic qemu guest on Linux systems instead of writing lengthy qemu commands. 
It supports simple qemu guests (launched from a disk image) or the guests launched from iscsi disks.
It supports an easy way to launch a qemu using either no network, tap devices or vfio-pci devices. Further, it supports the following features:
- Launch qemu guest with various disk types.
- Pre-launch mode
- Qemu guest with vTPM support (and fips support) 
- AMD SEV 
- and many other basic features for the convenience.

### Examples
#### Launch a basic qemu kvm guest
```
sudo bash easy-qemu.sh -O <image.qcow2>
```

#### Launch a qemu guest with network
##### with NAT
```
sudo bash easy-qemu.sh -O <image.qcow2> -n user
```
##### with macvtap
```
sudo bash easy-qemu.sh -O <image.qcow2> -n macvtap0
```

##### with vfio-pci
```
sudo bash easy-qemu.sh -O <image.qcow2> -b <pci bus id> -n vf
# pci bus id can be obtained using lspci 
```

#### OS installation using an ISO
##### installation on local disk/image
```
sudo bash easy-qemu.sh --iso <iso file> -O <image.qcow2>
```
##### installation on iscsi disk on default lun(0)
```
sudo bash easy-qemu.sh --iso <iso file> --iscsi 
```
##### installation on iscsi disk on specific lun
```
sudo bash easy-qemu.sh --iso <iso file> --iscsi -l 9
```

#### Booting and attaching ISCSI disks 
##### Boot from local disk/image with iscsi disks attached
```
sudo bash easy-qemu.sh -O <image.qcow2> --iscsi -l 9,2,3,4,5,6 
```

##### Boot from iscsi disk with other iscsi disks attached
```
sudo bash easy-qemu.sh --iscsi boot -l 9,2,3,4,5,6
# First lun in the array i.e. 9 in this example, is used as a boot disk. 
```