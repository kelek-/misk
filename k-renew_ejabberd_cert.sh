#!/bin/bash
#    ~     .         / ~
#  *      /       \ /
#     *  /     - --*-- ~
# \  ^  //     *    \  _ ____ _
# \\ | //_____   _\___________/_>
#  \\|//|--==|\____\--=     /\
# -==+==|->> |/-==/\\      /  \
#  //|\\|   _/   /  \\_  \/.  /
# //.| \\   \  _/___/_/_   \_/
# /,;|<//\  _____ -==/_\__  \_/_
#   .^// \\  | /   //\  \_>>_/_\ _
# ,*_/    \. |/   //__\   \\   )\\\
# `.|________/_____________\\_/_\\ \
# ,'|_______/__\_/zNr/dS!_//__\\ _) \
# `   --- -/-  <_\/________/_k!\/_>>
#----------------------------------------------------------------------#
#                  k-renew_ejabberd_certificate.sh v1.0                #
#----------------------------------------------------------------------#
# Description:                                                         #
#---                                                                   #
# Script to remove the need of manually renewing your LetsEncrypt SSL  #
# certificate for ejabberd.                                            #
#-----+                                                                #
# Prerequisites:                                                       #
#   - CertBot (https://github.com/certbot/certbot)                     #
#   - BASH version 4.x                                                 #
# NOTE: If you run an older version of BASH, you can replace the '>&', #
# which was introduced with BASH 4, with the common '2&>1' - then it   #
# *should* work with older BASH versions, however it's not tested -    #
# please leave me a comment if you did so! Replacing of course         #
# without ''. After that, you need to remove the check for the BASH    #
# version, which you can find beginnig on line 161 to 165.             # 
# Also note, that this script is BASH specific an therefor not POSIX   #
# compliant.                                                           #
#-----+                                                                #
# Installation:                                                        #  
#---                                                                   #
# Simply crontab this script to run once every three months. If you    #
# want to make 100% sure, that your ejabberd certificate will not      #
# expire, you can crontab it to run once a month :).                   #
#                                                                      #
# NOTE: This script assumes, that it can spin up a temporary webserver #
# to validate the certificate with LetsEncrypt. However, if you run a  #
# webserver on your own, you can change the command line options to    #
# place the files into your own webroot and validate it with           #
# LetsEncrypt. The variable you want to edit is:                       #
#  -> 'CERTBOT_RENEW_COMMAND'                                          #
# Refer to the CertBot manual to learn how to use your own webserver   #
# to validate your certificate.                                        #
#                                                                      #
# Example crontab:                                                     #
# 0 * 30 * * /root/k-renew_ejabberd_certificate.sh &> /dev/null        #
#                                                                      #
# This crontab will run every month on the 30th at 00:00 AM.           #
#                                                                      #
#                                                                      #
# MAKE SURE TO CHANGE THE SETTINGS!                                    # 
#-----+                                                                #
# Bugs:                                                                #
#---                                                                   #
# Not that I know of any, feel free to msg me - you know where!        #
#-----+                                                                #
# Sincerly,                                                            #
#  |k @ 11th January of 2o17                                           #
#----------------------------------------------------------------------#     


# <  --                     certbot settings                    --  >   # 
declare -r  CERTBOT_DOMAIN=""                                           # Domain to renew
declare -r  CERTBOT_WORK_DIRECTORY="/etc/letsencrypt/live"              # Work directory of the certbot (the folder where it stores the signed certificates (w/o domain) 
declare -r  CERTBOT_DIRECTORY="/home/pi/sources/certbot"                # Git repo directory of the certbot (or where you have it saved)
declare -r  CERTBOT_BINARY="certbot-auto"                               # Certbot binary name
declare -ir CERTBOT_AUTH_PORT=443                                       # Port to use for the certification authentication (443 is the default)
declare -ir CERTBOT_RSA_KEY_SIZE=2048                                   # Size of the rsa key to request - valid are 2048 and 4096, however 4096 bits are highly adviced!

# <  --                     general settings                    --  >   # 
declare -ir USE_IPTABLES=0                                              # Use iptables to remove and add a rule for the CERTBOT_AUTH_PORT. (REMEMBER: This is BASH! 0 represents true, everything else represents false!!) 
declare -ir SHUTDOWN_WAIT_TIME=20                                       # Time to wait for ejabberd to shut down. If you feel like you don't need to wait any time for it, set it to 0. I don't see the point in adding another boolean for skipping the wait time :)
declare -r  EJABBERD_USER="ejabberd"                                    # User which runs ejabberd (default: ejabberd)
declare -r  EJABBERD_GROUP="ejabberd"                                   # Group which the ejabberd user is in (default: ejabberd)
declare -r  EJABBERD_CERTIFICATE="/etc/ejabberd/ejabberd.pem"           # Path to the ejabberd.pem file (default /etc/ejabberd/ejabberd.pem)

# <  --                       log settings                      --  >   #
declare -r  LOG_LEVEL="INFO"                                            # Valid: DEBUG, INFO, WARNING, ERROR, NONE (this only affects the output to stdout - it will be logged to the file anway.)
declare -r  LOG_DATE_FORMAT="%d.%m.%y %H:%m:%S"                         # See man date for help
declare -r  LOG_FILE="/var/log/k-renew_ejjaber_certigicate.log"         # Logfile to write to





# <   --        Advanced Configuration (usually not needed)      --   > #
# The cli args to pass to the certbot - use certbot documentation for more information about the cli arguments
declare -r  CERTBOT_RENEW_COMMAND="certonly --non-interactive --agree-tos --force-renewal --standalone --rsa-key-size ${CERTBOT_RSA_KEY_SIZE} --tls-sni-01-port ${CERTBOT_AUTH_PORT} -d ${CERTBOT_DOMAIN}"



#                                                                       #
# <  --                     script starts here                    --  > #
#                                                                       #

# Both iptables and ejabberdctl are required to use this script
# As both are referred later on I decided to assign them a seperate variabl
declare -r __IPTABLES_BINARY="$(which iptables)"
declare -r __EJABBERDCTL_BINARY="$(which grep)"
declare -a __REQUIERED_BINARIES=(
  "printf"
  "getent"
  "cat"
  "chown"
  "${__IPTABLES_BINARY}"
  "${__EJABBERDCTL_BINARY}"
  "${CERTBOT_DIRECTORY}/${CERTBOT_BINARY}"
)

#-----------------------------
# certRenew::init
#------
# Description:
#--------
#  Check all settings and pre-requisites, which need to be met
#------
# Globals:
#--------
#   #  | Name                  | Origin   | Access (r = read, w = write)
#------+-----------------------+----------+--------------------------------------->
#   1  - REQUIRED_BINARIES      (internal): r
#   2  - BASH_VERSION           (BASH    ): r
#   3  - CERTBOT_WORK_DIRECTORY (internal): r
#   4  - USER                   (BASH)    : r
#   5  - LINENO                 (BASH)    : r
#   6  - CERTBOT_DIRECTORY      (internal): r
#   7  - CERTBOT_AUTH_PORT      (internal): r
#   8  - CERTBOT_RSA_KEY_SIZE   (internal): r
#   9  - CERTBOT_DOMAIN		(internal): r
#  10  - CERTBOT_RENEW_COMMAND  (internal): r
#  11  - USE_IPTABLES           (internal): r
#  12  - SHUTDOWN_WAIT_TIME     (internal): r
#  13  - EJABBERD_USER          (internal): r
#  14  - EJABBERD_GROUP         (internal): r
#  15  - EJABBERD_CERTIFICATE   (internal): r
#------
# Arguments:
#----------
#   #  | Variable                   | Type          | Description                                                       
#------+----------------------------+---------------+--------------------------->
#   --
#------
# Returns:
#--------
#   #  | Type    | Description
#------+---------+-------------------------------------------------->
#   0 - (return): Everything went fine
#   1 - (exit  ): BASH version is too old (4.x requiered)
#   2 - (exit  ): Missing required binary
#   3 - (exit  ): CERTBOT_WORK_DIRECTORY is invalid (checks permissions too!)
#   4 - (exit  ): CERTBOT_AUTH_PORT has an invalid value set
#   5 - (exit  ): CERTBOT_RSA_KEY_SIZE has an invalid value set
#   6 - (exit  ): CERTBOT_DOMAIN not set
#   7 - (exit  ): CERTBOT_RENEW_COMMAND not set
#   8 - (exit  ): USE_IPTABLES has an invalid value set 
#   9 - (exit  ): SHUTDOWN_WAIT_TIME has an invalid value set
#  10 - (exit  ): EJABBERD_USER is not a valid user
#  11 - (exit  ): EJABBERD_GROUP is not a valid group
#  12 - (exit  ): EJABBERD_CERTIFICATE is not accessible for the current user or couldn't be created
#-----------------------------
function certRenew::init () {
  # BASH version v4.x is needed at least
  # Note: This (lame) check works only until BASH version 9.x, after that a new check needs to be implemented - let's see in 2133 if there is still need for that ;P
  [[ "${BASH_VERSION}" =~ ^[4-9]\. ]] || {
    echo "ERROR: You are running '${BASH_VERSION}', but this script needs at least BASH v4.x" >&2;
    exit 1;
  };

  # check for necessary binaries
  for binary in "${__REQUIERED_BINARIES[@]}"; do
    command -v "${binary}" &> /dev/null || {
      echo "ERROR: '${binary} is not installed, but this scripts needs it. Install it!" >&2;
      exit 2;
    };
  done


  # init logging
  certRenew::init_logging

  # check for directories
  ( [ -e "${CERTBOT_WORK_DIRECTORY}" ] && [ -d "${CERTBOT_WORK_DIRECTORY}" ] && [ -r "${CERTBOT_WORK_DIRECTORY}" ] && [ -w "${CERTBOT_WORK_DIRECTORY}" ] ) || {
    certRenew::log "The working directory 'WORK_DIRECTORY' ('${CERTBOT_WORK_DIRECTORY}') is either not a valid directory or not accesible for the current user ('${USER}')." "99" "${LINENO}";
    exit 3;
  };

  ( [ -e "${CERTBOT_DIRECTORY}" ] && [ -d "${CERTBOT_DIRECTORY}" ] && [ -r "${CERTBOT_DIRECTORY}" ] && [ -w "${CERTBOT_DIRECTORY}" ] ) || {
    certRenew::log "The certbot directory 'CERTBOT_DIRECTORY' ('${CERTBOT_DIRECTORY}') is either not a valid directory or not accesible for the current user ('${USER}')." "99" "${LINENO}";
    exit 4;
  };


  # check the values of the settings
  ( [[ "${CERTBOT_AUTH_PORT}" =~ ^[[:digit:]]+$ ]] && [ "${CERTBOT_AUTH_PORT}" -gt "0" ] && [ "${CERTBOT_AUTH_PORT}" -le "65535" ] ) || {
    certRenew::log "'CERTBOT_AUTH_PORT' has an invalid value ('${CERTBOT_AUTH_PORT}') set." "99" "${LINENO}";
    exit 5;
  };

  [[ "${CERTBOT_RSA_KEY_SIZE}" =~ ^(2048|4096)$ ]] || { 
    certRenew::log "'CERTBOT_RSA_KEY_SIZE' has an invalid value ('${CERTBOT_RSA_KEY_SIZE}') set." "99" "${LINENO}";
    exit 6;
  };
 
  [ ! ${CERTBOT_RSA_KEY_SIZE} -eq 2048 ] || {
    certRenew::log "'CERTBOT_RSA_KEY_SIZE' is set to 2048 - recommended is 4096." "10" "${LINENO}";
    # just an info msg - no need to exit
  };

  [ -n "${CERTBOT_DOMAIN}" ] || {
    certRenew::log "'CERTBOT_DOMAIN' not set - we cannot get a certificate for an empty domain!" "99" "${LINENO}";
    exit 7;
  };

  [ -n "${CERTBOT_RENEW_COMMAND}" ] || {
    certRenew::log "'CERTBOT_RENEW_COMMAND' not set - we cannot renew this certification, when we don't have a command to do so!" "99" "${LINENO}";
    exit 8;
  };

  [[ "${USE_IPTABLES}" =~ ^[[:digit:]]+$ ]] || {
    certRenew::log "'USE_IPTABLES' has an invalue value ('${USE_IPTABLES}') set." "99" "${LINENO}";
    exit 9;
  };

  [[ "${SHUTDOWN_WAIT_TIME}" =~ ^[[:digit:]]+$ ]] || {
    certRenew::log "'SHUTDOWN_WAIT_TIME' has an invalue value ('${SHUTDOWN_WAIT_TIME}') set." "99" "${LINENO}";
    exit 10;
  };

  getent passwd "${EJABBERD_USER}" &> /dev/null || {
    certRenew::log "User set for 'EJABBERD_USER' ('${EJABBERD_USER}') is invalid." "99" "${LINENO}";
    exit 11;
  };

  getent group "${EJABBERD_GROUP}" &> /dev/null || {
    certRenew::log "Group set for 'EJABBERD_GROUP' ('${EJABBERD_GROUP}') is invalid." "99" "${LINENO}";
    exit 12; 
  };

  ( [ -e "${EJABBERD_CERTIFICATE}" ] && [ -f "${EJABBERD_CERTIFICATE}" ] && [ -w "${EJABBERD_CERTIFICATE}" ] ) || {
    touch "${EJABBERD_CERTIFICATE}" || {
      certRenew::log "Ejabberd certificate ('${EJABBERD_CERTIFICATE}') is not writeable for the current user and could not be created." "99" "${LINENO}";
      exit 13;
    };
  };

  certRenew::log "certRenew::init finished without any errors." "0" "${LINENO}"
  
  return 0;
} #; function certRenew::init ( )

#-----------------------------
# certRenew::init_logging
#------
# Description:
#--------
#   Check every setting, which is relevant for logging
#------
# Globals:
#--------
#   #  | Name             | Origin   | Access (r = read, w = write)
#------+------------------+----------+--------------------------------------->
#   1  - FUNCNAME          (BASH)    : r
#   2  - LINENO            (BASH)    : r
#   3  - LOG_DATE_FORMAT   (internal): r
#   4  - LOG_FILE          (internal): r
#   5  - LOG_LEVEL         (internal): r
#------
# Arguments:
#----------
#   #  | Variable                   | Type          | Description                                                       
#------+----------------------------+---------------+--------------------------->
#   --
#------
# Returns:
#--------
#   #  | Type    | Description
#------+---------+-------------------------------------------------->
#   0 - (return): Everything went fine
#   1 - (exit  ): Logfile couldn't be created
#   2 - (exit  ): Invalid loglevel spefified
#-----------------------------
function certRenew::init_logging () {
  # try creating the logfile
  touch "${LOG_FILE}" &> /dev/null || {
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: Can't create log file '${LOG_FILE}' with the current user ('${USER}')\n" "ERROR" >&2;
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >&2;
    exit 1;
  };

  # check for a valid log level
  [[ "${LOG_LEVEL}" =~ ^(ERR|WARN|INFO|DBG|ERROR|WARNING|INFORMATION|DEBUG|ALL|NONE)$ ]] || {
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: Invalid log level ('${LOG_LEVEL}') specified.\n" "ERROR" >&2;
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: Valid log levels are: ALL, DEBUG, INFO, WARNING, ERROR, NONE.\n" "ERROR" >&2;
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: However, NONE is not adviced, as no errors are shown at all.\n" "ERROR" >&2;
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >&2;
    exit 2
  };

  return 0;
} #; certRenew::init_logging ( )

#-----------------------------
# certRenew::log <message> <level> <lineNumber> [exitCode]
#------
# Description:
#--------
#   Write log to file and/or stdout.
#------
# Globals:
#--------
#   #  | Name             | Origin   | Access (r = read, w = write)
#------+------------------+----------+--------------------------------------->
#   1  - FUNCNAME          (BASH)    : r
#   2  - LINENO            (BASH)    : r
#   3  - LOG_DATE_FORMAT   (internal): r
#   4  - LOG_FILE          (internal): r
#   5  - LOG_LEVEL         (internal): r
#------
# Arguments:
#----------
#   #  | Variable                   | Type          | Description                                                       
#------+----------------------------+---------------+--------------------------->
#   $1 - <message>                   (string       ): Message to log
#   $2 - <level >                    (integer      ): Level of this message (the higer the number, the more important the message will be threated)
#   $3 - <lineNumber>                (integer      ): Line number, where the call to this function came from
#   $4 - [exitCode]                  (integer      ): Only used, when the loglevel is 99 - which means, print the message and exit with a (custom) exitCode.
#                                                     If this argument is not passed, the exitCode will be 2.
#------
# Returns:
#--------
#   #  | Type    | Description
#------+---------+-------------------------------------------------->
#   0 - (return): Everything went fine
#   1 - (exit  ): Not enough arguments are given
#   2 - (exit  ): Level has an invalid (non-integer) value set
#   3 - (exit  ): Custom exitCode is given, but has an invalid (non-integer) value set
#   4 - (exit  ): Custom exitCode is given, but the exitCode is 99, which is reserved
#  99 - (exit  ): Message level is 99 and no custom exitCode is given (NO error!)
#-----------------------------
function certRenew::log () {
  [ "${#}" -ge 3 ] || {
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Not enough arguments recieved. Expected 3, recieved '${#}'\n" "ERROR" >&2
    printf "["$(date "+${LOG_DATE_FORMAT}")"] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >&2
    exit 1;
  };

  declare message="${1}"
  declare -i level="${2}"
  declare -i lineNumber="${3}"

  declare -i exitCode=99
  # custom exitCode given
  [ -z "${4}" ] || {
    # exitCode is 99, which is reserved
    [ ! "${4}" -eq "99" ] || {
      [ -z "${LOG_FILE}" ] || {
        printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Invalid value set for 'exitCode'. Expected: Value not equal to 99 Recieved: '${exitCode}'.\n" "ERROR" >> "${LOG_FILE}";
        printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >> "${LOG_FILE}";
      };
      printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Invalid value set for 'exitCode'. Expected: Value not equal to 99, Recieved: '${exitCode}'.\n" "ERROR" >&2; 
      printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >&2;
      exit 4;
    };

    # custom exitCode is valid
    exitCode="${4}";
  };

  declare lastFunction="${FUNCNAME[1]}"
  declare timeStamp="$(date "+${LOG_DATE_FORMAT}")"
  declare -i quitAfterMessage=1


  # check values before proceeding with the message handling
  if [[ ! "${level}" =~ ^[[:digit:]]+$ ]]; then
    if [ -n "${LOG_FILE}" ]; then
	printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Invalid value set for 'level'. Expected: Integer, Recieved: '${level}'.\n" "ERROR" >> "${LOG_FILE}"
        printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >> "${LOG_FILE}"
    fi
    printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Invalid value set for 'level'. Expected: Integer, Recieved: '${level}'.\n" "ERROR" >&2
    printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >&2
    exit 2;
  fi

  if [[ ! "${exitCode}" =~ ^[[:digit:]]+$ ]]; then
    if [ -n "${LOG_FILE}" ]; then
        printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Invalid value set for 'exitCode'. Expected: Integer, Recieved: '${exitCode}'.\n" "ERROR" >> "${LOG_FILE}"
        printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >> "${LOG_FILE}"
    fi
    printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: Invalid value set for 'exitCode'. Expected: Integer, Recieved: '${exitCode}'.\n" "ERROR" >&2
    printf "[${timeStamp}] %-11s: ${FUNCNAME[0]}, line ${LINENO}: ${FUNCNAME[0]} was called from ${FUNCNAME[1]}.\n" "ERROR" >&2
    exit 3;
  fi


  # re-map message level to make it easier to read
  declare messageLevel=""
  if [ "${level}" -le 5 ]; then
    messageLevel="DEBUG"
  elif [ "${level}" -le 10 ] && [ ${level} -gt 5 ]; then
    messageLevel="INFORMATION"
  elif [ "${level}" -le 15 ] && [ ${level} -gt 10 ]; then
    messageLevel="WARNING"
  elif [ "${level}" -ge 20 ] && [ ! ${level} -eq 99 ]; then
    messageLevel="ERROR"
  elif [ "${level}" -eq 99 ]; then
    messageLevel="ERROR"
    quitAfterMessage=0
  fi

  # we print the message to the logfile in any case
  printf "[${timeStamp}] %-11s: %-25s, line %-6s, debug level %-2s: %s\n" "${messageLevel}" "${lastFunction}" "${lineNumber}" "${level}" "${message}" >> "${LOG_FILE}"



  if [ "${LOG_LEVEL}" = "NONE" ] && [ ! "${quitAfterMessage}" -eq 0 ]; then # user does not want to have anything logged to stdout
    return 0;
  elif [ "${LOG_LEVEL}" = "NONE" ] && [ "${quitAfterMessage}" -eq 0 ]; then # however, there we have an error, so we exit with the (custom) error code
    exit ${exitCode};
  fi


  # print the messages based on the loglevel
  if [ "${messageLevel}" = "DEBUG" ] && [[ "${LOG_LEVEL}" =~ ^(DBG|DEBUG|ALL)$ ]]; then
    printf "[${timeStamp}] %-11s: %-25s, line %-6s, debug level %-2s: %s\n" "${messageLevel}" "${lastFunction}" "${lineNumber}" "${level}" "${message}"
  elif [ "${messageLevel}" = "INFORMATION" ] && [[ "${LOG_LEVEL}" =~ ^(INFO|DBG|INFORMATION|DEBUG|ALL)$ ]]; then
    printf "[${timeStamp}] %-11s: %-25s, line %-6s, debug level %-2s: %s\n" "${messageLevel}" "${lastFunction}" "${lineNumber}" "${level}" "${message}"
  elif [ "${messageLevel}" = "WARNING" ] && [[ "${LOG_LEVEL}" =~ ^(WARN|INFO|DBG|WARNING|INFORMATION|DEBUG|ALL)$ ]]; then
    printf "[${timeStamp}] %-11s: %-25s, line %-6s, debug level %-2s: %s\n" "${messageLevel}" "${lastFunction}" "${lineNumber}" "${level}" "${message}"
  elif [ "${messageLevel}" = "ERROR" ] && [[ "${LOG_LEVEL}" =~ ^(ERR|WARN|INFO|DBG|ERROR|WARNING|INFORMATION|DEBUG|ALL)$ ]]; then
    printf "[${timeStamp}] %-11s: %-25s, line %-6s, debug level %-2s: %s\n" "${messageLevel}" "${lastFunction}" "${lineNumber}" "${level}" "${message}" >&2
  fi


  if [ "${quitAfterMessage}" -eq 0 ]; then
    exit ${exitCode};
  fi

  return 0;
} #; function certRenew::log ( <message>, <level>, <lineNumber>, [exitCode] )



certRenew::init

[ ! "${USE_IPTABLES}" -eq "0" ] || {
  certRenew::log "Removing block of port '${CERTBOT_AUTH_PORT}' (if there is one)" "0" "${LINENO}"
  ${IPTABLES_BINARY} -D INPUT -p tcp --destination-port ${CERTBOT_AUTH_PORT} -j DROP &> /dev/null
};

certRenew::log "Stopping ejabberd .." "10" "${LINENO}"
${EJABBERDCTL_BINARY} "stop" &> /dev/null

[ ! "${SHUTDOWN_WAIT_TIME}" -gt 0 ] || {
  certRenew::log "Waiting '${SHUTDOWN_WAIT_TIME}' secs to make sure ejabberd is stopped." "0" "${LINENO}";
  sleep "${SHUTDOWN_WAIT_TIME}";
};

certRenew::log "Renewing certificate for domain '${CERTBOT_DOMAIN}' using command:" "10" "${LINENO}"
certRenew::log "'${CERTBOT_DIRECTORY}/${CERTBOT_BINARY} ${CERTBOT_RENEW_COMMAND}'" "10" "${LINENO}"
${CERTBOT_DIRECTORY}/${CERTBOT_BINARY} ${CERTBOT_RENEW_COMMAND} &> /dev/null

[ ! "${USE_IPTABLES}" -eq "0" ] || {
  certRenew::log "Blocking port '${CERTBOT_AUTH_PORT}' again." "0" "${LINENO}"
  ${IPTABLES_BINARY} -A INPUT -p tcp --destination-port ${CERTBOT_AUTH_PORT} -j DROP &> /dev/null
};

certRenew::log "Preparing certificate for ejabberd" "0" "${LINENO}"
cat "${CERTBOT_WORK_DIRECTORY}/${CERTBOT_DOMAIN}/privkey.pem" "${CERTBOT_WORK_DIRECTORY}/${CERTBOT_DOMAIN}/fullchain.pem" > "${EJABBERD_CERTIFICATE}"
chown "${EJABBERD_USER}":"${EJABBERD_GROUP}" "${EJABBERD_CERTIFICATE}"

certRenew::log "Restarting ejabberd" "10" "${LINENO}"
"${EJABBERDCTL_BINARY}" "start" &> /dev/null

certRenew::log "Done .. " "10" "${LINENO}"

exit 0;
EOF
