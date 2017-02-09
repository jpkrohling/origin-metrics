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
function deploy_heapster() {
  secret_dir="/extra-secrets"
  mkdir -p $secret_dir && chmod 700 $secret_dir || :

  # Get the Heapster allowed users
  if [ -n "${HEAPSTER_ALLOWED_USERS:-}" ]; then
    echo "${HEAPSTER_ALLOWED_USERS:-}" | base64 -d > $dir/heapster_allowed_users
  elif [ -s ${secret_dir}/heapster-allowed-users ]; then
    cp ${secret_dir}/heapster-allowed-users $dir/heapster_allowed_users
  else #by default accept access from the api proxy
    echo "system:master-proxy" > $dir/heapster_allowed_users
  fi

  echo
  echo "Creating the Heapster Extra Secrets configuration json file"
  cat > $dir/heapster-extra-secrets.json <<EOF
      {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata":
        { "name": "heapster-extra-secrets",
          "labels": {
            "metrics-infra": "heapster"
          }
        },
        "data":
        {
          "heapster.allowed-users":"$(base64 -w 0 $dir/heapster_allowed_users)"
        }
      }
EOF
  
  echo "Installing the Heapster Component."

  echo "Creating the extra Heapster secret"
  oc create -f $dir/heapster-extra-secrets.json
  
  echo "Creating the Heapster template"
  if [ -n "${HEAPSTER_STANDALONE:-}" ]; then
    oc create -f templates/heapster-standalone.yaml
  else
    oc create -f templates/heapster.yaml
  fi
  
  echo "Deploying the Heapster component"
  if [ -n "${HEAPSTER_STANDALONE:-}" ]; then
    oc process heapster-standalone -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v MASTER_URL=$master_url -v METRIC_RESOLUTION=$metric_resolution -v STARTUP_TIMEOUT=$startup_timeout | oc create -f -
  else
    oc process hawkular-heapster -v IMAGE_PREFIX=$image_prefix -v IMAGE_VERSION=$image_version -v MASTER_URL=$master_url -v NODE_ID=$heapster_node_id -v METRIC_RESOLUTION=$metric_resolution -v STARTUP_TIMEOUT=$startup_timeout | oc create -f -
  fi
}
