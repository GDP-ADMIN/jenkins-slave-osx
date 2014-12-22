# Jenkins Slave for OS X

Scripts to create and run a [Jenkins](http://jenkins-ci.org) slave via [Java Web Start](https://wiki.jenkins-ci.org/display/JENKINS/Distributed+builds#Distributedbuilds-LaunchslaveagentviaJavaWebStart) (JNLP) on OS X as a Launch Daemon.



## Quick Start
`bash <( curl -L https://raw.githubusercontent.com/royingantaginting/jenkins-slave-osx/master/install.sh )`



## Features
OS X slaves created with this script:
* Start on system boot
* Run as an independent user



## Install
`bash <( curl -L https://raw.github.com/rhwood/jenkins-slave-osx/master/install.sh ) [options]`

The install script has the following options:
* `--java-args="ARGS"` to specify any optional java arguments. *Optional;* the installer does not test these arguments.
* `--master=URL` to specify the Jenkins Master on the command line. *Optional;* the installer prompts for this if not specified on the command line.
* `--node=NAME` to specify the Slave's node name. *Optional;* this defaults to the OS X hostname and is verified by the installer.
* `--user=NAME` to specify the Jenkins user who authenticates the slave. *Optional;* this defaults to your username on the OS X slave and is verified by the installer.
* `--token=TOKEN` to specify the Jenkins user token who authenticates the slave. *Optional;* the installer prompts for this if not specified on the command line



## Update
Simply rerun the installer. It will reinstall the scripts, but use existing configuration settings.



## Configuration
The file ``Library/Preferences/org.jenkins-ci.slave.jnlp.conf`` in ``/var/lib/jenkins`` (assuming an installation in the default location) can be used to configure this service with these options:
* `JAVA_ARGS` specifies any optional java arguments to be passed to the slave. This may be left blank.
* `JENKINS_SLAVE` specifies the node name for the slave. This is required.
* `JENKINS_MASTER` specifies the URL for the Jenkins master. This is required.
* `JENKINS_USER` specifies the Jenkins user used to bind the master to the slave. This is required.
* `HTTP_PORT` specifies the nonstandard port used to communicate with the Jenkins master. This may be left blank for port 80 (http) or 443 (https).
These settings are initially set by the installation script, and only need to be changed if that script is invalidated. The slave must be restarted for changes to take effect.
