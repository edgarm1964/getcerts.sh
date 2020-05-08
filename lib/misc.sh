#! /bin/bash

###
## @fn log(text msg,number level)
##
## @brief log information
##
## @param[in] msg ${1} the message to show
## @param[in] level ${2} verbosity must be greater or equal to this level to show the message
##
## @globalstart
## @global{PROGNAME,in,the name of the script}
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
function log
{
	local msg="${1}"
	local level=${2:-1}
	local now=$(/usr/bin/date +'%Y/%m/%d %H:%M:%S.%3N')

	[[ "${VERBOSE}" -ge ${level} && -n "${msg}" ]] && echo -e "${PROGNAME}: ${now} ${msg}" 1>&2
}

###
## @fn getDefaultDomain()
##
## @brief the first domain in domain.txt is considered the default domain.
##
## @globalstart
## @global{CONFIGDIR,in,location where the configuration files are stored}
## @global{DOMAIN,out,the domain to get certificates for}
## @globalend
##
## @retval none
#
function getDefaultDomain
{
	local domain=''

	[[ ! -f ${CONFIGDIR}/domain.txt ]] && usage 10 "${CONFIGDIR}/domain.txt doesn't exist, exiting..."

	domain=$(head -n 1 ${CONFIGDIR}/domain.txt)

	export DOMAIN="${domain}"
}

###
## @fn getDefaultDomainIfExists()
##
## @brief log information
##
## @globalstart
## @global{CONFIGDIR,in,location where the configuration files are stored}
## @global{DOMAIN,out,the domain to get certificates for}
## @globalend
##
## @retval none
#
function getDefaultDomainIfExists
{
	local domain=''

	[[ ! -f ${CONFIGDIR}/domain.txt ]] && return

	domain=$(head -n 1 ${CONFIGDIR}/domain.txt)

	export DOMAIN="${domain}"
}

###
## @fn listDomains()
##
## @brief list all configured domains
##
## @globalstart
## @global{CONFIGDIR,in,location where the configuration files are stored}
## @globalend
##
## @retval none
#
function listDomains
{
	local d=''

	[[ ! -f ${CONFIGDIR}/domain.txt ]] && usage 11 "please create ${CONFIGDIR}/domain.txt, exiting..."
	for d in $(cat ${CONFIGDIR}/domain.txt); do
		echo "${d}"
	done
}

###
## @fn listSANS()
##
## @brief list a domain's subject alternative names.
##
## @globalstart
## @global{CONFIGDIR,in,location where the configuration files are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @globalend
##
## @retval none
#
function listSANS
{
	local d=''

	[[ ! -f ${CONFIGDIR}/${DOMAIN}-san.txt ]] && usage 12 "${CONFIGDIR}/${DOMAIN}-san.txt doesn't exist, exiting..."
	for d in $(cat ${CONFIGDIR}/${DOMAIN}-san.txt); do
		echo "${d}.${DOMAIN}"
	done
}
