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

echo $(date "+%Y-%m-%d %H:%M:%S") Starting Hawkular Metrics

KUBERNETES_API_VERSION=${KUBERNETES_API_VERSION:-v1}
POD_NAMESPACE=${POD_NAMESPACE:-openshift-infra}
MASTER_URL=${MASTER_URL:-https://kubernetes.default.svc:443}

JBOSS_HOME=${JBOSS_HOME:-/opt/jboss/wildfly}

# Check Read Permission
token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
url="${MASTER_URL}/api/${KUBERNETES_API_VERSION}/namespaces/${POD_NAMESPACE}/replicationcontrollers/hawkular-metrics"
cacrt="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

status_code=$(curl --cacert ${cacrt} --max-time 10 --connect-timeout 10 -L -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${token}" $url)
if [ "$status_code" != 200 ]; then
  echo "Error: the service account for Hawkular Metrics does not have permission to view resources in this namespace. View permissions are required for Hawkular Metrics to function properly."
  echo "Usually this can be resolved by running: oc adm policy add-role-to-user view system:serviceaccount:${POD_NAMESPACE}:hawkular -n ${POD_NAMESPACE}"
  exit 1
else
  echo "The service account has read permissions for its project. Proceeding"
fi

# Setup additional logging if the ADDITIONAL_LOGGING variable is set
if [ -z "$ADDITIONAL_LOGGING" ]; then
  additional_loggers="            <!-- no additional logging configured -->"
else
  entries=$(echo ${ADDITIONAL_LOGGING} | tr "," "\n")
  for entry in ${entries}; do
    component=${entry%=*}
    debug_level=${entry##*=}

    debug_config="\
            <logger category=\"${component}\"> \n\
              <level name=\"${debug_level}\"/> \n\
            </logger> \n"

    additional_loggers+=${debug_config}
  done
fi
sed -i "s|<!-- ##ADDITIONAL LOGGERS## -->|$additional_loggers|g" ${JBOSS_HOME}/standalone/configuration/standalone.xml

exec 2>&1 /opt/jboss/wildfly/bin/standalone.sh \
  -Djboss.node.name=$HOSTNAME \
  -b `hostname -i` \
  -bprivate `hostname -i` \
  $@
