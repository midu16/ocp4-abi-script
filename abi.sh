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
   echo -e "\t-c This parameter is requiring the cluster-plan.yaml Example: /apps/registry/cluster-plan.yaml"
   exit 1 # Exit script after printing help
}

while getopts "a:b:c:" opt
do
   case "$opt" in
      a ) parameterA="$OPTARG" ;;
      b ) parameterB="$OPTARG" ;;
      c ) parameterC="$OPTARG" ;;
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
echo "$parameterA"
echo "$parameterB"
echo "$parameterC"

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
export LOCAL_REG_AUTH="$(cat ${PULLSECRET_FILE} | jq .auths.\"${LOCAL_REG}\".auth -r)"
export LOCAL_RHCOS_CACHE="${CONFIG_global_rhcos_cache_fqdn}:${$CONFIG_global_port_rhcos_cache_fqdn}"
export OCP_VERSION=$parameterB
export VERSION=${OCP_VERSION}-x86_64
export ICSP_NAME="ocp-${VERSION}"
export WORKING_DIR=$(pwd)

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
	echo "${DIR}directory does not exist. It will be created!"
    mkdir -p ${DIR}/openshift
    tree ${DIR}
fi

function validate_sshkey () {
    # check if the sshkey exists on the host otherwise create it
    if [ -f ${HOME}/.ssh/id_rsa.pub ];
    then
        echo "id_rsa exists."
    else
        echo "id_rsa doesn't exists. It will be created!"
        ssh-keygen -q -t rsa -N '' -f ${HOME}/.ssh/id_rsa <<<y >/dev/null 2>&1
    fi
    # store the public ssh-key to a variable
    export SSH_KEY=$(cat ${HOME}/.ssh/id_rsa.pub)
}

function gather_registry_cert () {
    # get the certificate from your offline registry
    status_code=$(curl --write-out %{http_code} --silent --output /dev/null https://${LOCAL_REG})
    if [[ "$status_code" -ne 200 ]] ; then
        echo "Site status changed to $status_code"
    else
        echo "Downloading certs from the Offline Registry"
        ex +'/BEGIN CERTIFICATE/,/END CERTIFICATE/p' <(echo | openssl s_client -showcerts -connect ${LOCAL_REG}) -scq > $(pwd)/file.crt
        export CRT_LOCAL_REG=$(cat $(pwd)/file.crt)
    fi
}

function validate_num_of_nodes () {
    NUM_WORKERS="2"
    NUM_MASTERS="3"
    re='^[0-9]+$'
    if ! [[ $NUM_WORKERS =~ $re ]] ; then
        echo "error:NUM_WORKERS: Not a number" >&2; exit 1
    else
        if [[ "${NUM_MASTERS}" == 3 ]] ; then
            echo ${NUM_WORKERS}
        else
            echo "error:NUM_WORKERS: Its not correct! If NUM_MASTERS is 1 the NUM_WORKERS should be set to 0!"
        fi
    fi
    if ! [[ $NUM_MASTERS =~ $re ]] ; then
        echo "error:NUM_MASTERS: Not a number" >&2; exit 1
    else
        if [[ "${NUM_MASTERS}" == 1 ]] | [[ "${NUM_MASTERS}" == 3 ]] ; then
            echo ${NUM_MASTERS}
        else
            echo "error:NUM_MASTERS: Its not correct! Should be a integer value either 1 or 3!"
        fi
    fi
}
# Templating the agent-config.yaml
cat << EOF > ${DIR}/agent-config.yaml
apiVersion: v1alpha1
metadata:
  name: ${CLUSTER_NAME}
rendezvousIP: "${rendezvous_VIP}"
hosts:
EOF
# Templating the install-config.yaml
cat << EOF > ${DIR}/install-config.yaml
apiVersion: v1
baseDomain: ${DOMAIN}
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: ${IPIBM_CIDR}
  clusterNetwork:
  - cidr: ${IPIBM_CNET_CIDR}
    hostPrefix: ${DEF_CNET_HOST_PREFIX}
  serviceNetwork:
  - ${IPIBM_SNET_CIDR}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: ${NUM_WORKERS}
controlPlane:
  name: master
  replicas: ${NUM_MASTERS}
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
    apiVIP: "${OCP_API_VIP}"
    ingressVIP: "${INGRESS_VIP}"
pullSecret: '{"auths":{"${LOCAL_REG}":{"auth":"${LOCAL_REG_AUTH}"}}}'
additionalTrustBundle: '${CRT_LOCAL_REG}'
sshKey: '${SSH_KEY}'
EOF






function patch_agent_config () {
    echo -e "\n+ Patching agent-config.yaml file adding the hosts"
    NUM_WORKERS="2"
    for i in $(seq $NUM_WORKERS -1 0)
    do
    echo "master-`expr $NUM_WORKERS - $i`"
    cat << EOF >> agent-config.yaml
    - name: ${WORKER_VM}
      role: worker
      bmc:
        address: ipmi://IPMI_URL:6230
        username: foo
        password: bar
        disableCertificateVerification: True
      bootMACAddress: aa:aa:aa:aa:bd:0${w}
    - hostname: "master-`expr $NUM_WORKERS - $i`"
        role: master
        rootDeviceHints:
        deviceName: "/dev/sdb"
        interfaces:
        - name: eno1
        macAddress: b8:ce:f6:56:48:aa
        networkConfig:
        interfaces:
            - name: eno1
            type: ethernet
            state: up
            mac-address: b8:ce:f6:56:48:aa
            ipv4:
                enabled: true
                address:
                - ip: 192.168.24.91
                    prefix-length: 25
                dhcp: false
        dns-resolver:
            config:
            server:
                - 192.168.24.80
        routes:
            config:
            - destination: 0.0.0.0/0
                next-hop-address: 192.168.24.1
                next-hop-interface: eno1
                table-id: 254
EOF
    done
}


# 