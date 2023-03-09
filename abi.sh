#!/bin/bash
###############################################################################################################
# MAINTAINER: midu@redhat.com
#
# Prerequisite
# - Offline Registry has been configured and its reachable from the host this script is run
# - RHCOS_Cache has been configured and its reachable from the host this script is run
#
# This script is available ONLY for OCP GA versions. Any other releaseases are not supported.
###############################################################################################################

# defining the keyboard input variables
helpFunction()
{
   echo ""
   echo "Usage: $0 -a /apps/registry/pull-secret.json -b parameterB -c parameterC"
   echo -e "\t-a This parameter is requiring the path to the pull-secret.json. Example: /apps/registry/pull-secret.json. Please note, that the pull-secret.json should inlcude the public and also private registry information."
   echo -e "\t-b This parameter is requiring the OpenShift Container Platform version to be installed. Example: 4.12.2"
   echo -e "\t-c This parameter is requiring the cluster-plan.yaml. Example: /apps/registry/cluster-plan.yaml"
   echo -e "\t-d The use of this parameter its enabling fully disconnected mode. The Offline Registry and RHCOS Cache are assumed completed. Example: True. Default value is set to False"
   exit 1 # Exit script after printing help
}

while getopts "a:b:c:d:" opt
do
    export DEFAULT="False"
   case "$opt" in
      a ) parameterA="${OPTARG}" ;;
      b ) parameterB="${OPTARG}" ;;
      c ) parameterC="${OPTARG}" ;;
      d ) parameterD="${OPTARG:-${DEFAULT}}" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$parameterA" ] || [ -z "$parameterB" ] || [ -z "$parameterC" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

# Begin script in case all parameters are correct
function debugg_param() {
  echo "$parameterA"
  echo "$parameterB"
  echo "$parameterC"
  echo "${parameterD:-${DEFAULT}}"
}

# This is a function that will parse the cluster-plan.yaml and translate it to global variables below
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|,$s\]$s\$|]|" \
        -e ":1;s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s,$s\(.*\)$s\]|\1\2: [\3]\n\1  - \4|;t1" \
        -e "s|^\($s\)\($w\)$s:$s\[$s\(.*\)$s\]|\1\2:\n\1  - \3|;p" $1 | \
   sed -ne "s|,$s}$s\$|}|" \
        -e ":1;s|^\($s\)-$s{$s\(.*\)$s,$s\($w\)$s:$s\(.*\)$s}|\1- {\2}\n\1  \3: \4|;t1" \
        -e    "s|^\($s\)-$s{$s\(.*\)$s}|\1-\n\1  \2|;p" | \
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)-$s[\"']\(.*\)[\"']$s\$|\1$fs$fs\2|p" \
        -e "s|^\($s\)-$s\(.*\)$s\$|\1$fs$fs\2|p" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" | \
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]; idx[i]=0}}
      if(length($2)== 0){  vname[indent]= ++idx[indent] };
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) { vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, vname[indent], $3);
      }
   }'
}

# parsing the cluster-plan.yaml file to the CONFIG_* global variables
eval $(parse_yaml $parameterC "CONFIG_")

# defining the global variables
export LOCAL_REPO="ocp-release"
export PULLSECRET_FILE=$parameterA
# we are going to use the localhost and port 5000 because this mirror will happen inside the registry container
export LOCAL_REG="${CONFIG_global_offline_registry_fqdn}:${CONFIG_global_port_offline_registry_fqdn}"
# validating that the pull secret exists on the mention path, othewise exit the process
if [[ -f "$PULLSECRET_FILE" ]]; then
    echo "$PULLSECRET_FILE exists in the mentioned path!"
    export LOCAL_REG_AUTH="$(cat ${PULLSECRET_FILE} | jq .auths.\"${LOCAL_REG}\".auth -r)"
else 
    echo -e "\n+ $PULLSECRET_FILE DOES NOT exists in the mentioned path!"
    exit 1
fi
export LOCAL_RHCOS_CACHE="${CONFIG_global_rhcos_cache_fqdn}:${CONFIG_global_port_rhcos_cache_fqdn}"
export OCP_VERSION=$parameterB
export VERSION=${OCP_VERSION}-x86_64
export ICSP_NAME="ocp-${VERSION}"
export WORKING_DIR=$(pwd)

if [[ "${parameterD:-${DEFAULT}}" == "False" ]]; then
    # validating that the localhost can reach the mirror.openshift.com registry to download the pre-requisites
    status_code=$(curl --write-out %{http_code} --silent --output /dev/null https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz)
    if [[ "$status_code" -ne 200 ]] ; then
        echo "Site status changed to $status_code"
    else
        echo "Downloading the oc binary ${OCP_VERSION}"
        curl -O -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz ${WORKING_DIR}/
        tar xf ${WORKING_DIR}/openshift-client-linux.tar.gz
        export UPSTREAM_REPO=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
        export MACHINE_OS=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/release.txt | grep 'machine-os' | awk -F ' ' '{print $2}'| head -1)
        # debugg purposses
        echo ${UPSTREAM_REPO}
        echo ${MACHINE_OS}
        echo "The mirroring process will start:"
        ${WORKING_DIR}/oc adm release mirror -a ${PULLSECRET_FILE} --from=${UPSTREAM_REPO} --to-release-image=${LOCAL_REG}/${LOCAL_REPO}:${VERSION} --to=${LOCAL_REG}/${LOCAL_REPO} --insecure=true
    fi

    status_code=$(curl --write-out %{http_code} --silent --output /dev/null https://rhcos.mirror.openshift.com/art/storage/prod/streams/${OCP_VERSION:0:-2}/builds/${MACHINE_OS}/x86_64/rhcos-${MACHINE_OS}-live.x86_64.iso)
    if [[ "$status_code" -ne 200 ]] ; then
        echo "Site status changed to $status_code"
    else
        echo "Downloading the raw RHCOS .iso for ${OCP_VERSION}"
        curl -O -L https://rhcos.mirror.openshift.com/art/storage/prod/streams/${OCP_VERSION:0:-2}/builds/${MACHINE_OS}/x86_64/rhcos-${MACHINE_OS}-live.x86_64.iso ${WORKING_DIR}/
    fi
    else
        echo "The installation will assume that the OfflineRegistry indicated in cluster-plan.yaml file has all the container base images
            mirrored and the RHCOSCacheService its populated and reachable."
        export MACHINE_OS=${CONFIG_global_machine_os}
fi

# templating the ImageContentSourcePOlicy file for later usage
cat > ImageContentSourcePolicy << EOF
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ${ICSP_NAME}
spec:
  repositoryDigestMirrors:
  - mirrors:
    - ${LOCAL_REG}/${LOCAL_REPO}
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - ${LOCAL_REG}/${LOCAL_REPO}
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

cat > ImageContentSource-install-config.yaml << EOF
imageContentSources:
- mirrors:
  - ${LOCAL_REG}/${LOCAL_REPO}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${LOCAL_REG}/${LOCAL_REPO}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

# Make sure that we have the abi-workir structure created
export DIR="${WORKING_DIR}/abi-workdir"
if [ -d "${DIR}" ];
then
    echo "${DIR}directory exists."
else
	echo -e "\n+ ${DIR}directory does not exist. It will be created!"
    mkdir -p ${DIR}/openshift
    tree ${DIR}
fi

function validate_sshkey () {
    # check if the sshkey exists on the host otherwise create it
    if [ -f ${HOME}/.ssh/id_rsa.pub ];
    then
        echo "id_rsa exists. It wont be created!"
    else
        echo "id_rsa doesn't exists. It will be created!"
        ssh-keygen -q -t rsa -N '' -f ${HOME}/.ssh/id_rsa <<<y >/dev/null 2>&1
    fi
    # store the public ssh-key to a variable
    export SSH_KEY=$(cat ${HOME}/.ssh/id_rsa.pub)
}

function gather_registry_cert () {
    # get the certificate from your offline registry
    status_code=$(curl --write-out %{http_code} --silent --output /dev/null ${LOCAL_REG})
    if [[ "$status_code" -ne 200 ]] ; then
        echo "Site status changed to $status_code"
    else
        echo -e "\n+ Downloading certs from the Offline Registry"
        echo -n | openssl s_client -connect ${LOCAL_REG} -servername ${CONFIG_global_offline_registry_fqdn} | openssl x509 > $(pwd)/file.crt
        export CRT_LOCAL_REG=$(cat $(pwd)/file.crt)
    fi
}

validate_sshkey
# comment the cert gather registry because of the following scenario:
# if the registry its in a remote location the answer is 000
# [midu@midu ocp4-abi-script]$ status_code=$(curl --write-out %{http_code} --silent --output /dev/null https://inbacrnrdl0100.offline.oxtechnix.lan:5000)
# [midu@midu ocp4-abi-script]$ echo $status_code
# 000
# gather_registry_cert()

function validate_num_of_nodes () {
    NUM_WORKERS=${CONFIG_install_workers}
    NUM_MASTERS=${CONFIG_install_ctlplanes}
    re='^[0-9]+$'
    if ! [[ $NUM_WORKERS =~ $re ]] ; then
        echo -e "\n+ error:NUM_WORKERS: Not a number" >&2; exit 1
    else
        if [[ "${NUM_MASTERS}" == 3 ]] ; then
            echo ${NUM_WORKERS}
        else
            echo -e "\n+ error:NUM_WORKERS: Its not correct! If NUM_MASTERS is 1 the NUM_WORKERS should be set to 0!"
        fi
    fi
    if ! [[ $NUM_MASTERS =~ $re ]] ; then
        echo -e "\n+ error:NUM_MASTERS: Not a number" >&2; exit 1
    else
        if [[ "${NUM_MASTERS}" == 1 ]] | [[ "${NUM_MASTERS}" == 3 ]] ; then
            echo ${NUM_MASTERS}
        else
            echo -e "\n+ error:NUM_MASTERS: Its not correct! Should be a integer value either 1 or 3!"
        fi
    fi
}
# Templating the agent-config.yaml
cat << EOF > ${DIR}/agent-config.yaml
apiVersion: v1alpha1
metadata:
  name: ${CONFIG_agent_name}
rendezvousIP: "${CONFIG_agent_rendezvousIP}"
hosts:
EOF
# Templating the install-config.yaml
cat << EOF > ${DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${CONFIG_install_baseDomain}
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: ${CONFIG_install_machineNetwork_1_cidr}
  clusterNetwork:
  - cidr: ${CONFIG_install_clusterNetwork_1_cidr}
    hostPrefix: ${CONFIG_install_clusterNetwork_1_hostPrefix}
  serviceNetwork:
  - ${CONFIG_install_serviceNetwork_1_cidr}
metadata:
  name: ${CONFIG_install_name}
compute:
- name: worker
  replicas: ${CONFIG_install_workers}
controlPlane:
  name: master
  replicas: ${CONFIG_install_ctlplanes}
imageContentSources:
- mirrors:
  - ${LOCAL_REG}/${LOCAL_REPO}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${LOCAL_REG}/${LOCAL_REPO}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
platform:
  baremetal:
    clusterOSImage: http://${LOCAL_RHCOS_CACHE}/rhcos-${MACHINE_OS}-live.x86_64.iso
    apiVIP: "${CONFIG_install_platform_baremetal_1_apiVIP}"
    ingressVIP: "${CONFIG_install_platform_baremetal_1_ingressVIP}"
pullSecret: '{"auths":{"${LOCAL_REG}":{"auth":"${LOCAL_REG_AUTH}"}}}'
additionalTrustBundle: '${CRT_LOCAL_REG}'
sshKey: '${SSH_KEY}'
EOF



NUM_WORKERS=0
for i in $(seq 1 $NUM_WORKERS)
do
  var="CONFIG_agent_worker_$i"
  var_1="${var}_hostname"
  var_2="${var}_deviceName"
  var_3="${var}_interfacename"
  echo ${!var_3}
  cat << EOF >> test.yaml
  - hostname: ${!var_1}
    role: master
    rootDeviceHints:
    deviceName: ${!var_2}
EOF
done

function patch_master_agent_config () {
    NUM_WORKERS=${CONFIG_install_workers}
    NUM_MASTERS=${CONFIG_install_ctlplanes}
    echo -e "\n+ Patching agent-config.yaml file adding the ${NUM_MASTERS} - master nodes"
    for i in $(seq 1 $NUM_MASTERS)
    do
      var="CONFIG_agent_master_$i"
      hostname="${var}_hostname"
      deviceName="${var}_deviceName"
      interfacename="${var}_interfacename"
      interfacemacaddr="${var}_interfacemacaddress"
      interfacetype="${var}_interfacetype"
      interfaceipv4="${var}_interfaceipv4"
      interfaceipv4prefix="${var}_interfaceprefix"
      dnsserver="${var}_dnsserver"
      routesdestination="${var}_routesdestination"
      routesnextaddr="${var}_routesnextaddr"
      cat << EOF >> ${DIR}/agent-config.yaml
  - hostname: ${!hostname}
    role: master
    rootDeviceHints:
      deviceName: ${!deviceName}
    interfaces:
      - name: ${!interfacename}
      macAddress: ${!interfacemacaddr}
    networkConfig:
      interfaces:
        - name: ${!interfacename}
          type: ${!interfacetype}
          state: up
          mac-address: ${!interfacemacaddr}
          ipv4:
            enabled: true
            address:
              - ip: ${!interfaceipv4}
                prefix-length: ${!interfaceipv4prefix}
            dhcp: false
      dns-resolver:
        config:
          server:
            - ${!dnsserver}
      routes:
        config:
          - destination: ${!routesdestination}
            next-hop-address: ${!routesnextaddr}
            next-hop-interface: ${!interfacename}
            table-id: ${!routesnextaddr}
EOF
done
}

function patch_worker_agent_config () {
    NUM_WORKERS=${CONFIG_install_workers}
    NUM_MASTERS=${CONFIG_install_ctlplanes}
    echo -e "\n+ Patching agent-config.yaml file adding the ${NUM_WORKERS} - worker nodes"
    for i in $(seq 1 $NUM_WORKERS)
    do
      var="CONFIG_agent_worker_$i"
      hostname="${var}_hostname"
      deviceName="${var}_deviceName"
      interfacename="${var}_interfacename"
      interfacemacaddr="${var}_interfacemacaddress"
      interfacetype="${var}_interfacetype"
      interfaceipv4="${var}_interfaceipv4"
      interfaceipv4prefix="${var}_interfaceprefix"
      dnsserver="${var}_dnsserver"
      routesdestination="${var}_routesdestination"
      routesnextaddr="${var}_routesnextaddr"
      cat << EOF >> ${DIR}/agent-config.yaml
  - hostname: ${!hostname}
    role: worker
    rootDeviceHints:
      deviceName: ${!deviceName}
    interfaces:
      - name: ${!interfacename}
      macAddress: ${!interfacemacaddr}
    networkConfig:
      interfaces:
        - name: ${!interfacename}
          type: ${!interfacetype}
          state: up
          mac-address: ${!interfacemacaddr}
          ipv4:
            enabled: true
            address:
              - ip: ${!interfaceipv4}
                prefix-length: ${!interfaceipv4prefix}
            dhcp: false
      dns-resolver:
        config:
          server:
            - ${!dnsserver}
      routes:
        config:
          - destination: ${!routesdestination}
            next-hop-address: ${!routesnextaddr}
            next-hop-interface: ${!interfacename}
            table-id: ${!routesnextaddr}
EOF
done
}

function generating_agent_based_installer () {
  # oc adm release extract -a /apps/registry/pull-secret.json --command=openshift-install INBACRNRDL0100.offline.oxtechnix.lan:5000/ocp-release:4.12.0-x86_64
  FILE=${WORKING_DIR}/openshift-install
  if [ -f "$FILE" ]; then
    echo -e "\n+ $FILE exists."
  else
    echo -e "\n+ $FILE doesnt exists. Generating.."
    ${WORKING_DIR}/oc adm release extract --registry-config=${PULLSECRET_FILE}  --icsp-file=${WORKING_DIR}/ImageContentSource-install-config.yaml --command=openshift-install --to=${WORKING_DIR}/. ${LOCAL_REG}/${LOCAL_REPO}:${VERSION}
  fi
}

function generating_discovery_iso () {
  # ./openshift-install agent create image --dir . --log-level debug
  echo -e "\n+ Generating the Discovery.iso in the ${DIR}"
  ${WORKING_DIR}/openshift-install agent create image --dir ${DIR}/. --log-level debug
}
# this is the _main_ section:

# templating the configuration files 
patch_master_agent_config
patch_worker_agent_config

# generating the openshift-install cli
generating_agent_based_installer
# generating the discovery.iso
generating_discovery_iso