#!/bin/bash

#
# Simple script to send notifications on an SSH login
#

#
# Installation:
# Copy this script to /etc/ssh and make it executable.
# Add the following line to /etc/pam.d/sshd
#   session required pam_exec.so seteuid /etc/ssh/login-notify.sh
# 
# For testing purposed you might want to replace required through optional,
# so that you are able to login via SSH if the script fails.
#

# Change these two lines:
sender="From: User <user@sub.domain.tld>"
recepient="user@domain.tld"

if [ "$PAM_TYPE" != "close_session" ]; then
    # get full hostname
    host="$(/bin/hostname -f)"

    # quick check if we can resolve an rdns
    if [[ "${PAM_RHOST}" =~ [[:alpha:]] ]]; then
      ipAddress="$(/usr/bin/host $PAM_RHOST | awk '{ print $4 }')"
      subject="SSH Login: $PAM_USER from $ipAddress on $host"
    else
      subject="SSH Login: $PAM_USER from $PAM_RHOST on $host"
    fi

    # Message to send, e.g. the current environment variables.
    message="$(env)"
    echo "$message" | mailx -s "$subject" "$recepient" -a "$sender"
fi
