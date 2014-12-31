#!/bin/bash
#
# Install the Jenkins JNLP slave LaunchDaemon on OS X
#
# See https://github.com/rhwood/jenkins-slave-osx for usage

set -u

SERVICE_USER=${SERVICE_USER:-"jenkins"}
SERVICE_GROUP=${SERVICE_GROUP:-"${SERVICE_USER}"}
SERVICE_HOME=${SERVICE_HOME:-"/var/lib/${SERVICE_USER}"}
SERVICE_CONF=""   # set in create_user function
SERVICE_WRKSPC="" # set in create_user function
MASTER_NAME=""    # set default to jenkins later
MASTER_USER=""    # set default to `whoami` later
MASTER=""
MASTER_HTTP_PORT=""
SLAVE_NODE=""
SLAVE_TOKEN=""
JAVA_ARGS=${JAVA_ARGS:-""}
INSTALL_TMP=`mktemp -d -q -t org.jenkins-ci.slave.jnlp`
DOWNLOADS_PATH=https://raw.githubusercontent.com/royingantaginting/jenkins-slave-osx/master

function create_user() {
	if dscl /Local/Default list /Users | grep -q ${SERVICE_USER} ; then
		echo "Using pre-existing service account ${SERVICE_USER}"
		SERVICE_HOME=$( dscl /Local/Default read /Users/${SERVICE_USER} NFSHomeDirectory | awk '{ print $2 }' )
		SERVICE_GROUP=$( dscl /Local/Default search /Groups gid $( dscl /Local/Default read /Users/${SERVICE_USER} PrimaryGroupID | awk '{ print $2 }' ) | head -n1 | awk '{ print $1 }' )
	else
		echo "Creating service account ${SERVICE_USER}..."
		if dscl /Local/Default list /Groups | grep -q ${SERVICE_GROUP} ; then
			NEXT_GID=$( dscl /Local/Default list /Groups gid | grep ${SERVICE_GROUP} | awk '{ print $2 }' )
		else
			NEXT_GID=$((`dscl /Local/Default list /Groups gid | awk '{ print $2 }' | sort -n | grep -v ^[5-9] | tail -n1` + 1))
			sudo dscl /Local/Default create /Groups/${SERVICE_GROUP}
			sudo dscl /Local/Default create /Groups/${SERVICE_GROUP} PrimaryGroupID $NEXT_GID
			sudo dscl /Local/Default create /Groups/${SERVICE_GROUP} Password \*
			sudo dscl /Local/Default create /Groups/${SERVICE_GROUP} RealName 'Jenkins Node Service'
		fi

		NEXT_UID=$((`dscl /Local/Default list /Users uid | awk '{ print $2 }' | sort -n | grep -v ^[5-9] | tail -n1` + 1))
		sudo dscl /Local/Default create /Users/${SERVICE_USER}
		sudo dscl /Local/Default create /Users/${SERVICE_USER} UniqueID $NEXT_UID
		sudo dscl /Local/Default create /Users/${SERVICE_USER} PrimaryGroupID $NEXT_GID
		sudo dscl /Local/Default create /Users/${SERVICE_USER} UserShell /bin/bash
		sudo dscl /Local/Default create /Users/${SERVICE_USER} NFSHomeDirectory ${SERVICE_HOME}
		sudo dscl /Local/Default create /Users/${SERVICE_USER} Password \*
		sudo dscl /Local/Default create /Users/${SERVICE_USER} RealName 'Jenkins Node Service'
		sudo dseditgroup -o edit -a ${SERVICE_USER} -t user ${SERVICE_USER}
	fi
	SERVICE_CONF=${SERVICE_HOME}/Library/Preferences/org.jenkins-ci.slave.jnlp.conf
	SERVICE_WRKSPC=${SERVICE_HOME}/Library/Developer/org.jenkins-ci.slave.jnlp
}

function install_files() {

	if [ ! -d ${SERVICE_WRKSPC} ] ; then
		sudo mkdir -p ${SERVICE_WRKSPC}
	fi

	sudo curl --silent -L --url ${DOWNLOADS_PATH}/org.jenkins-ci.slave.jnlp.plist -o ${SERVICE_WRKSPC}/org.jenkins-ci.slave.jnlp.plist
	sudo sed -i '' "s#\${JENKINS_HOME}#${SERVICE_WRKSPC}#g" ${SERVICE_WRKSPC}/org.jenkins-ci.slave.jnlp.plist
	sudo sed -i '' "s#\${JENKINS_USER}#${SERVICE_USER}#g" ${SERVICE_WRKSPC}/org.jenkins-ci.slave.jnlp.plist
	sudo rm -f /Library/LaunchDaemons/org.jenkins-ci.slave.jnlp.plist
	sudo install -o ${SERVICE_USER} -g ${SERVICE_GROUP} -m 644 ${SERVICE_WRKSPC}/org.jenkins-ci.slave.jnlp.plist ${SERVICE_HOME}/Library/LaunchAgents/org.jenkins-ci.slave.jnlp.plist
	
	sudo curl --silent -L --url ${DOWNLOADS_PATH}/slave.jnlp.sh -o ${SERVICE_WRKSPC}/slave.jnlp.sh
	sudo chmod 755 ${SERVICE_WRKSPC}/slave.jnlp.sh
	sudo sed -i -e "s|^JENKINS_CONF=.*|JENKINS_CONF=${SERVICE_CONF}|" ${SERVICE_WRKSPC}/slave.jnlp.sh

	# jenkins should own jenkin's home directory and all its contents
	sudo chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${SERVICE_HOME}
	# create a logging space
	if [ ! -d /var/log/${SERVICE_USER} ] ; then
		sudo mkdir /var/log/${SERVICE_USER}
		sudo chown ${SERVICE_USER}:wheel /var/log/${SERVICE_USER}
	fi
}

function process_args {
	if [ -f ${SERVICE_CONF} ]; then
		sudo chmod 666 ${SERVICE_CONF}
		source ${SERVICE_CONF}
		sudo chmod 400 ${SERVICE_CONF}
		SLAVE_NODE="${SLAVE_NODE:-$JENKINS_SLAVE}"
		MASTER=${MASTER:-$JENKINS_MASTER}
		MASTER_HTTP_PORT=${HTTP_PORT}
		MASTER_USER=${MASTER_USER:-$JENKINS_USER}
	fi

	while [ $# -gt 0 ]; do
		case $1 in
			--node=*) SLAVE_NODE="${1#*=}" ;;
			--user=*) MASTER_USER=${1#*=} ;;
			--master=*) MASTER=${1#*=} ;;
			--token=*) SLAVE_TOKEN=${1#*=} ;;
			--java-args=*) JAVA_ARGS="${1#*=}" ;;
		esac
		shift
	done
}

function configure_daemon {
	if [ -z $MASTER ]; then
		MASTER=${MASTER:-"http://jenkins"}
		echo
		read -p "URL for Jenkins master [$MASTER]: " RESPONSE
		MASTER=${RESPONSE:-$MASTER}
	fi
	while ! curl -L --url ${MASTER}/jnlpJars/slave.jar --insecure --location --silent --fail --output ${INSTALL_TMP}/slave.jar ; do
		echo "Unable to connect to Jenkins at ${MASTER}"
		read -p "URL for Jenkins master: " MASTER
	done
	MASTER_NAME=`echo $MASTER | cut -d':' -f2 | cut -d'.' -f1 | cut -d'/' -f3`
	PROTOCOL=`echo $MASTER | cut -d':' -f1`
	MASTER_HTTP_PORT=`echo $MASTER | cut -d':' -f3`
	if 	[ "$PROTOCOL" == "$MASTER" ] ; then
		PROTOCOL="http"
		MASTER_HTTP_PORT=`echo $MASTER | cut -d':' -f2`
		[ -z $MASTER_HTTP_PORT ] || MASTER="${PROTOCOL}://`echo $MASTER | cut -d':' -f2`"
	else
		[ -z $MASTER_HTTP_PORT ] || MASTER="${PROTOCOL}:`echo $MASTER | cut -d':' -f2`"
	fi
	[ ! -z $MASTER_HTTP_PORT ] && MASTER_HTTP_PORT=":${MASTER_HTTP_PORT}"
	if [ -z "$SLAVE_NODE" ]; then
		SLAVE_NODE=${SLAVE_NODE:-`hostname -s | tr '[:upper:]' '[:lower:]'`}
		echo
		read -p "Name of this slave on ${MASTER_NAME} [$SLAVE_NODE]: " RESPONSE
		SLAVE_NODE="${RESPONSE:-$SLAVE_NODE}"
	fi
	if [ -z $MASTER_USER ]; then
		[ "${SERVICE_USER}" != "jenkins" ] && MASTER_USER=${SERVICE_USER} || MASTER_USER=`whoami`
		echo
		read -p "Account that ${SLAVE_NODE} connects to ${MASTER_NAME} as [${MASTER_USER}]: " RESPONSE
		MASTER_USER=${RESPONSE:-$MASTER_USER}
	fi
	echo
	echo "${MASTER_USER}'s API token is required to authenticate a JNLP slave."
	echo "The API token is listed at ${MASTER}${MASTER_HTTP_PORT}/user/${MASTER_USER}/configure"
	while ! curl -L --url ${MASTER}${MASTER_HTTP_PORT}/user/${MASTER_USER} --user ${MASTER_USER}:${SLAVE_TOKEN} --insecure --silent --head --fail --output /dev/null ; do
		echo "Unable to authenticate ${MASTER_USER} with this token"
		read -p "API token for ${MASTER_USER}: " SLAVE_TOKEN
	done
}

function write_config {
	# ensure JAVA_ARGS specifies a setting for java.awt.headless (default to true)
	[[ "$JAVA_ARGS" =~ -Djava.awt.headless= ]] || JAVA_ARGS="${JAVA_ARGS} -Djava.awt.headless=true"
	# create config directory
	sudo mkdir -p `dirname ${SERVICE_CONF}`
	sudo chmod 777 `dirname ${SERVICE_CONF}`
	# make the config file writable
	if [ -f ${SERVICE_CONF} ]; then
		sudo chmod 666 ${SERVICE_CONF}
	fi
	# write the config file
	[[ "$MASTER_HTTP_PORT" =~ ^: ]] && MASTER_HTTP_PORT=${MASTER_HTTP_PORT#":"}
	local CONF_TMP=${INSTALL_TMP}/org.jenkins-ci.slave.jnlp.conf
	:> ${CONF_TMP}
	echo "JENKINS_SLAVE=\"${SLAVE_NODE}\"" >> ${CONF_TMP}
	echo "JENKINS_MASTER=${MASTER}" >> ${CONF_TMP}
	echo "HTTP_PORT=${MASTER_HTTP_PORT}" >> ${CONF_TMP}
	echo "JENKINS_USER=${MASTER_USER}" >> ${CONF_TMP}
	echo "JENKINS_TOKEN=${SLAVE_TOKEN}" >> ${CONF_TMP}
	echo "JAVA_ARGS=\"${JAVA_ARGS}\"" >> ${CONF_TMP}
	sudo mv ${CONF_TMP} ${SERVICE_CONF}
	# secure the config file
	sudo chmod 755 `dirname ${SERVICE_CONF}`
	sudo chmod 644 ${SERVICE_CONF}
	sudo chown -R ${SERVICE_USER}:${SERVICE_GROUP} ${SERVICE_HOME}
}

function start_daemon {
	echo "
The Jenkins JNLP Slave service is installed

This service can be started using the command
    sudo launchctl load /Library/LaunchDaemons/org.jenkins-ci.slave.jnlp.plist
and stopped using the command
    sudo launchctl unload /Library/LaunchDaemons/org.jenkins-ci.slave.jnlp.plist

This service logs to /var/log/${SERVICE_USER}/org.jenkins-ci.slave.jnlp.log
"
	CONFIRM=${CONFIRM:-"yes"}
	if [[ "${CONFIRM}" =~ ^[Yy] ]] ; then
		sudo launchctl load -F /Library/LaunchDaemons/org.jenkins-ci.slave.jnlp.plist
	fi
}

function cleanup {
	rm -rf ${INSTALL_TMP}
	exit $1
}

function rawurlencode() {
	# see http://stackoverflow.com/a/10660730/176160
	local string="${1}"
	local strlen=${#string}
	local encoded=""

	for (( pos=0 ; pos<strlen ; pos++ )); do
		c=${string:$pos:1}
		case "$c" in
			[-_.~a-zA-Z0-9] ) o="${c}" ;;
			* )               printf -v o '%%%02x' "'$c"
		esac
		encoded+="${o}"
	done
	echo "${encoded}"    # You can either set a return variable (FASTER) 
	REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}


CONFIRM=${CONFIRM:-"yes"}
if [[ "${CONFIRM}" =~ ^[Yy] ]] ; then
	create_user
	
	# $@ must be quoted in order to handle arguments that contain spaces
	# see http://stackoverflow.com/a/8198970/14731
	process_args "$@"
	echo "Installing files..."
	install_files
	echo "Configuring daemon..."
	configure_daemon
	write_config
	start_daemon
else
	echo "Aborting installation"
	cleanup 1
fi

cleanup 0
