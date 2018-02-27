#!/bin/bash
#
# Copyright (c) 2012-2017 Red Hat, Inc.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
# Contributors:
#   Red Hat, Inc.- initial API and implementation
#

init_global_variables () {
  # For coloring console output
  BLUE='\033[1;34m'
  GREEN='\033[0;32m'
  NC='\033[0m'

  USAGE="
Usage:
  che [COMMAND]
     start                              Starts server with output in the background
     stop                               Stops ${CHE_MINI_PRODUCT_NAME} server
     run                                Starts server with output in the foreground

Variables:
    CHE_SERVER_ACTION                   Another way to set the [COMMAND] to [run | start | stop]
    CHE_PORT                            The port the Che server will listen on
    CHE_IP                              The IP address of the host - must be set if remote clients connecting
    CHE_BLOCKING_ENTROPY                Starts Tomcat with blocking entropy: -Djava.security.egd=file:/dev/./urandom
    CHE_LAUNCH_DOCKER_REGISTRY          If true, uses Docker registry to save ws snapshots instead of disk
    CHE_REGISTRY_HOST                   Hostname of Docker registry to launch, otherwise 'localhost'
    CHE_LOG_LEVEL                       [INFO | DEBUG] Sets the output level of Tomcat messages
    CHE_DEBUG_SERVER                    If true, activates Tomcat's JPDA debugging mode
    CHE_HOME                            Where the Che assembly resides - self-determining if not set
"

  # Use blocking entropy -- needed for some servers
  DEFAULT_CHE_BLOCKING_ENTROPY=false
  CHE_BLOCKING_ENTROPY=${CHE_BLOCKING_ENTROPY:-${DEFAULT_CHE_BLOCKING_ENTROPY}}

  DEFAULT_CHE_SERVER_ACTION=run
  CHE_SERVER_ACTION=${CHE_SERVER_ACTION:-${DEFAULT_CHE_SERVER_ACTION}}

  DEFAULT_CHE_LAUNCH_DOCKER_REGISTRY=false
  CHE_LAUNCH_DOCKER_REGISTRY=${CHE_LAUNCH_DOCKER_REGISTRY:-${DEFAULT_CHE_LAUNCH_DOCKER_REGISTRY}}

  # Must be exported as this will be needed by Tomcat's JVM
  DEFAULT_CHE_REGISTRY_HOST=localhost
  export CHE_REGISTRY_HOST=${CHE_REGISTRY_HOST:-${DEFAULT_CHE_REGISTRY_HOST}}

  DEFAULT_CHE_PORT=8080
  export CHE_PORT=${CHE_PORT:-${DEFAULT_CHE_PORT}}

  DEFAULT_CHE_IP=
  CHE_IP=${CHE_IP:-${DEFAULT_CHE_IP}}

  DEFAULT_CHE_LOG_LEVEL=INFO
  CHE_LOG_LEVEL=${CHE_LOG_LEVEL:-${DEFAULT_CHE_LOG_LEVEL}}

  DEFAULT_CHE_LOGS_DIR="${CATALINA_HOME}/logs/"
  export CHE_LOGS_DIR=${CHE_LOGS_DIR:-${DEFAULT_CHE_LOGS_DIR}}

  DEFAULT_CHE_DEBUG_SERVER=false
  CHE_DEBUG_SERVER=${CHE_DEBUG_SERVER:-${DEFAULT_CHE_DEBUG_SERVER}}

}

error () {
  echo
  echo "!!!"
  echo -e "!!! ${1}"
  echo "!!!"
  return 0
}

usage () {
  echo "${USAGE}"
}

set_environment_variables () {
  ### Set value of derived environment variables.

  # CHE_DOCKER_IP is used internally by Che to set its IP address
  if [[ -z "${CHE_DOCKER_IP}" ]]; then
    if [[ -n "${CHE_IP}" ]]; then
        export CHE_DOCKER_IP="${CHE_IP}"
    fi
  fi

  # Convert Tomcat environment variables to POSIX format.
  if [[ "${JAVA_HOME}" == *":"* ]]; then
    JAVA_HOME=$(echo /"${JAVA_HOME}" | sed  's|\\|/|g' | sed 's|:||g')
  fi

  # Convert Che environment variables to POSIX format.
  if [[ "${CHE_HOME}" == *":"* ]]; then
    CHE_HOME=$(echo /"${CHE_HOME}" | sed  's|\\|/|g' | sed 's|:||g')
  fi

  # Sets the location of the application server and its executables
  # Internal property - should generally not be overridden
  export CATALINA_HOME="${CHE_HOME}/tomcat"

  # Convert windows path name to POSIX
  if [[ "${CATALINA_HOME}" == *":"* ]]; then
    CATALINA_HOME=$(echo /"${CATALINA_HOME}" | sed  's|\\|/|g' | sed 's|:||g')
  fi

  # Internal properties - should generally not be overridden
  export CATALINA_BASE="${CHE_HOME}/tomcat"
  export ASSEMBLY_BIN_DIR="${CATALINA_HOME}/bin"
  export CHE_LOGS_LEVEL="${CHE_LOG_LEVEL}"
}

docker_exec() {
  "$(which docker)" "$@"
}

start_che_server () {
 if ${CHE_LAUNCH_DOCKER_REGISTRY} ; then
    # Export the value of host here
    launch_docker_registry
  fi

  #########################################
  # Launch Che natively as a tomcat server
  call_catalina
}

stop_che_server () {
  CHE_SERVER_ACTION="stop"
  echo -e "Stopping Che server running on localhost:${CHE_PORT}"
  call_catalina >/dev/null 2>&1
}

call_catalina () {
  # Test to see that Che application server is where we expect it to be
  if [ ! -d "${ASSEMBLY_BIN_DIR}" ]; then
    error "Could not find Che's application server."
    return 1;
  fi

  ### Initialize default JVM arguments to run che
  if [[ "${CHE_BLOCKING_ENTROPY}" == true ]]; then
    [ -z "${JAVA_OPTS}" ] && JAVA_OPTS="-Xms256m -Xmx1024m"
  else
    [ -z "${JAVA_OPTS}" ] && JAVA_OPTS="-Xms256m -Xmx1024m -Djava.security.egd=file:/dev/./urandom"
  fi

  ### Cannot add this in setenv.sh.
  ### We do the port mapping here, and this gets inserted into server.xml when tomcat boots
  export JAVA_OPTS="${JAVA_OPTS} -Dport.http=${CHE_PORT} -Dche.home=${CHE_HOME}"
  export SERVER_PORT=${CHE_PORT}

  # Launch the Che application server, passing in command line parameters
  if [[ "${CHE_DEBUG_SERVER}" == true ]]; then
    "${ASSEMBLY_BIN_DIR}"/catalina.sh jpda ${CHE_SERVER_ACTION}
  else
    "${ASSEMBLY_BIN_DIR}"/catalina.sh ${CHE_SERVER_ACTION}
  fi
}

kill_and_launch_docker_registry () {
  echo -e "Launching Docker container named ${GREEN}registry${NC} from image ${GREEN}registry:2${NC}."
  docker_exec rm -f registry &> /dev/null || true
  docker_exec run -d -p 5000:5000 --restart=always --name registry registry:2
}

launch_docker_registry () {
    echo "Launching a Docker registry for workspace snapshots."
    CREATE_NEW_CONTAINER=false

    # Check to see if the registry docker was not properly shut down
    docker_exec inspect registry &> /dev/null || DOCKER_INSPECT_EXIT=$? || true
    if [ "${DOCKER_INSPECT_EXIT}" != "1" ]; then

      # Existing container running registry is found.  Let's start it.
      echo -e "Found a registry container named ${GREEN}registry${NC}. Attempting restart."
      docker_exec start registry &>/dev/null || DOCKER_EXIT=$? || true

      # Existing container found, but could not start it properly.
      if [ "${DOCKER_EXIT}" == "1" ]; then
        echo "Initial start of registry docker container failed... Attempting docker restart and exec."
        CREATE_NEW_CONTAINER=true
      fi

    echo "Successful restart of registry container."
    echo

    # No existing Che container found, we need to create a new one.
    else
      CREATE_NEW_CONTAINER=true
    fi

    if ${CREATE_NEW_CONTAINER} ; then
      # Container in bad state or not found, kill and launch new container.
      kill_and_launch_docker_registry
    fi
}

perform_database_migration() {
  CHE_DATA=/data
  if [ -f ${CHE_DATA}/db/che.mv.db ]; then
    echo "!!! Detected Che database, that is stored by an old path: ${CHE_DATA}/db/che.mv.db"
    echo "!!! In case if you want to use it, move it manually to the new path ${CHE_DATA}/storage/db/che.mv.db"
    echo "!!! It will be moved there automatically, if no database is present by the new path"
    if [ ! -f ${CHE_DATA}/storage/db/che.mv.db ]; then
      mkdir -p ${CHE_DATA}/storage/db
      mv ${CHE_DATA}/db/che.mv.db ${CHE_DATA}/storage/db/che.mv.db
      echo "Database has been successfully moved to the new path"
    fi
  fi
}

init() {
  ### Any variables with export is a value that native Tomcat che.sh startup script requires
  export CHE_IP=${CHE_IP}

  if [ -f "/assembly/tomcat/bin/catalina.sh" ]; then
    echo "Found custom assembly..."
    export CHE_HOME="/assembly"
  else
    echo "Using embedded assembly..."
    export CHE_HOME=$(echo /home/user/eclipse-che/)
  fi

  ### We need to discover the host mount provided by the user for `/data`
  export CHE_DATA="/data"
  CHE_DATA_HOST=$(get_che_data_from_host)

  CHE_USER=${CHE_USER:-root}
  export CHE_USER=$CHE_USER
  if [ "$CHE_USER" != "root" ]; then
    if [ ! $(getent group docker) ]; then
      echo "!!!"
      echo "!!! Error: The docker group doesn't exist."
      echo "!!!"
      exit 1
    fi
    export CHE_USER_ID=${CHE_USER}
    sudo chown -R ${CHE_USER} ${CHE_DATA}
    sudo chown -R ${CHE_USER} ${CHE_HOME}
    sudo chown -R ${CHE_USER} ${CHE_LOGS_DIR}
  fi

  [ -z "$CHE_DATABASE" ] && export CHE_DATABASE=${CHE_DATA}/storage
  [ -z "$CHE_TEMPLATE_STORAGE" ] && export CHE_TEMPLATE_STORAGE=${CHE_DATA}/templates
  [ -z "$CHE_WORKSPACE_AGENT_DEV" ] && export CHE_WORKSPACE_AGENT_DEV=${CHE_DATA_HOST}/lib/ws-agent.tar.gz
  [ -z "$CHE_WORKSPACE_TERMINAL__LINUX__AMD64" ] && export CHE_WORKSPACE_TERMINAL__LINUX__AMD64=${CHE_DATA_HOST}/lib/linux_amd64/terminal
  [ -z "$CHE_WORKSPACE_TERMINAL__LINUX__ARM7" ] && export CHE_WORKSPACE_TERMINAL__LINUX__ARM7=${CHE_DATA_HOST}/lib/linux_arm7/terminal
  [ -z "$CHE_WORKSPACE_EXEC__LINUX__AMD64" ] && export CHE_WORKSPACE_EXEC__LINUX__AMD64=${CHE_DATA_HOST}/lib/linux_amd64/exec

  perform_database_migration

  # CHE_DOCKER_IP_EXTERNAL must be set if you are in a VM.
  HOSTNAME=${CHE_DOCKER_IP_EXTERNAL:-$(get_docker_external_hostname)}
  if has_external_hostname; then
    # Internal property used by Che to set hostname.
    export CHE_DOCKER_IP_EXTERNAL=${HOSTNAME}
  fi
  ### Necessary to allow the container to write projects to the folder
  [ -z "$CHE_WORKSPACE_STORAGE__MASTER__PATH" ] && export CHE_WORKSPACE_STORAGE__MASTER__PATH=${CHE_DATA}/workspaces
  [ -z "$CHE_WORKSPACE_STORAGE" ] && export CHE_WORKSPACE_STORAGE="${CHE_DATA_HOST}/workspaces"
  [ -z "$CHE_WORKSPACE_STORAGE_CREATE_FOLDERS" ] && export CHE_WORKSPACE_STORAGE_CREATE_FOLDERS=false

  # Move files from /lib to /lib-copy.  This puts files onto the host.
  rm -rf ${CHE_DATA}/lib/*
  mkdir -p ${CHE_DATA}/lib
  cp -rf ${CHE_HOME}/lib/* "${CHE_DATA}"/lib

  # Cleanup no longer in use stacks folder, accordance to a new loading policy.
  if [[ -d "${CHE_DATA}"/stacks ]];then
    rm -rf "${CHE_DATA}"/stacks
  fi

  # replace samples.json each run to make sure that we are using corrent samples from the assembly.
  # also it allows users to store their own samples which should not be touched by us.
  mkdir -p "${CHE_DATA}"/templates
  rm -rf "${CHE_DATA}"/templates/samples.json
  cp -rf "${CHE_HOME}"/templates/* "${CHE_DATA}"/templates

  # A che property, which names the Docker network used for che + ws to communicate
  if [ -z "$CHE_DOCKER_NETWORK" ]; then
    NETWORK_NAME="bridge"
  else
    NETWORK_NAME=$CHE_DOCKER_NETWORK
  fi
  export JAVA_OPTS="${JAVA_OPTS} -Dche.docker.network=$NETWORK_NAME"
}

get_che_data_from_host() {
  DEFAULT_DATA_HOST_PATH=/data
  CHE_SERVER_CONTAINER_ID=$(get_che_server_container_id)
  # If `docker inspect` fails $DEFAULT_DATA_HOST_PATH is returned
  echo $(docker inspect --format='{{(index .Volumes "/data")}}' $CHE_SERVER_CONTAINER_ID 2>/dev/null || echo $DEFAULT_DATA_HOST_PATH)
}

get_che_server_container_id() {
  # Returning `hostname` doesn't work when running Che on OpenShift/Kubernetes/Docker Cloud.
  # In these cases `hostname` correspond to the pod ID that is different from
  # the container ID
  echo $(basename "$(head /proc/1/cgroup || hostname)");
}

is_docker_for_mac_or_windows() {
  if uname -r | grep -q 'linuxkit'; then
    return 0
  elif uname -r | grep -q 'moby'; then
    return 0
  else
    return 1
  fi
}

get_docker_external_hostname() {
  if is_docker_for_mac_or_windows; then
    echo "localhost"
  else
    echo ""
  fi
}

has_external_hostname() {
  if [ "${HOSTNAME}" = "" ]; then
    return 1
  else
    return 0
  fi
}

# SITTERM / SIGINT
responsible_shutdown() {
  echo ""
  echo "Received SIGTERM"
  stop_che_server &
  wait ${PID}
  exit;
}

set -e
set +o posix

# setup handlers
# on callback, kill the last background process, which is `tail -f /dev/null` and execute the specified handler
trap 'responsible_shutdown' SIGHUP SIGTERM SIGINT

init
init_global_variables
set_environment_variables

CHE_INFRASTRUCTURE_ACTIVE=openshift
CHE_OPENSHIFT_CERT_LOCATION=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
CHE_OPENSHIFT_SERVICE_CERT_LOCATION=/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
CHE_OPENSHIFT_SIGNER_CERT_LOCATION=/tmp/service-signer.crt
CHE_JAVA_CERT_LOCATION=/etc/ssl/certs/java/cacerts
if [ "${CHE_INFRASTRUCTURE_ACTIVE}" = "openshift" ]; then
    if [ -f ${CHE_OPENSHIFT_SIGNER_CERT_LOCATION} ] && [ -f ${CHE_JAVA_CERT_LOCATION} ]; then
        tail -$(($(grep -c "^" ${CHE_OPENSHIFT_SERVICE_CERT_LOCATION})-$(grep -c "^" ${CHE_OPENSHIFT_CERT_LOCATION})-1)) ${CHE_OPENSHIFT_SERVICE_CERT_LOCATION} > ${CHE_OPENSHIFT_SIGNER_CERT_LOCATION}
        chmod a+w ${CHE_JAVA_CERT_LOCATION}
        keytool -importcert -noprompt -file ${CHE_OPENSHIFT_SIGNER_CERT_LOCATION} -storepass changeit -keystore ${CHE_JAVA_CERT_LOCATION} -alias openshiftcert
        chmod a-w ${CHE_JAVA_CERT_LOCATION}
    fi
fi

# run che
start_che_server &

PID=$!

# See: http://veithen.github.io/2014/11/16/sigterm-propagation.html
wait ${PID}
wait ${PID}
EXIT_STATUS=$?

# wait forever
while true
do
  tail -f /dev/null & wait ${!}
done
