#!/bin/bash

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