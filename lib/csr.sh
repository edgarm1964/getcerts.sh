#! /bin/bash

###
## @file	csr.sh
## @brief	function related to CSRs
##
## @version	2.0
## @changelog	converted from certbot to acme-tiny
##

###
## @fn createKey()
##
## @brief create a private key
##
## @globalstart
## @global{DOMAIN,in,the domain to get certificates for}
## @global{KEYDIR,in,location where the keys are stored}
## @globalend
##
## @retval none
#
function createKey
{
	log "creating key"

	openssl genrsa -out ${KEYDIR}/${DOMAIN}.key 4096 || usage 15 "key creation failed, exiting..."
}

###
## @fn createCSR()
##
## @brief create a new CSR
##
## @globalstart
## @global{CERTDIR,in,location where the certificates are stored}
## @global{CONFIGDIR,in,location where the configuration files are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @global{KEYDIR,in,location where the keys are stored}
## @globalend
##
## @retval none
#
function createCSR
{
	local san=''
	local s=''

	log "creating CSR"

	for s in ${DOMAIN} $(listSANS); do
		if [[ -n "${san}" ]]; then
			san="${san}, DNS:${s}"
		else
			san="DNS:${s}"
		fi
	done
	[[ -z "${san}" ]] && usage 13 "no subject alternative names defined, exiting"

	export SAN="${san}"

	log "createCSR: SAN: ${SAN}"

	[[ ! -f ${KEYDIR}/${DOMAIN}.key ]] && createKey

	CN=${DOMAIN} openssl req -new \
		-out ${CERTDIR}/${DOMAIN}.csr \
		-key ${KEYDIR}/${DOMAIN}.key \
		-config ${CONFIGDIR}/openssl.cnf \
		-batch
}

###
## @fn listCSR()
##
## @brief list CSRs and give additional information.
##
## @globalstart
## @global{CERTDIR,in,location where the certificates are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
function listCSR
{
	log "listing CSR" 2

	[[ ! -f ${CERTDIR}/${DOMAIN}.csr ]] && usage 16 "${CERTDIR}/${DOMAIN}.csr doesn't exist, exiting..."

	echo "Information on ${DOMAIN}.csr:"
	{
		openssl req -noout -subject -in ${CERTDIR}/${DOMAIN}.csr ||
			usage 17 "${CERTDIR}/${DOMAIN}.csr couldn't be listed, exiting..."
	} | sed -ne '/^[sS]ubject/{ s/^[sS]ubject=/- Subject: /; s@/O=@O=@; s@/@, @g; p; }'

	if [[ ${VERBOSE} -ne 0 ]]; then
		{
			openssl req -noout -text -in ${CERTDIR}/${DOMAIN}.csr ||
				usage 17 "${CERTDIR}/${DOMAIN}.csr couldn't be listed, exiting..."
		} | sed -ne '/Subject Alternative Name:/{
			s/^.*$/Defined Subject Alternative Names:/p; n;
			s/[[:space:]][[:space:]]*DNS:\([^,]*\)[,]*/- \1\n/g;
			s/\n$//p; }'
	fi
}

###
## @fn verifyCSR()
##
## @brief verify a generated CSR
##
## @globalstart
## @global{CERTDIR,in,location where the certificates are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
function verifyCSR
{
	local text='-subject'

	[[ ! -f ${CERTDIR}/${DOMAIN}.csr ]] && usage 14 "${CERTDIR}/${DOMAIN}.csr doesn't exist, exiting..."

	[[ ${VERBOSE} -gt 0 ]] && text='-text'

	{
		openssl req -in ${CERTDIR}/${DOMAIN}.csr -verify -noout ${text} ||
				usage 18 "${CERTDIR}/${DOMAIN}.csr couldn't be verified, exiting..."
	} | sed -e '/^[sS]ubject/{ s/^[sS]ubject=/Subject: /; s@/O=@O=@; s@/@, @g; }'
}

[[ -z "${ACMEDIR}" ]] && {
	echo "csr.sh can't be used standalone, exiting..." 1>&2
	exit 1
}
