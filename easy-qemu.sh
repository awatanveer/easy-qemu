#!/bin/bash

# Copyright [2022] [Awais Tanveer]

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

EQ_CONFIG_FILE="config"
EQ_QEMU_CMD=""
EQ_OS=""
EQ_CUSTOM_IMAGE=""
EQ_ISO=""
EQ_INSTALL=false
EQ_LOCAL_BOOT=true
EQ_ISCSI_BOOT=false
EQ_BOOT_LUN=0
EQ_LUNS=""
EQ_ARCH=$(uname -m)
EQ_NETWORK=false
EQ_OS_VERSION="os_name"
EQ_LUN_ARRAY=""
EQ_SCSI_DRIVE_MODE=true
EQ_ISCSI_PORTAL_IP=""
EQ_ISCSI_TARGET=""
EQ_ISCSI_INITIATOR=""
EQ_BLOCK_DEVS=""
EQ_SCSI_DRIVES=""
EQ_SCSI_DEVICE_TYPE="scsi-block"
EQ_CONTROLLER=""
EQ_LOCAL_DISK_PARAM=""
EQ_LOCAL_DISK_TYPE="ide"
EQ_NIC_MODEL=""
EQ_PCI_BUS=""
EQ_ROM_FILE=""
EQ_SEV=false
EQ_SEV_ARGS=""
EQ_IOMMU_PLAT=''
EQ_LAUNCH_MODE="local"
EQ_TPM=false
EQ_TPM_CMD=""
EQ_FIPS=false
EQ_PCIE_ROOT_PORTS=0
EQ_PCIE_PORTS_OFFSET=5
EQ_PCIE_ROOT_DEVICES=""
EQ_PRE_LAUNCH_MODE=false
EQ_PRE_LAUNCH_OPTION=""

get_param_from_config()
{
    [[ $# -ne 1 ]] && echo "get_param_from_config: no parameter specified" && return 1
    local param=$1
    local param_val=""
    if [[ -f "${EQ_CONFIG_FILE}" ]]; then
        param_val=$(cat ${EQ_CONFIG_FILE} | grep ${param} | cut -d'=' -f2)
    else
        # TODO: Decide what to do when config file is not found. 
        # SET default values?
        echo "config file not found."
    fi
    echo ${param_val}
}

detect_package_manager()
{
    # returns detected package manager in EQ_PACK_MAN
    if [[ `command -v rpm` ]]; then
        EQ_PACK_MAN="rpm"
    elif [[ `command -v dpkg` ]]; then
        EQ_PACK_MAN="dpkg"
    else
        # TODO check for more package managers 
        EQ_PACK_MAN=''
        return 1
    fi
}

get_installed_package()
{ 
    if [[ $# < 1 ]]; then
        echo ""
        return 1
    fi
    local package=$1
    detect_package_manager
    if [[ "${EQ_PACK_MAN}" == "rpm" ]]; then
        echo `rpm -qa | grep ${package}`
    elif [[ "${EQ_PACK_MAN}" == "dpkg" ]]; then
        package=$(echo ${package} | tr '[:upper:]' '[:lower:]')
        echo `dpkg-query --list | \
        grep ${package} | \
        awk '{print $2 "-" $3}'` | \
        sed 's/ /, /g'
    else
        echo ""
        return 1
    fi
}

################
# Detects the OS based on the found package manager.
# For example, if this method detects the availability of 
# rpm command, the redhat-based OS is assumed and if dpkg 
# command is available, we assume debian-based OS. 
################
detect_os()
{
    detect_package_manager
    if [[ "${EQ_PACK_MAN}" == "rpm" ]]; then
        EQ_OS="redhat"
    elif [[ "${EQ_PACK_MAN}" == "dpkg" ]]; then
        EQ_OS="debian"
    else 
        # TODO: Detect more OSes based on the package manager
        EQ_OS="unknown"
    fi
    echo ${EQ_OS}
}

usage()
{
    echo "Usage: iscsi-vm-ol-installation.sh [OPTION...]"
    echo "-a                Additional arguments for qemu command line"
    echo "-o                OL version (default:os_name)"
    echo "-O                Launch from user provided image."
    echo "-l                Format: -l BOOT_LUN,DATA_LUN1,DATA_LUN2 ... (example: 0,2,3,5,7)"
    echo "                  iscsi lun number used for booting or installing OL (default: 3)."
    echo "                  It can also be used to attach array of scsi disks."
    echo "-i                For installation on an iscsi lun. It first downloads the iso from sysinfra."
    echo "                  To install on local image, use -O option to specify the location of image where OS"
    echo "                  needs to be installed."
    echo "-g                VGA type (default: std)"
    echo "-n                [ macvtap_name | vf ] 
                  Network mode. Macvtap device or vfio-pci device.  (default: No network device)"
    echo "-N                NIC model e.g. e1000. Use qemu-system-<arch> -nic model=help to get the list."
    echo "-b                PCI bus id. Required if -n is set to \"vf\"."
    echo "-B                blockdev iscsi mode."
    echo "-s                Add telnet serial console on the chosen local port. Requires port number. (default: 3333)"
    echo "-S                iScsi settings. <portal_ip>,<iscsi_target>,<iscsi_initiator>"
    echo "-v                vnc port"
    echo "-D                Remove -nodefaults for qemu command line"
    echo "-d                Boot from local disk. Optoins: ide | virtio-scsi | virtio-blk (default:  ide)"
    echo "-M                Memory for VM (default: 8G)"
    echo "-C                Qemu cpu option (default: host)"
    echo "-c                Option to choose virio-scsi-pci or lsi controller. (defualt: virtio-scsi-pci)"
    echo "-P                Qemu smp option. (default: 8)"
    echo "-T                Start VM with TPM."
    echo "-t                iScsi device type i.e. scsi-block or scsi-hd. (default: scsi-block)"
    echo "-q                Specify qmp port or unix socket file (e.g. /tmp/my_qmp_sock). (default port: 3334)"
    echo "--iso             Specify ISO image for installation."
    echo "--iscsi [boot]    Attach ISCSI disks. Add 'boot' to boot from an ISCSI disk."
    echo "--machine         Set machine type for Qemu. (default: pc for x86_64, virt for aarch64)"
    echo "--secboot         Start Vm in secure boot mode"
    echo "--secboot-debug   Start Vm in secure boot mode"
    echo "--stdio           Start Vm with serial console on stdio"
    echo "--log             log file for qemu logs (default: OLX-uefi.log)"
    echo "--bg              run qemu in the background aka daemonize"
    echo "--ipxe            ipxe mode. --ipxe <rom file>"
    echo "--big-vm          Start Big VM (default memory size: 1.2T) "
    echo "--pcie-root       Add pcie root ports. These are usually added to support q35 and aarch64 guests."
    echo "--pl              Start qemu in pre-launch mode"
    echo "--usb             To add usb mouse"
    echo "--fips            Force openssl into fips mode"
    echo "--sev             Start VM in SEV mode (This option should only be used to AMD machines"
    echo "-h                Help"
    exit 1
}

get_options() 
{
    local OPTIND opt
    while getopts "a:o:l:b:n:S:v:c:t:g:s:q:N:M:C:P:O:i:TeduUBDh-:" opt; do
        case "${opt}" in
            -)
                case "${OPTARG}" in
                    help)
                        usage
                        exit 0
                        ;;
                    iso)
                        EQ_INSTALL=true
                        EQ_ISO="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        ;;
                    iscsi)
                        EQ_LAUNCH_MODE="iscsi"
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        if [[ "${val}" == "boot" ]]; then
                            EQ_ISCSI_BOOT=true
                            EQ_LOCAL_BOOT=false
                        else
                            OPTIND=$(( $OPTIND - 1 ))
                        fi
                        ;;
                    stdio)
                       EQ_MONITOR="-display none -serial stdio"
                       EQ_SERIAL=""
                       ;;
                    log)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        EQ_LOG_FILE="-D ${val}"
                        ;;
                    bg)
                        EQ_DAEMONIZE="-daemonize"
                        EQ_MONITOR=""
                        ;;
                    machine)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        EQ_MACHINE="-machine ${val}"; 
                        ;;        
                    secboot)
                        secure_boot=true
                        ;;
                    secboot-debug)
                        secure_boot_debug=true
                        ;;
                    ipxe)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        EQ_ROM_FILE=${val}
                        EQ_IPXE=true
                        ;;
                    big-vm)
                        EQ_CPU="-cpu host,+host-phys-bits"
                        EQ_MEMORY="-m 1.2T"
                        ;;       
                    pcie-root)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        EQ_PCIE_ROOT_PORTS=val
                        add_pcie_root_ports_devices
                        ;; 
                    pl)
                        EQ_PRE_LAUNCH_MODE=true
                        ;;               
                    usb)
                        EQ_USB_MOUSE="-usb -device usb-tablet,id=tablet1"
                        ;;  
                    fips)
                        EQ_FIPS=true
                        ;;
                    sev)
                        EQ_SEV=true
                        EQ_CPU="-cpu host,+host-phys-bits"
                        EQ_IOMMU_PLAT=",disable-legacy=on,iommu_platform=true"
                        ;;
                   *)
                      echo "Unknown option --${OPTARG}"
                      exit 1
                      ;;
                esac;;
            a)
                EQ_ADDITIONAL_ARGS=${OPTARG}
                ;;
            o)
                EQ_OS_VERSION=${OPTARG}
                EQ_VM_NAME="-name ${EQ_OS_VERSION}-uefi"
                EQ_LOG_FILE="-D ./${EQ_OS_VERSION}-uefi.log"
                ;;
            O)
                EQ_CUSTOM_IMAGE=${OPTARG}
                ;;
            l)
                luns=${OPTARG}
                if [[ "$luns" == *,* ]]; then
                    EQ_LUN_ARRAY=(${luns//,/ })
                    EQ_BOOT_LUN=${EQ_LUN_ARRAY[0]}
                else
                    EQ_BOOT_LUN=${OPTARG}
                fi
                ;;
            b)
               EQ_PCI_BUS=${OPTARG}
               ;;
            g)
               EQ_VGA="-vga ${OPTARG}"
               ;;
            q)
               # check if it is not a number i.e. port number
               re='^[0-9]+$' 
               if ! [[ $OPTARG =~ $re ]] ; then
                    EQ_QMP_SOCK="-qmp unix:${OPTARG},server,nowait" # unix socket
               else
                    EQ_QMP_SOCK="-qmp tcp:127.0.0.1:${OPTARG},server,nowait"
               fi
               ;;
            n)
                EQ_NETWORK=${OPTARG}
                if [[ "${EQ_NETWORK}" != *"macvtap"*  && \
                    "${EQ_NETWORK}" != "vf" && \
                    "${EQ_NETWORK}" != "user" ]]; then
                    echo -e "\n${EQ_NETWORK} is invalid option for -n\n"
                    exit 1
                fi
                ;;
            N)
                EQ_NIC_MODEL=${OPTARG}
                ;;
            S)
                iscsi_info=${OPTARG}
                if [[ "$iscsi_info" == *,*  ]]; then
                    si_arr=(${iscsi_info//,/ })
                    iscsi_portal=${si_arr[0]}
                    iscsi_target=${si_arr[1]}
                    iscsi_initiator=${si_arr[2]}
                else
                    echo "Invalid arguments for -S"
                    echo "Using default iscsi settings."
                fi
                ;;
            B)
                EQ_SCSI_DRIVE_MODE=false
                ;;
            D)
                EQ_NO_DEFAULTS=""
                ;;
            C)
                EQ_CPU="-cpu ${OPTARG}"
                ;;
            c)
                EQ_CONTROLLER=${OPTARG}
                EQ_VIRTIO_DEVICE="-device ${EQ_CONTROLLER},id=${EQ_CONTROLLER}0"
                ;;
            d)
                EQ_LOCAL_BOOT=true
                # Check next positional parameter
                eval nextopt=\${$OPTIND}
                # existing or starting with dash?
                if [[ -n $nextopt && $nextopt != -* ]] ; then
                  OPTIND=$((OPTIND + 1))
                  EQ_LOCAL_DISK_TYPE=$nextopt
                else
                  EQ_LOCAL_DISK_TYPE="ide"
                fi
                ;;
            M)
                EQ_MEMORY="-m ${OPTARG}"
                ;;
            P)
                EQ_SMP="-smp ${OPTARG}"
                ;;
            s)
                EQ_SERIAL="-serial telnet:127.0.0.1:${OPTARG},server,nowait"
                ;;
            v)
               EQ_VNC="-vnc :${OPTARG}"
               ;;
            T)
               EQ_TPM=true
               ;;
            t)
               EQ_SCSI_DEVICE_TYPE=${OPTARG}
               ;;
            h)
                usage
                ;;
            *)
                echo "Unknow option ${opt}"
                echo "Use -h for help"
                exit 1
                ;;
         esac
    done
}
set_defaults() 
{
    EQ_ISCSI_PORTAL_IP=$(get_param_from_config ISCSI_PORTAL_IP)
    EQ_ISCSI_TARGET=$(get_param_from_config ISCSI_TARGET)
    EQ_ISCSI_INITIATOR=$(get_param_from_config ISCSI_INITIATOR)
    EQ_ADDITIONAL_ARGS=""
    secure_boot=false
    secure_boot_debug=false
    EQ_VM_NAME="-name ${EQ_OS_VERSION}-uefi"
    EQ_CPU="-cpu host"
    EQ_NO_DEFAULTS="-nodefaults"
    EQ_MEMORY="-m 8G"
    EQ_SMP="-smp 8,maxcpus=240"
    EQ_MONITOR="-monitor stdio"
    EQ_VNC="-vnc 0.0.0.0:0,to=999"
    EQ_QMP_SOCK="-qmp tcp:127.0.0.1:3334,server,nowait"
    EQ_SERIAL="-serial telnet:127.0.0.1:3333,server,nowait"
    EQ_CONTROLLER="virtio-scsi-pci"
    EQ_VIRTIO_DEVICE="-device virtio-scsi-pci,id=virtio-scsi-pci0"
    EQ_LOG_FILE="-D ./${EQ_OS_VERSION}-uefi.log"
    EQ_USB_MOUSE=""
    EQ_DAEMONIZE=""
    EQ_IHC9=""
    EQ_IPXE=false
    EQ_DEBUG_CON=""
    # Architecture specific settings
    if [[ "${EQ_ARCH}" == "x86_64" ]]; 
    then 
        EQ_MACHINE="-machine pc,accel=kvm"; 
        EQ_VGA="-vga std"
        EQ_AHCI=""
    else 
        EQ_MACHINE="-machine virt,accel=kvm,gic-version=3"; 
        EQ_VGA="-device virtio-gpu-pci -device usb-ehci -device usb-kbd -device usb-mouse"
        EQ_AHCI="-device ahci,id=ahci0"
    fi
}

get_qemu() 
{
    if [[ "${EQ_ARCH}" = "x86_64" ]]; then
        EQ_QEMU_CMD="qemu-system-x86_64"
    elif [[ "${EQ_ARCH}" == "aarch64" ]]; then
        EQ_QEMU_CMD="qemu-system-aarch64"
    else
        echo -e "Architecture not supported.\n"
        exit 1
    fi
    if [[ ! `command -v "${EQ_QEMU_CMD}"` ]]; then
        EQ_QEMU_CMD="/usr/libexec/qemu-kvm"
        if [[ ! `command -v  "${EQ_QEMU_CMD}"` ]]; then
            echo "\e[34mHypervisor    : \e[31mQemu not found on the system.\n\e[39m"
            exit 1
        fi
    fi
    echo -e "\e[34mHypervisor    : \e[39m$(${EQ_QEMU_CMD} --version | grep -i emul)"
}

get_edk2_info()
{
    local edk2=""
    EQ_EDK2_DIR="/usr/share/OVMF"
    [[ "${EQ_ARCH}" == "x86_64"  ]] && edk2="ovmf" || edk2="aavmf"
    local edk2_pack_name=$(get_installed_package ${edk2})
    if [[ -z ${edk2_pack_name} ]]; then
        # On some distributions such as Oracle Linux 7, edk2 package name
        # is OVMF (uppercase).
        EDK2=$(echo ${edk2} | tr '[:lower:]' '[:upper:]')
        edk2_pack_name=$(get_installed_package ${edk2})
    fi 
    if [[ -n ${edk2_pack_name} && -d "${EQ_EDK2_DIR}" ]]; then 
        echo -e "\e[34mOVMF/AAVMF    : \e[39m${edk2_pack_name}"
    else
        echo -e "\e[34mOVMF/AAVMF    : \e[31mNot installed\n\e[39m"
        # TODO: Add legacy bios support
        echo "easy-qemu only supports UEFI currently. Exitting."
        exit 1
    fi
}

get_host_info()
{
   local host_type="Unknown"
   local lscpu_hypervisor=""
   lscpu_hypervisor=$(lscpu | grep Hypervisor)
   if [[ -n "${lscpu_hypervisor}" ]]; then
        host_type="KVM Guest"
   else
        host_type="Bare-Metal Server"  
   fi
   echo -e "\n"
   echo -e "\e[32mHOST INFO\e[39m"
   echo -e "\e[34mHost type     : \e[39m${host_type}"
   echo -e "\e[34mCPU model     : \e[39m$(lscpu | grep -i 'model name' | cut -d':' -f2 | xargs)"
   echo -e "\e[34mArchitecture  : \e[39m${EQ_ARCH}"
   echo -e "\e[34mHostname      : \e[39m$(hostname)"
   echo -e "\e[34mOS            : \e[39m$(cat /etc/os-release | grep PRETTY_NAME= | cut -d'"' -f2)"
   echo -e "\e[34mKernel        : \e[39m$(uname -rv)"
   get_qemu
   get_edk2_info
   echo -e "\n"
}

get_iso() 
{
   echo ""
}

set_scsi_disks() 
{
    local boot_index=""
    [[ "${EQ_ISCSI_BOOT}" == "true" ]] && boot_index=",bootindex=0"
    local counter=1
    for lun in "${EQ_LUN_ARRAY[@]}"; do 
        if [[ "${EQ_SCSI_DRIVE_MODE}" == "false" ]]; then
            if [[ "${counter}" -eq 1 ]]; then
                EQ_BLOCK_DEVS=$(printf %s "-blockdev driver=iscsi,transport=tcp,"\
                        "portal=${EQ_ISCSI_PORTAL_IP}:3260,initiator-name=${EQ_ISCSI_INITIATOR},"\
                        "target=${EQ_ISCSI_TARGET},lun=${EQ_BOOT_LUN},node-name=boot,"\
                        "cache.no-flush=off,cache.direct=on,read-only=off -device ${EQ_SCSI_DEVICE_TYPE},"\
                        "bus=${EQ_CONTROLLER}0.0,id=disk_boot,drive=boot${boot_index}")
            else
                EQ_BLOCK_DEVS=$(printf %s "${EQ_BLOCK_DEVS} -blockdev driver=iscsi,transport=tcp,"\
                        "portal=${EQ_ISCSI_PORTAL_IP}:3260,initiator-name=${iscsi_initiator},"\
                        "target=${EQ_ISCSI_TARGET},lun=${EQ_LUN_ARRAY[lun]},node-name=data${lun},"\
                        "cache.no-flush=off,cache.direct=on,read-only=off "\
                        "-device ${EQ_SCSI_DEVICE_TYPE},bus=${EQ_CONTROLLER}0.0,id=disk${lun},"\
                        "drive=data${lun}")   
            fi
        else
            EQ_ISCSI_INITIATOR_PARAM="-iscsi initiator-name=${EQ_ISCSI_INITIATOR}"
            if [[ "${counter}" -eq 1 ]]; then
                EQ_SCSI_DRIVES=$(printf %s "-drive "\
                            "file=iscsi://${EQ_ISCSI_PORTAL_IP}/${EQ_ISCSI_TARGET}/${EQ_BOOT_LUN},"\
                            "format=raw,if=none,id=drive_boot -device ${EQ_SCSI_DEVICE_TYPE},"\
                            "id=boot_image,drive=drive_boot,bus=${EQ_CONTROLLER}0.0${boot_index}")
            else
                EQ_SCSI_DRIVES=$(printf %s "${EQ_SCSI_DRIVES} "\
                            "-drive file=iscsi://${EQ_ISCSI_PORTAL_IP}/${EQ_ISCSI_TARGET}/${EQ_LUN_ARRAY[${lun}]},"\
                            "format=raw,if=none,id=drive_image${lun} -device ${EQ_SCSI_DEVICE_TYPE},"\
                            "id=image${lun},drive=drive_image${lun},bus=${EQ_CONTROLLER}0.0")
            fi        
        fi
        counter=$((counter+1)) 
    done
    [[ "${EQ_INSTALL}" == "true" ]] && local data_lun_info="" || \
                        data_lun_info="with ${#EQ_LUN_ARRAY[@]} data LUNs attached."
    echo -e "\e[32mLAUNCHING VM - Booting from LUN #${EQ_BOOT_LUN} ${data_lun_info}.\e[39m"
    echo "iScsi portal: ${EQ_ISCSI_PORTAL_IP}"
    echo "iScsi target: ${EQ_ISCSI_TARGET}"
    echo -e "iScsi initiator: ${EQ_ISCSI_INITIATOR}\n"
}

set_local_disk()
{
    if [[ "${EQ_LOCAL_DISK_TYPE}" == "ide" ]]; then
        EQ_LOCAL_DISK_PARAM=$(printf %s "-drive file=${EQ_CUSTOM_IMAGE},if=none,"\
                            "id=local_disk0,media=disk -device ide-hd,drive=local_disk0,"\
                            "id=local_disk1,bootindex=0")
        if [ "${EQ_ARCH}" == "aarch64" ]; 
        then
            EQ_LOCAL_DISK_PARAM="-hda ${EQ_CUSTOM_IMAGE} -boot order=c,menu=on"
        fi
    elif [[ "${EQ_LOCAL_DISK_TYPE}" == "virtio-scsi" ]]; then
        EQ_LOCAL_DISK_PARAM=$(printf %s "-drive file=${EQ_CUSTOM_IMAGE},if=none,id=virtscsi_disk,"\
                            "media=disk -device scsi-hd,drive=virtscsi_disk,"\
                            "bus=${EQ_CONTROLLER}0.0,id=local_disk0,bootindex=0")
    elif [[ "${EQ_LOCAL_DISK_TYPE}" == "virtio-blk" ]]; then
        EQ_LOCAL_DISK_PARAM=$(printf %s "-drive file=${EQ_CUSTOM_IMAGE},if=none,id=virtblk_disk,"\
                            "media=disk -device virtio-blk-pci,drive=virtblk_disk,"\
                            "id=local_disk0,bootindex=0")
    else
        echo -e "\e[31m${EQ_LOCAL_DISK_TYPE} is invalid storage device type for -d \n\e[39m"
        exit 1 
    fi
    echo -e "Using ${EQ_CUSTOM_IMAGE} image to boot from disk."
}

start_tpm()
{
    local tpm_dir="/tmp"
    local fips_mode=""
    tpm_dir=$(get_param_from_config TPM_DIR)
    echo -e "\e[32mStarting TPM\e[39m"
    mkdir -p ${tpm_dir}/nvram_v1/
    if [[ "${EQ_FIPS}" == "true" ]];then
        fips_mode="OPENSSL_FORCE_FIPS_MODE=1"
        export OPENSSL_FORCE_FIPS_MODE=1
    fi
    install_packages swtpm
    local swtpm_cmd=$(printf %s "${fips_mode} swtpm socket "\
                "--tpmstate dir=${tpm_dir}/nvram_v1/ --ctrl type=unixio," \
                "path=${tpm_dir}/swtpm-sock --tpm2 "\
                "--log file=${tpm_dir}/mytpm.log,level=20,truncate --daemon")
    echo "swtpm command: ${swtpm_cmd}"
    eval "$swtpm_cmd"

    EQ_TPM_CMD=$(printf %s "-chardev socket,id=chrtpm0,path=${tpm_dir}/swtpm-sock "\
                "-tpmdev emulator,id=tpm0,chardev=chrtpm0 -device tpm-tis,tpmdev=tpm0 "\
                "-global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1 "\
                "-chardev pty,id=charserial1 -device isa-serial,chardev=charserial1,id=serial1 "\
                "-global driver=cfi.pflash01,property=secure,value=on")
    EQ_DEBUG_CON="-debugcon file:${tpm_dir}/ovmf_debug.log -global isa-debugcon.iobase=0x402"
}

set_network()
{
    if [ "${EQ_NETWORK}" == "vf" ]; then
        if [[ -z "${EQ_PCI_BUS}" ]]; then
            echo -e "\n-n flag requires -b flag.\n"
            exit 1
        fi
        EQ_QMEU_NET="-net none -device vfio-pci,host=${EQ_PCI_BUS}"
        if [[ "${EQ_IPXE}" == "true" ]]; then
            EQ_QMEU_NET=$(printf %s "-device vfio-pci,host=${EQ_PCI_BUS},id=ipxe-nic,"\
                "romfile=${EQ_ROM_FILE} -boot n")
            if [[ "$ARCH" == "aarch64"  ]]; then
                EQ_QMEU_NET=$(printf %s "-device pcie-root-port,id=root,slot=0 "\
                    "-device vfio-pci,host=${EQ_PCI_BUS},id=ipxe-nic," 
                    "romfile=${EQ_ROM_FILE} -boot n")
            fi
        fi
    elif [[ "${EQ_NETWORK}" == "macvtap"* ]]; then
        local ipxe_param=''
        if [[ "${EQ_IPXE}" == "true" ]]; then
            ipxe_param=",romfile=${EQ_ROM_FILE}"
        fi
        if [[ "${sev}" == "true" ]]; then
            ipxe_param=",romfile=''"
        fi
        EQ_QMEU_NET=$(printf %s "-netdev tap,"\
            "id=${EQ_NETWORK},fd=3 3<>/dev/tap$(< /sys/class/net/${EQ_NETWORK}/ifindex) "\
            "-device virtio-net-pci,mac=$(< /sys/class/net/${EQ_NETWORK}/address),"\
            "id=virtio-net-pci0,vectors=482,mq=on,netdev=${EQ_NETWORK}${ipxe_param}${EQ_IOMMU_PLAT}")
        if [[ -n "${EQ_NIC_MODEL}" ]]; then 
            EQ_QMEU_NET=$(printf %s "-net nic,model=${EQ_NIC_MODEL},"\
                "macaddr=$(cat /sys/class/net/${EQ_NETWORK}/address) "\
                "-net tap,fd=3 3<>/dev/tap$(cat /sys/class/net/${EQ_NETWORK}/ifindex)")
        fi
    elif [[ "${EQ_NETWORK}" == "user" ]]; then
        EQ_QMEU_NET="-net nic -net user,id=net0,hostfwd=tcp::2222-:22"
    else
        EQ_QMEU_NET=""
    fi     
}

add_pcie_root_ports_devices()
{
    if [[ "${EQ_MACHINE}" == "-machine q35" || \
    "${EQ_MACHINE}" == "-machine virt,accel=kvm,gic-version=3" ]]; then
        local range=$((EQ_PCIE_ROOT_PORTS + EQ_PCIE_PORTS_OFFSET))
        for ((i=EQ_PCIE_PORTS_OFFSET;i<range;i++)); do
            local addr=$( printf "%x" ${i} )
            EQ_PCIE_ROOT_DEVICES=$(printf %s "${EQ_PCIE_ROOT_DEVICES} -device pcie-root-port,port=${i},"\
                                 "chassis=${i},id=pciroot${i},bus=pcie.0,addr=0x${addr}")
        done
    fi
}

qemu_command()
{
    content='#!/bin/bash\n\n'
    content="${content}${EQ_QEMU_CMD} ${EQ_VM_NAME} \\\\\n"
    content="${content}${EQ_MACHINE} \\\\\n"
    content="${content}-enable-kvm \\\\\n"
    content="${content}${EQ_CPU} \\\\\n"
    content="${content}${EQ_MEMORY} \\\\\n"
    content="${content}${EQ_SMP} \\\\\n"
    content="${content}${EQ_LOG_FILE} \\\\\n"
    [[ -n  "${EQ_NO_DEFAULTS}"  ]] && content="${content}${EQ_NO_DEFAULTS} \\\\\n"
    [[ -n  "${EQ_MONITOR}"  ]] && content="${content}${EQ_MONITOR} \\\\\n"
    content="${content}${EQ_VNC} \\\\\n"
    content="${content}${EQ_VGA} \\\\\n"
    content="${content}${EQ_EDK2_DRIVES} \\\\\n"
    [[ -n  "${EQ_VIRTIO_DEVICE}"  ]] && content="${content}${EQ_VIRTIO_DEVICE} \\\\\n"
    [[ -n  "${EQ_AHCI}"  ]] && content="${content}${EQ_AHCI} \\\\\n"
    [[ -n  "${EQ_LOCAL_DISK_PARAM}"  ]] && content="${content}${EQ_LOCAL_DISK_PARAM} \\\\\n"
    [[ -n  "${EQ_BLOCK_DEVS}"  ]] && content="${content}${EQ_BLOCK_DEVS} \\\\\n"
    [[ -n  "${EQ_ISCSI_INITIATOR_PARAM}"  ]] && content="${content}${EQ_ISCSI_INITIATOR_PARAM} \\\\\n"
    [[ -n  "${EQ_SCSI_DRIVES}"  ]] && content="${content}${EQ_SCSI_DRIVES} \\\\\n"
    [[ -n  "${EQ_PCIE_ROOT_DEVICES}"  ]] && content="${content}${EQ_PCIE_ROOT_DEVICES} \\\\\n"
    [[ -n  "${EQ_CDROM}"  ]] && content="${content}${EQ_CDROM} \\\\\n"
    [[ -n  "${EQ_QMEU_NET}"  ]] && content="${content}${EQ_QMEU_NET} \\\\\n"
    [[ -n  "${EQ_IHC9}"  ]] && content="${content}${EQ_IHC9} \\\\\n"
    [[ -n  "${EQ_DEBUG_CON}"  ]] && content="${content}${EQ_DEBUG_CON} \\\\\n"
    [[ -n  "${EQ_QMP_SOCK}"  ]] && content="${content}${EQ_QMP_SOCK} \\\\\n"
    [[ -n  "${EQ_SERIAL}"  ]] && content="${content}${EQ_SERIAL} \\\\\n"
    [[ -n  "${EQ_TPM_CMD}"  ]] && content="${content}${EQ_TPM_CMD} \\\\\n"
    [[ -n  "${EQ_DAEMONIZE}"  ]] && content="${content}${EQ_DAEMONIZE} \\\\\n" 
    [[ -n  "${EQ_USB_MOUSE}"  ]] && content="${content}${EQ_USB_MOUSE} \\\\\n"
    [[ -n  "${EQ_ADDITIONAL_ARGS}"  ]] && content="${content}${EQ_ADDITIONAL_ARGS} \\\\\n"
    [[ -n  "${EQ_SEV_ARGS}"  ]] && content="${content}${EQ_SEV_ARGS} \\\\\n"
    [[ -n  "${EQ_PRE_LAUNCH_OPTION}"  ]] && content="${content}${EQ_PRE_LAUNCH_OPTION} \\\\\n"
    
    # Save formated command in a file
    echo -e ${content} > ${EQ_OS_VERSION}-uefi.sh

    final_cmd="${content//\\\\\\n/}"
    final_cmd="${final_cmd//\#\!\/bin\/bash\\n\\n/}" 
    echo $final_cmd
}

copy_edk2_files()
{
    # Copying fresh VAR file
    local mode=".pure-efi."
    [[ ! -d "${EQ_EDK2_DIR}/OVMF_CODE${mode}fd" ]] && mode="."
    if "$secure_boot" ; then 
        mode=".secboot."
        if [ "${EQ_ARCH}" != "aarch64" ];
        then
            EQ_IHC9="-global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1"
        fi
    fi 
    if "$secure_boot_debug" ; then 
        mode="secboot-debug."
        if [ "${EQ_ARCH}" != "aarch64" ];
        then
            EQ_IHC9="-global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1"
            EQ_DEBUG_CON="-debugcon file:ovmf_debug.log -global isa-debugcon.iobase=0x402"
        fi
    fi
    local ovmf_var_file="${EQ_EDK2_DIR}/OVMF_VARS${mode}fd"
    if [[ ! -f "${ovmf_var_file}" ]]; then
        ovmf_var_file="${EQ_EDK2_DIR}/OVMF_VARS.fd"
    fi 
    cp -f ${ovmf_var_file} OVMF_VARS.${EQ_OS_VERSION}
    EQ_EDK2_DRIVES=$(printf %s "-drive file=${EQ_EDK2_DIR}/OVMF_CODE${mode}fd,index=0,"\
                    "if=pflash,format=raw,readonly -drive file=OVMF_VARS.${EQ_OS_VERSION},"\
                    "index=1,if=pflash,format=raw")
}

ipxe_settings()
{
    if [[ "${EQ_IPXE}" == "true" ]]; then
        EQ_AHCI="" 
        EQ_LOCAL_DISK_PARAM=""
        EQ_BLOCK_DEVS=""
        EQ_SCSI_DRIVES=""   
    fi
}

pre_launch_mode_settings()
{
    EQ_VIRTIO_DEVICE=''
    EQ_AHCI="" 
    EQ_LOCAL_DISK_PARAM=""
    local pcie_root_bus=''
    EQ_PRE_LAUNCH_OPTION="-S"
    if [[ "${EQ_MACHINE}" == "-machine q35" ]]; then
        EQ_PCIE_ROOT_DEVICES=$(printf %s "${EQ_PCIE_ROOT_DEVICES} -device pcie-root-port,"\
        "port=4,chassis=4,id=pciroot4,bus=pcie.0,addr=0x4")
        pcie_root_bus=",bus=pciroot4"
    fi
    
    echo "Qemu starting in prelaunch mode. Use following disk hotplug commands to start the guest:"
    echo "(qemu) drive_add auto file=${EQ_CUSTOM_IMAGE},id=drive2,aio=threads,cache=writeback,if=none"
    echo "(qemu) device_add virtio-scsi-pci,id=virtio-scsi-pci2${pcie_root_bus}${EQ_IOMMU_PLAT}"
    echo "(qemu) device_add scsi-hd,id=scsi-hd2,drive=drive2"
    echo "(qemu) c"
}

get_c_bit()
{
   install_packages cpuid
   local text=$(cpuid -r -1 -l 0x8000001f)
   local search="ebx"
   local prefix=${text%%$search*}
   local ebx_index=$((${#prefix} + 4))
   local ebx_val=${text:${ebx_index}:10}
   local mask=$(( (1 << 6) -1 ))
   echo $(( $ebx_val & mask ))
}

install_packages()
{
    if [[ $# < 1 ]]; then
        echo "install_packages: Package name not provided."
        return 1
    fi
    local proxy=$(get_param_from_config PROXY)
    local proxy_vars=""
    if [[ -n "${proxy}" ]]; then
        proxy_vars="http_proxy=${proxy} https_proxy=${proxy}"
    fi
    local packages=$1
    local dist=$(detect_os)
    if [[ "${dist}" == "redhat" ]]; then
        ${proxy_vars} sudo yum install ${packages} -y -q
    elif [[ "${dist}" == "debian" ]]; then
        ${proxy_vars} sudo apt update -y -qq 2>/dev/null >/dev/null
        ${proxy_vars} sudo apt install ${packages} -y -qq 2>/dev/null >/dev/null
    else
        echo "$0: OS not supported. ${packages} can not be installed."
        return 1
    fi
}

enable_sev()
{
    EQ_SEV_ARGS=$(printf %s "-device virtio-rng-pci,disable-legacy=on,"\
                "iommu_platform=true -object sev-guest,id=sev0,cbitpos=$(get_c_bit),"\
                "reduced-phys-bits=1 -machine memory-encryption=sev0")
    EQ_VIRTIO_DEVICE="-device virtio-scsi-pci,id=virtio-scsi-pci0${EQ_IOMMU_PLAT}"
}

set_defaults
get_options "$@"
get_host_info
set_network
[[ "$EQ_TPM" == "true" ]] && start_tpm || EQ_TPM_CMD=""
copy_edk2_files

if [[ "${EQ_INSTALL}" == "true" ]]; then
    get_iso
    EQ_BLOCK_DEVS=$(printf %s "-blockdev driver=iscsi,transport=tcp,"\
            "portal=${EQ_ISCSI_PORTAL_IP}:3260,initiator-name=${EQ_ISCSI_INITIATOR},"\
            "target=${EQ_ISCSI_TARGET},lun=${EQ_BOOT_LUN},node-name=oci-bm-iscsi,"\
            "cache.no-flush=off,cache.direct=on,read-only=off "\
            "-device ${EQ_SCSI_DEVICE_TYPE},bus=${EQ_CONTROLLER}0.0,id=disk1,drive=oci-bm-iscsi")
    EQ_CDROM="-cdrom ${EQ_ISO} -boot d"
    if [[ ("${EQ_LAUNCH_MODE}" == "local") && ( ! -z "${EQ_CUSTOM_IMAGE}" ) ]]
    then
        EQ_BLOCK_DEVS="-drive file=${EQ_CUSTOM_IMAGE},if=none,id=local_disk0,media=disk -device ide-hd,drive=local_disk0,id=local_disk1"
    fi
else
    EQ_CDROM=""
    [[ "${EQ_LOCAL_BOOT}" == "true" ]] && set_local_disk
    if [[ "${EQ_LAUNCH_MODE}" == "iscsi" ]]
    then
        set_scsi_disks ${EQ_BOOT_LUN}
    fi
fi

ipxe_settings 

[[ "${EQ_PRE_LAUNCH_MODE}" == "true" ]] && pre_launch_mode_settings
[[ "${EQ_SEV}"  == "true" ]] && enable_sev

vm_launch_cmd=$(qemu_command)

echo -e "QEMU Command:\n${vm_launch_cmd}"
echo -e ${vm_launch_cmd} > qemu-cmd-latest-noformat

eval "$vm_launch_cmd"
