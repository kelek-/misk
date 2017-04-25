#!/bin/bash

#
# Simple script to cronjob fetching a new version of rclone and installing it
#

declare -r __CURRENT_RCLONE_VERSION_FILE="/root/sources/rclone.zip"
declare -r __NEW_RCLONE_VERSION_FILE="/root/sources/rclone-current-linux-amd64.zip"
declare -r __RCLONE_URL="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
declare -r __RCLONE_LOG="/var/log/rclone_wget.log"
declare -r __RCLONE_WORK_DIRECTORY="/root/sources/rclone"

# fetch rclone
/usr/bin/wget -q -O "${__NEW_RCLONE_VERSION_FILE}" "${__RCLONE_URL}" &> /dev/null || {
  /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to fetch rclone archive via '${__RCLONE_URL}'n" >> "${__RCLONE_LOG}";
  exit 1;
}

# check for new version
[ -n "$(/usr/bin/diff "${__NEW_RCLONE_VERSION_FILE}" "${__CURRENT_RCLONE_VERSION_FILE}")" ] || {
  /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') No new rclone version found.\n" >> "${__RCLONE_LOG}";
  exit 0;
};

# unzip it
/usr/bin/unzip "-qqo" "${__NEW_RCLONE_VERSION_FILE}" "-d" "${__RCLONE_WORK_DIRECTORY}" &> /dev/null || {
  /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to unzip '${__NEW_RCLONE_VERSION_FILE}' to '${__RCLONE_WORK_DIRECTORY}'\n" >> "${__RCLONE_LOG}"
  exit 1;
}

# extract version number
for directory in "${__RCLONE_WORK_DIRECTORY}/"*; do
  if [[ "$(basename "${directory}")" =~ ^rclone-v([[:digit:]]+\.[[:digit:]]+)-linux-amd64$ ]]; then
    /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') New rclone version found: ${BASH_REMATCH[1]}\n" >> "${__RCLONE_LOG}"
    /bin/cp "${directory}/rclone" "/usr/bin" &> /dev/null || {
      /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to copy 'rclone' to '/usr/bin'\n" >> "${__RCLONE_LOG}"
      exit 1;
    }

    /bin/chown "root:root" "/usr/bin/rclone" &> /dev/null || {
      /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to chown '/usr/bin/rclone' to 'root:root'\n" >> "${__RCLONE_LOG}"
      exit 1;
    }

    /bin/chmod "755" "/usr/bin/rclone" &> /dev/null || {
      /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to chmod '/usr/bin/rclone' to '755'\n" >> "${__RCLONE_LOG}"
      exit 1;
    }
    
    /bin/cp "${directory}/rclone.1" "/usr/local/share/man/man1/" &> /dev/null || {
      /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to copy 'rclone.1' to '/usr/local/share/man/man1/'\n" >> "${__RCLONE_LOG}"
      exit 1;
    }

    /usr/bin/mandb &> /dev/null || {
      /usr/bin/printf "$(/bin/date +'%d.%m.%Y %H:%M:%S') Failed to execute 'mandb'\n" >> "${__RCLONE_LOG}"
      exit 1;
    }
    break
  fi
done

