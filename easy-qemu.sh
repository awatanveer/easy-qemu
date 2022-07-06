#!/bin/bash

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

pl_mode=false
pre_launch_option=''

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
                       monitor="-display none -serial stdio"
                       serial=""
                       ;;
                    log)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        log_file="-D ${val}"
                        ;;
                    bg)
                        daemonize="-daemonize"
                        monitor=""
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
                        cpu="-cpu host,+host-phys-bits"
                        memory="-m 1.2T"
                        ;;       
                    pcie-root)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        EQ_PCIE_ROOT_PORTS=val
                        add_pcie_root_ports_devices
                        ;; 
                    pl)
                        pl_mode=true
                        ;;               
                    usb)
                        usb_mouse="-usb -device usb-tablet,id=tablet1"
                        ;;  
                    fips)
                        EQ_FIPS=true
                        ;;
                    sev)
                        EQ_SEV=true
                        cpu="-cpu host,+host-phys-bits"
                        EQ_IOMMU_PLAT=",disable-legacy=on,iommu_platform=true"
                        ;;
                   *)
                      echo "Unknown option --${OPTARG}"
                      exit 1
                      ;;
                esac;;
            a)
                add_args=${OPTARG}
                ;;
            o)
                EQ_OS_VERSION=${OPTARG}
                name="-name OL${EQ_OS_VERSION}-uefi"
                log_file="-D ./OL${EQ_OS_VERSION}-uefi.log"
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
               vga="-vga ${OPTARG}"
               ;;
            q)
               # check if it is not a number i.e. port number
               re='^[0-9]+$' 
               if ! [[ $OPTARG =~ $re ]] ; then
                    qmp_sock="-qmp unix:${OPTARG},server,nowait" # unix socket
               else
                    qmp_sock="-qmp tcp:127.0.0.1:${OPTARG},server,nowait"
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
                no_defaults=""
                ;;
            C)
                cpu="-cpu ${OPTARG}"
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
                memory="-m ${OPTARG}"
                ;;
            P)
                smp="-smp ${OPTARG}"
                ;;
            s)
                serial="-serial telnet:127.0.0.1:${OPTARG},server,nowait"
                ;;
            v)
               vnc="-vnc :${OPTARG}"
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
    add_args=""
    secure_boot=false
    secure_boot_debug=false
    name="-name OL${EQ_OS_VERSION}-uefi"
    cpu="-cpu host"
    no_defaults="-nodefaults"
    memory="-m 8G"
    smp="-smp 8,maxcpus=240"
    monitor="-monitor stdio"
    vnc="-vnc 0.0.0.0:0,to=999"
    qmp_sock="-qmp tcp:127.0.0.1:3334,server,nowait"
    serial="-serial telnet:127.0.0.1:3333,server,nowait"
    EQ_CONTROLLER="virtio-scsi-pci"
    EQ_VIRTIO_DEVICE="-device virtio-scsi-pci,id=virtio-scsi-pci0"
    log_file="-D ./OL${EQ_OS_VERSION}-uefi.log"
    usb_mouse=""
    daemonize=""
    ihc9=""
    EQ_IPXE=false
    EQ_DEBUG_CON=""
    # Architecture specific settings
    if [[ "${EQ_ARCH}" == "x86_64" ]]; 
    then 
        EQ_MACHINE="-machine pc,accel=kvm"; 
        vga="-vga std"
        ahci=""
    else 
        EQ_MACHINE="-machine virt,accel=kvm,gic-version=3"; 
        vga="-device virtio-gpu-pci -device usb-ehci -device usb-kbd -device usb-mouse"
        ahci="-device ahci,id=ahci0"
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
            iscsi_initiator_val="-iscsi initiator-name=${EQ_ISCSI_INITIATOR}"
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
        net="-net none -device vfio-pci,host=${EQ_PCI_BUS}"
        if [[ "${EQ_IPXE}" == "true" ]]; then
            net=$(printf %s "-device vfio-pci,host=${EQ_PCI_BUS},id=ipxe-nic,"\
                "romfile=${EQ_ROM_FILE} -boot n")
            if [[ "$ARCH" == "aarch64"  ]]; then
                net=$(printf %s "-device pcie-root-port,id=root,slot=0 "\
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
        net=$(printf %s "-netdev tap,"\
            "id=${EQ_NETWORK},fd=3 3<>/dev/tap$(< /sys/class/net/${EQ_NETWORK}/ifindex) "\
            "-device virtio-net-pci,mac=$(< /sys/class/net/${EQ_NETWORK}/address),"\
            "id=virtio-net-pci0,vectors=482,mq=on,netdev=${EQ_NETWORK}${ipxe_param}${EQ_IOMMU_PLAT}")
        if [[ -n "${EQ_NIC_MODEL}" ]]; then 
            net=$(printf %s "-net nic,model=${EQ_NIC_MODEL},"\
                "macaddr=$(cat /sys/class/net/${EQ_NETWORK}/address) "\
                "-net tap,fd=3 3<>/dev/tap$(cat /sys/class/net/${EQ_NETWORK}/ifindex)")
        fi
    elif [[ "${EQ_NETWORK}" == "user" ]]; then
        net="-net nic -net user,id=net0,hostfwd=tcp::2222-:22"
    else
        net=""
        echo "NO NETWORK"
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

qemu_cmd_to_file()
{
    content='#!/bin/bash\n\n'
    content="${content}${EQ_QEMU_CMD} ${name} \\\\\n"
    content="${content}${EQ_MACHINE} \\\\\n"
    content="${content}-enable-kvm \\\\\n"
    content="${content}${cpu} \\\\\n"
    content="${content}${memory} \\\\\n"
    content="${content}${smp} \\\\\n"
    content="${content}${log_file} \\\\\n"
    [[ ! -z  $no_defaults  ]] && content="${content}${no_defaults} \\\\\n"
    [[ ! -z  $monitor  ]] && content="${content}${monitor} \\\\\n"
    content="${content}${vnc} \\\\\n"
    content="${content}${vga} \\\\\n"
    content="${content}${edk2_drives} \\\\\n"
    [[ ! -z  ${EQ_VIRTIO_DEVICE}  ]] && content="${content}${EQ_VIRTIO_DEVICE} \\\\\n"
    [[ ! -z  $ahci  ]] && content="${content}${ahci} \\\\\n"
    [[ ! -z  ${EQ_LOCAL_DISK_PARAM}  ]] && content="${content}${EQ_LOCAL_DISK_PARAM} \\\\\n"
    [[ ! -z  ${EQ_BLOCK_DEVS}  ]] && content="${content}${EQ_BLOCK_DEVS} \\\\\n"
    [[ ! -z  ${iscsi_initiator_val}  ]] && content="${content}${iscsi_initiator_val} \\\\\n"
    [[ ! -z  ${EQ_SCSI_DRIVES}  ]] && content="${content}${EQ_SCSI_DRIVES} \\\\\n"
    [[ ! -z  ${EQ_PCIE_ROOT_DEVICES}  ]] && content="${content}${EQ_PCIE_ROOT_DEVICES} \\\\\n"
    [[ ! -z  $cdrom  ]] && content="${content}${cdrom} \\\\\n"
    [[ ! -z  $net  ]] && content="${content}${net} \\\\\n"
    [[ ! -z  $ihc9  ]] && content="${content}${ihc9} \\\\\n"
    [[ ! -z  $qmp_sock  ]] && content="${content}${qmp_sock} \\\\\n"
    [[ ! -z  $serial  ]] && content="${content}${serial} \\\\\n"
    [[ ! -z  ${EQ_TPM_CMD}  ]] && content="${content}${EQ_TPM_CMD} \\\\\n"
    [[ ! -z  $daemonize  ]] && content="${content}${daemonize} \\\\\n" 
    [[ ! -z  $usb_mouse  ]] && content="${content}${usb_mouse} \\\\\n"
    [[ ! -z  $add_args  ]] && content="${content}${add_args} \\\\\n"
    [[ ! -z  ${EQ_SEV_ARGS}  ]] && content="${content}${EQ_SEV_ARGS} \\\\\n"
    
    
    echo -e ${content} > OL${EQ_OS_VERSION}-uefi.sh
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
            ihc9="-global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1"
        fi
    fi 
    if "$secure_boot_debug" ; then 
        mode="secboot-debug."
        if [ "${EQ_ARCH}" != "aarch64" ];
        then
            ihc9="-global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1"
            EQ_DEBUG_CON="-debugcon file:ovmf_debug.log -global isa-debugcon.iobase=0x402"
        fi
    fi
    local ovmf_var_file="${EQ_EDK2_DIR}/OVMF_VARS${mode}fd"
    if [[ ! -f "${ovmf_var_file}" ]]; then
        ovmf_var_file="${EQ_EDK2_DIR}/OVMF_VARS.fd"
    fi 
    cp -f ${ovmf_var_file} OVMF_VARS.${EQ_OS_VERSION}
    edk2_drives="-drive file=${EQ_EDK2_DIR}/OVMF_CODE${mode}fd,index=0,if=pflash,format=raw,readonly \
    -drive file=OVMF_VARS.${EQ_OS_VERSION},index=1,if=pflash,format=raw"
}

ipxe_settings()
{
    if [[ "${EQ_IPXE}" == "true" ]]; then
        ahci="" 
        EQ_LOCAL_DISK_PARAM=""
        EQ_BLOCK_DEVS=""
        EQ_SCSI_DRIVES=""   
    fi
}

pre_launch_mode_settings()
{
    EQ_VIRTIO_DEVICE=''
    ahci="" 
    EQ_LOCAL_DISK_PARAM=""
    pcie_root_bus=''
    pre_launch_option="-S"
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
    cdrom="-cdrom ${EQ_ISO} -boot d"
    if [[ ("${EQ_LAUNCH_MODE}" == "local") && ( ! -z "${EQ_CUSTOM_IMAGE}" ) ]]
    then
        EQ_BLOCK_DEVS="-drive file=${EQ_CUSTOM_IMAGE},if=none,id=local_disk0,media=disk -device ide-hd,drive=local_disk0,id=local_disk1"
    fi
else
    cdrom=""
    [[ "${EQ_LOCAL_BOOT}" == "true" ]] && set_local_disk
    if [[ "${EQ_LAUNCH_MODE}" == "iscsi" ]]
    then
        set_scsi_disks ${EQ_BOOT_LUN}
    fi
fi

ipxe_settings 

($pl_mode) && pre_launch_mode_settings
[[ "${EQ_SEV}"  == "true" ]] && enable_sev

vm_launch_cmd="${EQ_QEMU_CMD} ${EQ_MACHINE} ${name} -enable-kvm ${no_defaults} ${cpu} ${memory} ${smp} ${monitor} ${vnc} ${vga} ${edk2_drives} ${EQ_VIRTIO_DEVICE} ${ihc9} ${EQ_DEBUG_CON} ${ahci} ${EQ_LOCAL_DISK_PARAM} ${EQ_BLOCK_DEVS} ${iscsi_initiator_val} ${EQ_SCSI_DRIVES} ${EQ_PCIE_ROOT_DEVICES} ${cdrom} ${net} ${qmp_sock} ${serial} ${EQ_TPM_CMD} ${log_file} ${daemonize} ${usb_mouse} ${add_args} ${pre_launch_option} ${EQ_SEV_ARGS}"

echo -e "QEMU Command:\n${vm_launch_cmd}"
echo -e ${vm_launch_cmd} > qemu-cmd-latest-noformat
qemu_cmd_to_file

eval "$vm_launch_cmd"
