#!/bin/bash

[ "${DEBUG}" == "yes" ] && set -x

function add_config_value() {
  local key=${1}
  local value=${2}
  # local config_file=${3:-/etc/postfix/main.cf}
  [ "${key}" == "" ] && echo "ERROR: No key set !!" && exit 1
  [ "${value}" == "" ] && echo "ERROR: No value set !!" && exit 1

  echo "Setting configuration option ${key} with value: ${value}"
 postconf -e "${key} = ${value}"
}

# Read password from file to avoid unsecure env variables
if [ -n "${SMTP_PASSWORD_FILE}" ]; then [ -f "${SMTP_PASSWORD_FILE}" ] && read SMTP_PASSWORD < ${SMTP_PASSWORD_FILE} || echo "SMTP_PASSWORD_FILE defined, but file not existing, skipping."; fi

[ -z "${SMTP_RELAY}" ] && echo "SMTP_RELAY is not set" && exit 1
[ -z "${SERVER_HOSTNAME}" ] && echo "SERVER_HOSTNAME is not set" && exit 1

SMTP_PORT="${SMTP_PORT:-587}"
DESTINATION_CONCURRENCY_LIMIT="${DESTINATION_CONCURRENCY_LIMIT:-5}"
DESTINATION_RATE_DELAY="${DESTINATION_RATE_DELAY:-1s}"

#Get the domain from the server host name
DOMAIN=`echo ${SERVER_HOSTNAME} | awk 'BEGIN{FS=OFS="."}{print $(NF-1),$NF}'`

add_config_value "myhostname" ${SERVER_HOSTNAME}
add_config_value "mydomain" ${SERVER_HOSTNAME}
add_config_value "mydestination" '$myhostname, localhost'
add_config_value "myorigin" '$mydomain'
add_config_value "relayhost" "$SMTP_RELAY"
#add_config_value "smtp_use_tls" "yes"
add_config_value "smtpd_relay_restrictions" "permit_mynetworks permit_sasl_authenticated defer_unauth_destination"
add_config_value "default_destination_concurrency_limit" "1"
add_config_value "default_destination_rate_delay" "1s"


#Set header tag
if [ ! -z "${SMTP_HEADER_TAG}" ]; then
  postconf -e "header_checks = regexp:/etc/postfix/header_tag"
  echo -e "/^MIME-Version:/i PREPEND RelayTag: $SMTP_HEADER_TAG\n/^Content-Transfer-Encoding:/i PREPEND RelayTag: $SMTP_HEADER_TAG" > /etc/postfix/header_tag
  echo "Setting configuration option SMTP_HEADER_TAG with value: ${SMTP_HEADER_TAG}"
fi

#Check for subnet restrictions
nets='10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16'
if [ ! -z "${SMTP_NETWORKS}" ]; then
        for i in $(sed 's/,/\ /g' <<<$SMTP_NETWORKS); do
                if grep -Eq "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}" <<<$i ; then
                        nets+=", $i"
                else
                        echo "$i is not in proper IPv4 subnet format. Ignoring."
                fi
        done
fi
add_config_value "mynetworks" "${nets}"

#Start services

# If host mounting /var/spool/postfix, we need to delete old pid file before
# starting services
rm -f /var/spool/postfix/pid/master.pid

exec supervisord -c /etc/supervisord.conf
