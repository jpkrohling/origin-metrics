#!/bin/bash
#
# Copyright 2014-2015 Red Hat, Inc. and/or its affiliates
# and other contributors as indicated by the @author tags.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

for args in "$@"
do
  case $args in
    --seeds=*)
      SEEDS="${args#*=}"
    ;;
    --cluster_name=*)
      CLUSTER_NAME="${args#*=}"
    ;;
    --data_volume=*)
      DATA_VOLUME="${args#*=}"
    ;;
    --commitlog_volume=*)
      COMMITLOG_VOLUME="${args#*=}"
    ;;
    --seed_provider_classname=*)
      SEED_PROVIDER_CLASSNAME="${args#*=}"
    ;;
    --internode_encryption=*)
      INTERNODE_ENCRYPTION="${args#*=}"
    ;;
    --require_node_auth=*)
      REQUIRE_NODE_AUTH="${args#*=}"
    ;;
    --enable_client_encryption=*)
      ENABLE_CLIENT_ENCRYPTION="${args#*=}"
    ;;
    --require_client_auth=*)
      REQUIRE_CLIENT_AUTH="${args#*=}"
    ;;
    --help)
      HELP=true
    ;;
  esac
done

if [ -n "$HELP" ]; then
  echo
  echo Starts up a Cassandra Docker image
  echo
  echo Usage: [OPTIONS]...
  echo
  echo Options:
  echo "  --seeds=SEEDS"
  echo "        comma separated list of hosts to use as a seed list"
  echo "        default: \$HOSTNAME"
  echo
  echo "  --cluster_name=NAME"
  echo "        the name to use for the cluster"
  echo "        default: test_cluster"
  echo
  echo "  --data_volume=VOLUME_PATH"
  echo "        the path to where the data volume should be located"
  echo "        default: \$CASSANDRA_HOME/data"
  echo
  echo "  --seed_provider_classname"
  echo "        the classname to use as the seed provider"
  echo "        default: org.apache.cassandra.locator.SimpleSeedProvider"
  echo
  echo "  --internode_encryption=[all|none|dc|rack]"
  echo "        what type of internode encryption should be used"
  echo "        default: none"
  echo
  echo "  --enable_client_encryption=[true|false]"
  echo "        if client encryption should be enabled"
  echo "        default: false"
  echo
  echo "  --require_node_auth=[true|false]"
  echo "        if certificate based authentication should be required between nodes"
  echo "        default: false"
  echo
  echo "  --require_client_auth=[true|false]"
  echo "        if certificate based authentication should be required for client"
  echo "        default: false"
  echo
  exit 0
fi

CASSANDRA_HOME=${CASSANDRA_HOME:-"/opt/apache-cassandra"}
CASSANDRA_CONF=${CASSANDRA_CONF:-"${CASSANDRA_HOME}/conf"}
CASSANDRA_AUTH=${CASSANDRA_AUTH:-"${CASSANDRA_HOME}/auth"}
CASSANDRA_CONF_FILE=${CASSANDRA_CONF_FILE:-"${CASSANDRA_CONF}/cassandra.yaml"}
KEYSTORE_DIR=${KEYSTORE_DIR:-"${CASSANDRA_AUTH}"}
KEYSTORE_FILE=${KEYSTORE_FILE:-"${KEYSTORE_DIR}/cassandra.keystore"}
TRUSTSTORE_FILE=${TRUSTSTORE_FILE:-"${KEYSTORE_DIR}/cassandra.truststore"}
KEYSTORE_PASSWORD=`cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c15`
PKCS12_FILE=${PKCS12_FILE:-"${KEYSTORE_DIR}/cassandra.pkcs12"}
SERVICE_CERT=${SERVICE_CERT:-"/secrets/tls.crt"}
SERVICE_CERT_KEY=${SERVICE_CERT_KEY:-"/secrets/tls.key"}
KEYTOOL_COMMAND="/usr/lib/jvm/java-1.8.0/jre/bin/keytool"

if [ ! -d ${CASSANDRA_AUTH} ]; then
  mkdir -p ${CASSANDRA_AUTH}
fi

if [ -z "${MAX_HEAP_SIZE}" ]; then
  if [ -z "${MEMORY_LIMIT}" ]; then
    MEMORY_LIMIT=`cat /sys/fs/cgroup/memory/memory.limit_in_bytes`
    echo "The MEMORY_LIMIT envar was not set. Reading value from /sys/fs/cgroup/memory/memory.limit_in_bytes."
  fi
  echo "The MAX_HEAP_SIZE envar is not set. Basing the MAX_HEAP_SIZE on the available memory limit for the pod (${MEMORY_LIMIT})."
  BYTES_MEGABYTE=1048576
  BYTES_GIGABYTE=1073741824
  # Based on the Cassandra memory limit recommendations. See http://docs.datastax.com/en/cassandra/2.2/cassandra/operations/opsTuneJVM.html
  if (( ${MEMORY_LIMIT} <= (2 * ${BYTES_GIGABYTE}) )); then
    # If less than 2GB, set the heap to be 1/2 of available ram
    echo "The memory limit is less than 2GB. Using 1/2 of available memory for the max_heap_size."
    export MAX_HEAP_SIZE="$((${MEMORY_LIMIT} / ${BYTES_MEGABYTE} / 2 ))M"
  elif (( ${MEMORY_LIMIT} <= (4 * ${BYTES_GIGABYTE}) )); then
    echo "The memory limit is between 2 and 4GB. Setting max_heap_size to 1GB."
    # If between 2 and 4GB, set the heap to 1GB
    export MAX_HEAP_SIZE="1024M"
  elif (( ${MEMORY_LIMIT} <= (32 * ${BYTES_GIGABYTE}) )); then
    echo "The memory limit is between 4 and 32GB. Using 1/4 of the available memory for the max_heap_size."
    # If between 4 and 32GB, use 1/4 of the available ram
    export MAX_HEAP_SIZE="$(( ${MEMORY_LIMIT} / ${BYTES_MEGABYTE} / 4 ))M"
  else
    echo "The memory limit is above 32GB. Using 8GB for the max_heap_size"
    # If above 32GB, set the heap size to 8GB
    export MAX_HEAP_SIZE="8192M"
  fi
  echo "The MAX_HEAP_SIZE has been set to ${MAX_HEAP_SIZE}"
else
  echo "The MAX_HEAP_SIZE envar is set to ${MAX_HEAP_SIZE}. Using this value"
fi

if [ -z "${HEAP_NEWSIZE}" ] && [ -z "${CPU_LIMIT}" ]; then
  echo "The HEAP_NEWSIZE and CPU_LIMIT envars are not set. Defaulting the HEAP_NEWSIZE to 100M"
  export HEAP_NEWSIZE=100M
elif [ -z "${HEAP_NEWSIZE}" ]; then
  export HEAP_NEWSIZE=$((CPU_LIMIT/10))M
  echo "THE HEAP_NEWSIZE envar is not set. Setting to ${HEAP_NEWSIZE} based on the CPU_LIMIT of ${CPU_LIMIT}. [100M per CPU core]"
else
  echo "The HEAP_NEWSIZE envar is set to ${HEAP_NEWSIZE}. Using this value"
fi

#Update the cassandra-env.sh with these new values
cp ${CASSANDRA_CONF}/cassandra-env.sh.template ${CASSANDRA_CONF}/cassandra-env.sh
sed -i 's/${MAX_HEAP_SIZE}/'$MAX_HEAP_SIZE'/g' ${CASSANDRA_CONF}/cassandra-env.sh
sed -i 's/${HEAP_NEWSIZE}/'$HEAP_NEWSIZE'/g' ${CASSANDRA_CONF}/cassandra-env.sh

cp ${CASSANDRA_CONF_FILE}.template ${CASSANDRA_CONF_FILE}

# set the hostname in the cassandra configuration file
sed -i 's/${HOSTNAME}/'$HOSTNAME'/g' ${CASSANDRA_CONF_FILE}

# if the seed list is not set, try and get it from the gather-seeds script
if [ -z "$SEEDS" ]; then
  source ${CASSANDRA_HOME}/bin/gather-seeds.sh
fi

echo "Setting seeds to be ${SEEDS}"
sed -i 's/${SEEDS}/'$SEEDS'/g' ${CASSANDRA_CONF_FILE}

# set the cluster name if set, default to "test_cluster" if not set
if [ -n "$CLUSTER_NAME" ]; then
    sed -i 's/${CLUSTER_NAME}/'$CLUSTER_NAME'/g' ${CASSANDRA_CONF_FILE}
else
    sed -i 's/${CLUSTER_NAME}/test_cluster/g' ${CASSANDRA_CONF_FILE}
fi

# set the data volume if set, otherwise use the CASSANDRA_HOME location, otherwise default to '/cassandra_data'
if [ -n "$DATA_VOLUME" ]; then
    sed -i 's#${DATA_VOLUME}#'$DATA_VOLUME'#g' ${CASSANDRA_CONF_FILE}
elif [ -n "$CASSANDRA_HOME" ]; then
    DATA_VOLUME="$CASSANDRA_HOME/data"
    sed -i 's#${DATA_VOLUME}#'$CASSANDRA_HOME'/data#g' ${CASSANDRA_CONF_FILE}
else
    DATA_VOLUME="/cassandra_data"
    sed -i 's#${DATA_VOLUME}#/cassandra_data#g' ${CASSANDRA_CONF_FILE}
fi

# set the commitlog volume if set, otherwise use the DATA_VOLUME value instead
if [ -n "$COMMITLOG_VOLUME" ]; then
  sed -i 's#${COMMITLOG_VOLUME}#'$COMMITLOG_VOLUME'#g' ${CASSANDRA_CONF_FILE}
else
  sed -i 's#${COMMITLOG_VOLUME}#'$DATA_VOLUME'#g' ${CASSANDRA_CONF_FILE}
fi

# set the seed provider class name, otherwise default to the SimpleSeedProvider
if [ -n "$SEED_PROVIDER_CLASSNAME" ]; then
    sed -i 's#${SEED_PROVIDER_CLASSNAME}#'$SEED_PROVIDER_CLASSNAME'#g' ${CASSANDRA_CONF_FILE}
else
    sed -i 's#${SEED_PROVIDER_CLASSNAME}#org.apache.cassandra.locator.SimpleSeedProvider#g' ${CASSANDRA_CONF_FILE}
fi

# setup and configure the security setting
if [ -n "$INTERNODE_ENCRYPTION" ]; then
   sed -i 's#${INTERNODE_ENCRYPTION}#'$INTERNODE_ENCRYPTION'#g' ${CASSANDRA_CONF_FILE}
else
   sed -i 's#${INTERNODE_ENCRYPTION}#none#g' ${CASSANDRA_CONF_FILE}
fi

if [ -n "$ENABLE_CLIENT_ENCRYPTION" ]; then
   sed -i 's#${ENABLE_CLIENT_ENCRYPTION}#'$ENABLE_CLIENT_ENCRYPTION'#g' ${CASSANDRA_CONF_FILE}
else
   sed -i 's#${ENABLE_CLIENT_ENCRYPTION}#false#g' ${CASSANDRA_CONF_FILE}
fi

if [ -n "$REQUIRE_NODE_AUTH" ]; then
   sed -i 's#${REQUIRE_NODE_AUTH}#'$REQUIRE_NODE_AUTH'#g' ${CASSANDRA_CONF_FILE}
else
   sed -i 's#${REQUIRE_NODE_AUTH}#false#g' ${CASSANDRA_CONF_FILE}
fi

if [ -n "$REQUIRE_CLIENT_AUTH" ]; then
   sed -i 's#${REQUIRE_CLIENT_AUTH}#'$REQUIRE_CLIENT_AUTH'#g' ${CASSANDRA_CONF_FILE}
else
   sed -i 's#${REQUIRE_CLIENT_AUTH}#false#g' ${CASSANDRA_CONF_FILE}
fi

echo "Creating the Cassandra keystore from the Secret's cert data"
openssl pkcs12 -export -in ${SERVICE_CERT} -inkey ${SERVICE_CERT_KEY} -out ${PKCS12_FILE} -name cassandra -noiter -nomaciter -password pass:${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a PKCS12 certificate file with the service-specific certificate. Aborting."
    exit 1
fi

echo "Converting the PKCS12 keystore into a Java Keystore"
${KEYTOOL_COMMAND} -v -importkeystore -srckeystore ${PKCS12_FILE} -srcstoretype PKCS12 -destkeystore ${KEYSTORE_FILE} -deststoretype JKS -deststorepass ${KEYSTORE_PASSWORD} -srcstorepass ${KEYSTORE_PASSWORD}
if [ $? != 0 ]; then
    echo "Failed to create a Java Keystore file with the service-specific certificate. Aborting."
    exit 1
fi

${KEYTOOL_COMMAND} -noprompt -import -alias services-ca -file /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt -keystore ${KEYSTORE_FILE} -trustcacerts -storepass ${KEYSTORE_PASSWORD}

echo "-----------------------------------------"
echo "Certs in keystore"
${KEYTOOL_COMMAND} -list -keystore ${KEYSTORE_FILE} -storepass ${KEYSTORE_PASSWORD}
echo "-----------------------------------------"

echo "-----------------------------------------"
echo "Services CA"
cat /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
echo "-----------------------------------------"

sed -i 's#${KEYSTORE_FILE}#'${KEYSTORE_FILE}'#g' ${CASSANDRA_CONF_FILE}
sed -i 's#${KEYSTORE_PASSWORD}#'${KEYSTORE_PASSWORD}'#g' ${CASSANDRA_CONF_FILE}
sed -i 's#${TRUSTSTORE_FILE}#'${KEYSTORE_FILE}'#g' ${CASSANDRA_CONF_FILE}
sed -i 's#${TRUSTSTORE_PASSWORD}#'${KEYSTORE_PASSWORD}'#g' ${CASSANDRA_CONF_FILE}

# create the cqlshrc file so that cqlsh can be used much more easily from the system
mkdir -p $HOME/.cassandra
cat >> $HOME/.cassandra/cqlshrc << DONE
[connection]
hostname= $HOSTNAME
factory = cqlshlib.ssl.ssl_transport_factory
port = 9042

[ssl]
certfile = ${SERVICE_CERT}
usercert = ${SERVICE_CERT}
userkey = ${SERVICE_CERT_KEY}
DONE

# verify that we are not trying to run an older version of Cassandra which has been configured for a newer version.
if [ -f ${CASSANDRA_DATA_VOLUME}/.cassandra.version ]; then
    previousVersion=$(cat ${CASSANDRA_DATA_VOLUME}/.cassandra.version)
    echo "The previous version of Cassandra was $previousVersion. The current version is $CASSANDRA_VERSION"
    previousMajor=$(cut -d "." -f 1 <<< "$previousVersion")
    previousMinor=$(cut -d "." -f 2 <<< "$previousVersion")

    currentMajor=$(cut -d "." -f 1 <<< "$CASSANDRA_VERSION")
    currentMinor=$(cut -d "." -f 2 <<< "$CASSANDRA_VERSION")

    if (( ($currentMajor < $previousMajor) || (($currentMajor == $previousMajor) && ($currentMinor < $previousMinor)) )); then
       echo "Error: the data volume associated with this pod is configured to be used with Cassandra version $previousVersion"
       echo "       or higher. This pod is using Cassandra version $CASSANDRA_VERSION which does not meet this requirement."
       echo "       This pod will not be started."
       exit 1
    fi
fi

echo "------------ Version 1"
echo "----------------------------------------------------"
echo "cassandra.yaml"
cat ${CASSANDRA_CONF_FILE}
echo "----------------------------------------------------"
# remove -R once CASSANDRA-12641 is fixed
exec ${CASSANDRA_HOME}/bin/cassandra -f -R
