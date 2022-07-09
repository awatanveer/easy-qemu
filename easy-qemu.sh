#!/bin/bash

# Copyright 2022 Awais Tanveer

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
EQ_QMP_SOCK_VAL=""

source ./utils.sh

usage()
{
    if [[ -f usage ]]; then
        cat usage
        exit 0
    fi
    exit 1
}

get_options() 
{
    local OPTIND opt
    while getopts "a:o:l:b:n:S:v:c:t:g:s:q:N:M:C:P:O:i:TeduUBDh-:" opt; do
        case "${opt}" in -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                iso)  EQ_INSTALL=true; EQ_ISO="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 )) ;;
                stdio) EQ_MONITOR="-display none -serial stdio"; EQ_SERIAL="" ;;
                log) val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 )); EQ_LOG_FILE="-D ${val}" ;;
                bg) EQ_DAEMONIZE="-daemonize"; EQ_MONITOR="" ;;
                machine) EQ_MACHINE="-machine ${!OPTIND}" OPTIND=$(( $OPTIND + 1 )) ;;        
                secboot) secure_boot=true ;;
                secboot-debug) secure_boot_debug=true ;;
                ipxe) EQ_ROM_FILE=${!OPTIND}; OPTIND=$(( $OPTIND + 1 )); EQ_IPXE=true ;;
                big-vm) EQ_CPU="-cpu host,+host-phys-bits"; EQ_MEMORY="-m 1.2T" ;;
                pl) EQ_PRE_LAUNCH_MODE=true ;;               
                usb) EQ_USB_MOUSE="-usb -device usb-tablet,id=tablet1" ;;  
                fips) EQ_FIPS=true ;;   
                sev) EQ_SEV=true ;;
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
                pcie-root) 
                        EQ_PCIE_ROOT_PORTS=${!OPTIND}; OPTIND=$(( $OPTIND + 1 )); 
                        add_pcie_root_ports_devices 
                    ;; 
                *)
                    echo "Unknown option --${OPTARG}"
                    exit 1
                    ;;
            esac;;
            a) EQ_ADDITIONAL_ARGS=${OPTARG} ;;
            O) EQ_CUSTOM_IMAGE=${OPTARG} ;;
            b) EQ_PCI_BUS=${OPTARG} ;;
            g) EQ_VGA="-vga ${OPTARG}" ;;
            N) EQ_NIC_MODEL=${OPTARG}  ;;
            B) EQ_SCSI_DRIVE_MODE=false ;;
            D) EQ_NO_DEFAULTS="" ;;
            C) EQ_CPU="-cpu ${OPTARG}" ;;
            M) EQ_MEMORY="-m ${OPTARG}" ;;
            P) EQ_SMP="-smp ${OPTARG}"  ;;
            s) EQ_SERIAL="-serial telnet:127.0.0.1:${OPTARG},server,nowait" ;;
            v) EQ_VNC="-vnc :${OPTARG}" ;;
            T) EQ_TPM=true ;;
            t) EQ_SCSI_DEVICE_TYPE=${OPTARG} ;;
            l) EQ_LUNS=${OPTARG} ;;
            n) EQ_NETWORK=${OPTARG} ;;
            o) EQ_OS_VERSION=${OPTARG} ;;
            q) EQ_QMP_SOCK_VAL=${OPTARG} ;;
            h) usage ;;
            c) EQ_CONTROLLER=${OPTARG} ;;
            d)
                EQ_LOCAL_BOOT=true
                # Check next positional parameter
                eval nextopt=\${$OPTIND}
                # existing or starting with dash?
                if [[ -n "${nextopt}" && "${nextopt}" != -* ]] ; then
                  OPTIND=$((OPTIND + 1))
                  EQ_LOCAL_DISK_TYPE=$nextopt
                else
                  EQ_LOCAL_DISK_TYPE="ide"
                fi
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
   # TODO: Should download the distribution iso identified ideally by -o option 
   echo ""
}

parse_lun_array()
{
    if [[ -n "${EQ_LUNS}" ]]; then
        EQ_LUN_ARRAY=(${EQ_LUNS//,/ })
        EQ_BOOT_LUN=${EQ_LUN_ARRAY[0]}
    else
        EQ_BOOT_LUN=${EQ_BOOT_LUN}
    fi
}

set_scsi_disks() 
{
    local boot_index=""
    parse_lun_array
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
    [[ "${EQ_NETWORK}" == "false" ]] && return 0
    if [[ "${EQ_NETWORK}" != *"macvtap"*  && \
        "${EQ_NETWORK}" != "vf" && \
        "${EQ_NETWORK}" != "user" ]]; then
        echo -e "\n${EQ_NETWORK} is invalid option for -n\n"
        exit 1
    fi
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

create_qemu_command()
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
    cp -f ${ovmf_var_file} OVMF_VARS.${EQ_OS_VERSION}.fd
    EQ_EDK2_DRIVES=$(printf %s "-drive file=${EQ_EDK2_DIR}/OVMF_CODE${mode}fd,index=0,"\
                    "if=pflash,format=raw,readonly -drive file=OVMF_VARS.${EQ_OS_VERSION}.fd,"\
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

set_qmp()
{
    if [[ -n "${EQ_QMP_SOCK_VAL}" ]]; then
        local re='^[0-9]+$'
        # Check if it is not a number i.e. port number
        if [[ ${EQ_QMP_SOCK_VAL} =~ $re ]]; then
            EQ_QMP_SOCK="-qmp tcp:127.0.0.1:${EQ_QMP_SOCK_VAL},server,nowait"
        else
            EQ_QMP_SOCK="-qmp unix:${EQ_QMP_SOCK_VAL},server,nowait" # unix socket
        fi
    fi
}

enable_sev()
{
    EQ_CPU="-cpu host,+host-phys-bits" 
    EQ_IOMMU_PLAT=",disable-legacy=on,iommu_platform=true"
    EQ_SEV_ARGS=$(printf %s "-device virtio-rng-pci,disable-legacy=on,"\
                "iommu_platform=true -object sev-guest,id=sev0,cbitpos=$(get_c_bit),"\
                "reduced-phys-bits=1 -machine memory-encryption=sev0")
    EQ_VIRTIO_DEVICE="-device virtio-scsi-pci,id=virtio-scsi-pci0${EQ_IOMMU_PLAT}"
}

iso_install()
{
    parse_lun_array
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
            EQ_BLOCK_DEVS=$(printf %s "-drive file=${EQ_CUSTOM_IMAGE},if=none,id=local_disk0,"\
                            "media=disk -device ide-hd,drive=local_disk0,id=local_disk1")
        fi
    else
        EQ_CDROM=""
        [[ "${EQ_LOCAL_BOOT}" == "true" ]] && set_local_disk
        if [[ "${EQ_LAUNCH_MODE}" == "iscsi" ]]
        then
            set_scsi_disks ${EQ_BOOT_LUN}
        fi
    fi
}

main()
{
    local vm_launch_cmd=""
    set_defaults
    get_options "$@"
    get_host_info
    set_network
    copy_edk2_files
    iso_install
    ipxe_settings
    set_qmp
    EQ_VIRTIO_DEVICE="-device ${EQ_CONTROLLER},id=${EQ_CONTROLLER}0"
    [[ "$EQ_TPM" == "true" ]] && start_tpm || EQ_TPM_CMD="" 
    [[ "${EQ_PRE_LAUNCH_MODE}" == "true" ]] && pre_launch_mode_settings
    [[ "${EQ_SEV}"  == "true" ]] && enable_sev
    vm_launch_cmd=$(create_qemu_command)
    echo -e "QEMU Command:\n${vm_launch_cmd}"
    echo -e ${vm_launch_cmd} > qemu-cmd-latest-noformat
    eval "$vm_launch_cmd"
}

main "$@"