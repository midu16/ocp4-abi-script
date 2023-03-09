# ocp4-abi-script

This repo is designed to deploy a Red Hat OpenShift cluster with ABI method on a BareMetal server.

# Prerequisite

 - Offline Registry has been configured and its reachable from the localhost

 - RHCOS_Cache has been configured and its reachable from the localhost

 - In a total disconnected environment the `oc-cli` and `oc-mirror-cli` are made available in the `${HOME}/ocp4-abi-script/bin/` of this project before usage, if the existing ones version are out of scope. Be aware, that the verison used in this is `4.12.2` and you should update the binaries to the OCP version you are going to deploy.

 - RHEL base Operating System

 # Quick Start

 ```bash
[midu@GFA2MKUN ]$ git clone https://github.com/midu16/ocp4-abi-script.git
[midu@GFA2MKUN ]$ cd ocp4-abi-script
[midu@GFA2MKUN ocp4-abi-script]$ ls -l
total 24
-rwxrwxr-x 1 midu midu 14523 Mar  8 12:06 abi.sh
-rw-rw-r-- 1 midu midu  2791 Mar  8 12:06 cluster-plan.yaml
-rw-rw-r-- 1 midu midu   185 Mar  8 12:06 README.md
```
The `abi.sh-cli` help:
```bash
[midu@GFA2MKUN ocp4-abi-script]$ ./abi.sh
Some or all of the parameters are empty

Usage: ./abi.sh -a /apps/registry/pull-secret.json -b parameterB -c parameterC
        -a This parameter is requiring the path to the pull-secret.json. Example: /apps/registry/pull-secret.json. Please note, that the pull-secret.json should inlcude the public and also private registry information.
        -b This parameter is requiring the OpenShift Container Platform version to be installed. Example: 4.12.2
        -c This parameter is requiring the cluster-plan.yaml. Example: /apps/registry/cluster-plan.yaml
        -d The use of this parameter its enabling fully disconnected mode. The Offline Registry and RHCOS Cache are assumed completed. Example: True. Default value is set to False
```

# Quick Usage
- The usage in a total disconnected environment:
```bash
[midu@GFA2MKUN ocp4-abi-script]$ ./abi.sh -a ./path/to/pull-secret.json -b 4.12.2 -c cluster-plan.yaml -d True
```
In the above use-case, when the deployment environment its total disconnected, the assumption is that the `oc-cli`, `oc-mirror-cli`, `Offline Registry` and `RHCOS Cache server` are made available before. In the case of the `oc-cli` and `oc-mirror-cli` are made available in the `${HOME}/ocp4-abi-script/`. 

- The usage in a connected environment:
```bash
[midu@GFA2MKUN ocp4-abi-script]$ ./abi.sh -a ./path/to/pull-secret.json -b 4.12.2 -c cluster-plan.yaml -d False
```
In the above use-case, when the deployment environment its on a connected host, the script will validate the connection to the public RH registry to download the `oc-cli`, `oc-mirror-cli`, `mirror the OpenShift Container Platform release cluster operator container base images` and the `RHCOS base image`.

In the working directory its required before starting the process to have the `pull-secret.json` download and add the offline registry information appended to the file in the [pull-secret.json].

[pull-secret.json]: https://docs.openshift.com/container-platform/4.12/openshift_images/managing_images/using-image-pull-secrets.html
