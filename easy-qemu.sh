#!/bin/bash

EQ_CONFIG_FILE="config"
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

QEMU_CMD=""
nic_model="e1000"
nic_model_set=false
ubuntu=false
ubuntu_host=false
centos=false
pci_bus=""
boot_lun=3
initial_lun=7
end_lun=13

local_disk=""
local_disk_type="ide"
telnet_port=4444
mode="local"
tpm=false
tpm_cmd=""
pcie_root_ports=10
pcie_root_devices=''
pl_mode=false
pre_launch_option=''
iommu_plat=''
fips=false
sev=false

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
    echo "-N                NIC model. Use qemu-system-<arch> -nic model=help to get the list. (default: e1000)"
    echo "-b                PCI bus id. Required if -n is set to \"vf\"."
    echo "-B                blockdev iscsi mode."
    echo "-s                Add telnet serial console on the chosen local port. Requires port number. (default: 3333)"
    echo "-S                iScsi settings. <portal_ip>,<iscsi_target>,<iscsi_initiator>"
    echo "-u                Use it to for Ubuntu instalation"
    echo "-U                Use it if host system is Ubuntu"
    echo "-v                vnc port"
    echo "-D                Remove -nodefaults for qemu command line"
    echo "-d                Boot from local disk. Optoins: ide | virtio-scsi | virtio-blk (default:  ide)"
    echo "-M                Memory for VM (default: 8G)"
    echo "-m                Launch mode. \"iscsi\" or \"local\" (default: iscsi)"
    echo "-C                Qemu cpu option (default: host)"
    echo "-c                Option to choose virio-scsi-pci or lsi controller. (defualt: virtio-scsi-pci)"
    echo "-P                Qemu smp option. (default: 8)"
    echo "-T                Start VM with TPM."
    echo "-t                iScsi device type i.e. scsi-block or scsi-hd. (default: scsi-block)"
    echo "-q                Specify qmp port or unix socket file (e.g. /tmp/my_qmp_sock). (default port: 3334)"
    echo "--iso             Specify ISO image for installation."
    echo "--iscsi [boot]    Attach ISCSI disks. Add 'boot' to boot from an ISCSI disk."
    echo "--cos             To specify CentOS image"
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
    while getopts "a:o:l:b:n:S:v:c:t:g:s:m:q:N:M:C:P:O:i:TeduUBDh-:" opt; do
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
                        mode="iscsi"
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
                        machine="-machine ${val}"; 
                        ;;        
                    secboot)
                        secure_boot=true
                        ;;
                    secboot-debug)
                        secure_boot_debug=true
                        ;;
                    ipxe)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        rom_file=${val}
                        ipxe=true
                        ;;
                    big-vm)
                        cpu="-cpu host,+host-phys-bits"
                        memory="-m 1.2T"
                        ;;       
                    pcie-root)
                        val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                        pcie_root_ports=val
                        add_pcie_root_ports_devices
                        ;; 
                    pl)
                        pl_mode=true
                        ;;               
                    usb)
                        usb_mouse="-usb -device usb-tablet,id=tablet1"
                        ;;  
                    fips)
                        fips=true
                        export OPENSSL_FORCE_FIPS_MODE=1
                        ;;
                    sev)
                        sev=true
                        cpu="-cpu host,+host-phys-bits"
                        iommu_plat=",disable-legacy=on,iommu_platform=true"
                        ;;
                    cos)
                        centos=true
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
               pci_bus=${OPTARG}
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
                nic_model=${OPTARG}
                nic_model_set=true
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
                virtio_device="-device ${EQ_CONTROLLER},id=${EQ_CONTROLLER}0"
                ;;
            d)
                EQ_LOCAL_BOOT=true
                # Check next positional parameter
                eval nextopt=\${$OPTIND}
                # existing or starting with dash?
                if [[ -n $nextopt && $nextopt != -* ]] ; then
                  OPTIND=$((OPTIND + 1))
                  local_disk_type=$nextopt
                else
                  local_disk_type="ide"
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
            u)
                ubuntu=true
                ;;
            U)
                ubuntu_host=true
                ;;
            v)
               vnc="-vnc :${OPTARG}"
               ;;
            T)
               tpm=true
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
    virtio_device="-device virtio-scsi-pci,id=virtio-scsi-pci0"
    log_file="-D ./OL${EQ_OS_VERSION}-uefi.log"
    usb_mouse=""
    daemonize=""
    ihc9=""
    ipxe=false
    debug_con=""
    # Architecture specific settings
    if [ "${EQ_ARCH}" == "x86_64" ]; 
    then 
        machine="-machine pc,accel=kvm"; 
        vga="-vga std"
        ahci=""
    else 
        machine="-machine virt,accel=kvm,gic-version=3"; 
        vga="-device virtio-gpu-pci -device usb-ehci -device usb-kbd -device usb-mouse"
        ahci="-device ahci,id=ahci0"
    fi
}

get_qemu() 
{
    host_ol_ver=$(cat /etc/*release | grep VERSION_ID | cut -d'=' -f2 | sed 's/"//g' | grep -o "^.")
    
    if [ "${EQ_ARCH}" = "x86_64" ]; then
        QEMU_CMD=qemu-system-x86_64
    elif [ "${EQ_ARCH}" = "aarch64" ]; then
        QEMU_CMD=qemu-system-aarch64
    else
        echo -e "This script does not support this architecture.\n"
    fi
    [[ "$host_ol_ver" == "8" || "$host_ol_ver" == "9" ]] && QEMU_CMD=/usr/libexec/qemu-kvm #cater for OL8
    if command -v $QEMU_CMD &> /dev/null
    then
        QEMU_CMD=$(command -v $QEMU_CMD)
        echo -e "\e[34mHypervisor    : \e[39m$(${QEMU_CMD} --version | grep -i emul)"
    else
        echo "\e[34mHypervisor    : \e[31mQemu not found on the system.\n\e[39m"
        exit 1
    fi
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
    if [ "${local_disk_type}" == "ide" ]; then
        local_disk="-drive file=${EQ_CUSTOM_IMAGE},if=none,id=local_disk0,media=disk -device ide-hd,drive=local_disk0,id=local_disk1,bootindex=0"
        if [ "${EQ_ARCH}" == "aarch64" ]; 
        then
            local_disk="-hda ${EQ_CUSTOM_IMAGE} -boot order=c,menu=on"
        fi
    elif [ "${local_disk_type}" == "virtio-scsi" ]; then
        local_disk="-drive file=${EQ_CUSTOM_IMAGE},if=none,id=virtscsi_disk,media=disk -device scsi-hd,drive=virtscsi_disk,bus=${EQ_CONTROLLER}0.0,id=local_disk0,bootindex=0"
    elif [ "${local_disk_type}" == "virtio-blk" ]; then
        local_disk="-drive file=${EQ_CUSTOM_IMAGE},if=none,id=virtblk_disk,media=disk -device virtio-blk-pci,drive=virtblk_disk,id=local_disk0,bootindex=0"
    else
        echo -e "\e[31m${local_disk_type} is invalid storage device type for -d \n\e[39m"
        exit 1 
    fi
    
    echo -e "Using ${EQ_CUSTOM_IMAGE} image to boot from disk."
}

start_tpm()
{
    echo -e "\e[32mStarting TPM\e[39m"
    tpm_dir=/tmp/measured-boot
    mkdir -p ${tpm_dir}/nvram_v1/
    ($fips) && fips_mode="OPENSSL_FORCE_FIPS_MODE=1" || fips_mode=""
    swtpm_cmd="${fips_mode} swtpm socket --tpmstate dir=${tpm_dir}/nvram_v1/ --ctrl type=unixio,path=${tpm_dir}/swtpm-sock --tpm2 --log file=${tpm_dir}/mytpm.log,level=20,truncate --daemon"
    echo "swtpm command: ${swtpm_cmd}"
    eval "$swtpm_cmd"

    tpm_cmd="-chardev socket,id=chrtpm0,path=${tpm_dir}/swtpm-sock -tpmdev emulator,id=tpm0,chardev=chrtpm0 -device tpm-tis,tpmdev=tpm0"
    tpm_cmd="${tpm_cmd} -global ICH9-LPC.disable_s3=1 -global ICH9-LPC.disable_s4=1"
    tpm_cmd="${tpm_cmd} -chardev pty,id=charserial1 -device isa-serial,chardev=charserial1,id=serial1 -global driver=cfi.pflash01,property=secure,value=on"
    debug_con="-debugcon file:${tpm_dir}/ovmf_debug.log -global isa-debugcon.iobase=0x402"
}

set_network()
{
    if [ "${EQ_NETWORK}" == "vf" ]; then
        if [[ -z "${pci_bus}" ]]; then
            echo -e "\n-n flag requires -b flag.\n"
            exit 1
        fi
        net="-net none -device vfio-pci,host=${pci_bus}"
        if "$ipxe" ; then
            net="-device vfio-pci,host=${pci_bus},id=ipxe-nic,romfile=${rom_file} -boot n"
            if [ "$ARCH" = "aarch64"  ]; then
                net="-device pcie-root-port,id=root,slot=0 -device vfio-pci,host=${pci_bus},id=ipxe-nic,romfile=${rom_file} -boot n"
            fi
        fi
    elif [[ "${EQ_NETWORK}" == "macvtap"* ]]; then
        ipxe_param=''
        if "$ipxe" ; then
            ipxe_param=",romfile=${rom_file}"
        fi
        if "$sev" ; then
            ipxe_param=",romfile=''"
        fi
        net="-netdev tap,id=${EQ_NETWORK},fd=3 3<>/dev/tap$(< /sys/class/net/${EQ_NETWORK}/ifindex) \
        -device virtio-net-pci,mac=$(< /sys/class/net/${EQ_NETWORK}/address),id=virtio-net-pci0,vectors=482,mq=on,netdev=${EQ_NETWORK}${ipxe_param}${iommu_plat}"
        if "$nic_model_set" ; then 
            net="-net nic,model=${nic_model},macaddr=$(cat /sys/class/net/${EQ_NETWORK}/address) \
            -net tap,fd=3 3<>/dev/tap$(cat /sys/class/net/${EQ_NETWORK}/ifindex)"
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
    if [[ "${machine}" == "-machine q35" || "${machine}" == "-machine virt,accel=kvm,gic-version=3" ]]; then
        echo "${machine}"
        range=$((pcie_root_ports + 5))
        for ((i=5;i<range;i++)); do
            addr=$( printf "%x" ${i} )
            pcie_root_devices="${pcie_root_devices} -device pcie-root-port,port=${i},chassis=${i},id=pciroot${i},bus=pcie.0,addr=0x${addr}"
        done
    fi
}

qemu_cmd_to_file()
{
    content='#!/bin/bash\n\n'
    content="${content}${QEMU_CMD} ${name} \\\\\n"
    content="${content}${machine} \\\\\n"
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
    [[ ! -z  $virtio_device  ]] && content="${content}${virtio_device} \\\\\n"
    [[ ! -z  $ahci  ]] && content="${content}${ahci} \\\\\n"
    [[ ! -z  $local_disk  ]] && content="${content}${local_disk} \\\\\n"
    [[ ! -z  ${EQ_BLOCK_DEVS}  ]] && content="${content}${EQ_BLOCK_DEVS} \\\\\n"
    [[ ! -z  ${iscsi_initiator_val}  ]] && content="${content}${iscsi_initiator_val} \\\\\n"
    [[ ! -z  ${EQ_SCSI_DRIVES}  ]] && content="${content}${EQ_SCSI_DRIVES} \\\\\n"
    [[ ! -z  $pcie_root_devices  ]] && content="${content}${pcie_root_devices} \\\\\n"
    [[ ! -z  $cdrom  ]] && content="${content}${cdrom} \\\\\n"
    [[ ! -z  $net  ]] && content="${content}${net} \\\\\n"
    [[ ! -z  $ihc9  ]] && content="${content}${ihc9} \\\\\n"
    [[ ! -z  $qmp_sock  ]] && content="${content}${qmp_sock} \\\\\n"
    [[ ! -z  $serial  ]] && content="${content}${serial} \\\\\n"
    [[ ! -z  $tpm_cmd  ]] && content="${content}${tpm_cmd} \\\\\n"
    [[ ! -z  $daemonize  ]] && content="${content}${daemonize} \\\\\n" 
    [[ ! -z  $usb_mouse  ]] && content="${content}${usb_mouse} \\\\\n"
    [[ ! -z  $add_args  ]] && content="${content}${add_args} \\\\\n"
    [[ ! -z  $sev_args  ]] && content="${content}${sev_args} \\\\\n"
    
    
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
            debug_con="-debugcon file:ovmf_debug.log -global isa-debugcon.iobase=0x402"
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
    if "$ipxe" ; then
        ahci="" 
        local_disk=""
        EQ_BLOCK_DEVS=""
        EQ_SCSI_DRIVES=""   
    fi
}

pre_launch_mode_settings()
{
    virtio_device=''
    ahci="" 
    local_disk=""
    pcie_root_bus=''
    pre_launch_option="-S"
    if [[ "${machine}" == "-machine q35" ]]; then
        pcie_root_devices="${pcie_root_devices} -device pcie-root-port,port=4,chassis=4,id=pciroot4,bus=pcie.0,addr=0x4"
        pcie_root_bus=",bus=pciroot4"
    fi
    
    echo "Qemu starting in prelaunch mode. Use following disk hotplug commands to start the guest:"
    echo "(qemu) drive_add auto file=${EQ_CUSTOM_IMAGE},id=drive2,aio=threads,cache=writeback,if=none"
    echo "(qemu) device_add virtio-scsi-pci,id=virtio-scsi-pci2${pcie_root_bus}${iommu_plat}"
    echo "(qemu) device_add scsi-hd,id=scsi-hd2,drive=drive2"
    echo "(qemu) c"
}

get_c_bit()
{
   yum install cpuid -y -q
   text=$(cpuid -r -1 -l 0x8000001f)
   search="ebx"
   prefix=${text%%$search*}
   ebx_index=$((${#prefix} + 4))
   ebx_val=${text:${ebx_index}:10}
   mask=$(( (1 << 6) -1 ))
   c_bit=$(( $ebx_val & mask ))
}


enable_sev()
{
    
    get_c_bit
    sev_args="-device virtio-rng-pci,disable-legacy=on,iommu_platform=true -object sev-guest,id=sev0,cbitpos=${c_bit},reduced-phys-bits=1 -machine memory-encryption=sev0"
    virtio_device="-device virtio-scsi-pci,id=virtio-scsi-pci0${iommu_plat}"
}

set_defaults
get_options "$@"
get_host_info
set_network
($tpm) && start_tpm || tpm_cmd=""
copy_edk2_files

if [[ "${EQ_INSTALL}" == "true" ]]; then
    get_iso
    EQ_BLOCK_DEVS=$(printf %s "-blockdev driver=iscsi,transport=tcp,"\
            "portal=${EQ_ISCSI_PORTAL_IP}:3260,initiator-name=${EQ_ISCSI_INITIATOR},"\
            "target=${EQ_ISCSI_TARGET},lun=${EQ_BOOT_LUN},node-name=oci-bm-iscsi,"\
            "cache.no-flush=off,cache.direct=on,read-only=off "\
            "-device ${EQ_SCSI_DEVICE_TYPE},bus=${EQ_CONTROLLER}0.0,id=disk1,drive=oci-bm-iscsi")
    cdrom="-cdrom ${EQ_ISO} -boot d"
    if [[ ("${mode}" == "local") && ( ! -z "${EQ_CUSTOM_IMAGE}" ) ]]
    then
        EQ_BLOCK_DEVS="-drive file=${EQ_CUSTOM_IMAGE},if=none,id=local_disk0,media=disk -device ide-hd,drive=local_disk0,id=local_disk1"
    fi
else
    cdrom=""
    [[ "${EQ_LOCAL_BOOT}" == "true" ]] && set_local_disk
    if [[ "${mode}" == "iscsi" ]]
    then
        set_scsi_disks ${EQ_BOOT_LUN}
    fi
fi

ipxe_settings 

($pl_mode) && pre_launch_mode_settings
($sev) && enable_sev

vm_launch_cmd="${QEMU_CMD} ${machine} ${name} -enable-kvm ${no_defaults} ${cpu} ${memory} ${smp} ${monitor} ${vnc} ${vga} ${edk2_drives} ${virtio_device} ${ihc9} ${debug_con} ${ahci} ${local_disk} ${EQ_BLOCK_DEVS} ${iscsi_initiator_val} ${EQ_SCSI_DRIVES} ${pcie_root_devices} ${cdrom} ${net} ${qmp_sock} ${serial} ${tpm_cmd} ${log_file} ${daemonize} ${usb_mouse} ${add_args} ${pre_launch_option} ${sev_args}"

echo -e "QEMU Command:\n${vm_launch_cmd}"
echo -e ${vm_launch_cmd} > qemu-cmd-latest-noformat
qemu_cmd_to_file

eval "$vm_launch_cmd"
