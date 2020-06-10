#! /bin/bash

###
## @file	certificate.sh
## @brief	all functions relating to certificates
##
## @version	2.0
## @changelog	converted from certbot to acme-tiny
##

###
## @fn getCertificate()
##
## @brief retrieve certificates from Let's Encrypt.
##
## @globalstart
## @global{ACMEDIR,in,ACME challenge directory}
## @global{ACMEKEY,in,location where the Let's Encrypt key file is stored}
## @global{BINDIR,in,location where this script is stored}
## @global{CERTDIR,in,location where the certificates are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @global{EMAIL,in,the contact address}
## @global{FORCE,in,force the creation of a new certificate if unequal to 0}
## @global(MINDAYSLEFT,in,a new certificate is requested if current certificate has less than this number of days validity left}
## @global{USESTAGING,in,1 if Let's Encrypt's staging directory should be used\, 0 otherwise}
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
function getCertificate
{
	local staging=''
	local quiet='--quiet'
	local commonName=''
	local n=0
	local days=$(daysLeft)

	log "getting certificates"

	[[ ${USESTAGING} -ne 0 ]] && staging='--staging'
	[[ ${VERBOSE} -ne 0 ]] && quiet=''

	[[ ${FORCE} -eq 0 && ${daysleft} -gt ${MINDAYSLEFT} ]] && {
		usage 20 "current top level domain certificate has ${daysLeft} days validity left, not requesting a new certificate"
	}

	[[ ${FORCE} -ne 0 ]] && {
		log "forcing the request of a new certificate" 0
	}

	python ${BINDIR}/acme-tiny.py --account-key ${ACMEKEY} ${staging} \
		--contact ${EMAIL} ${quiet} \
		--csr ${CERTDIR}/${DOMAIN}.csr \
		--acme-dir ${ACMEDIR} > ${CERTDIR}/signed_chain.crt

	awk 'BEGIN{
		echo = 0;
		n = 1;
		certdir = ENVIRON["CERTDIR"];
	}
	{
		fn = sprintf ("%s/cert-%04d.crt", certdir, n);
		if (match ($0, /-----BEGIN CERTIFICATE-----/))
			echo = 1;
		if (echo)
			printf ("%s\n", $0) >> fn;
		if (match ($0, /-----END CERTIFICATE-----/))
		{
			close (fn);
			n++;
			echo = 0;
		}
	}' ${CERTDIR}/signed_chain.crt

	n=1
	for certfile in ${CERTDIR}/cert-*.crt; do
		log "processing ${certfile}"

		commonName=$(openssl x509 -noout -subject -in ${certfile} |
			sed -ne 's;^.*CN=\(.*\)$;\1;p')

		# @brief A fake cross signed certificate has a commonName
		[[ "${commonName}" =~ "Fake" || "${commonName}" =~ "Let's" ]] && commonName=''

		if [[ -n "${commonName}" ]]; then
			mv ${certfile} ${CERTDIR}/${commonName}.crt ||
				usage 21 "couldn't create ${DOMAIN} certificate, exiting"
		elif openssl x509 -noout -text -in ${certfile} | grep -qi 'lets'; then
			mv ${certfile} ${CERTDIR}/lets-encrypt-x1-cross-signed-$(printf "%04d" ${n}).crt ||
				usage 22 "could create Let's Encrypt cross signed certificate, exiting..."
			(( n++ ))
		fi
	done

	#
	# @brief when successfully split into separate certificates, remove certificate chain
	[[ ${n} -gt 1 ]] && rm ${CERTDIR}/signed_chain.crt
}

###
## @fn listCertificates()
##
## @brief list certificates obtained from Let's Encrypt.
##
## @globalstart
## @global{CERTDIR,in,location where the certificates are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
function listCertificates
{
	log "listing certificate(s)" 2

	[[ ! -f ${CERTDIR}/${DOMAIN}.crt ]] && usage 23 "${CERTDIR}/${DOMAIN}.crt doesn't exist, exiting..."

	echo "Information on ${DOMAIN}.crt:"
	{
		openssl x509 -noout -issuer -subject -dates -in ${CERTDIR}/${DOMAIN}.crt ||
			usage 24 "${CERTDIR}/${DOMAIN}.crt couldn't be listed, exiting..."
	} | sed -ne '/^[sS]ubject/{ s@^[sS]ubject=[[:space:]]*/@- Subject: @; s@/O=@O=@; s@/@, @g; p; }' \
		-e '/notBefore/{ s/notBefore=/- Valid from: /p; }' \
		-e '/notAfter/{ s/notAfter=/-         to: /p;}' \
		-e '/[Ii]ssuer/{ s@^.*CN=Fake.*$@- Purpose: unusable test/staging certificate@p;
				 s@^.*CN=\(.*\)$@- Purpose: valid certificate from \1@p; }'
		# -e '/CN=Fake/{ s@^.*$@- Usability: unusable test/staging certificate@p; }' \

	if [[ ${VERBOSE} -ne 0 ]]; then
		{
			openssl x509 -noout -text -in ${CERTDIR}/${DOMAIN}.crt ||
				usage 25 "${CERTDIR}/${DOMAIN}.crt couldn't be listed, exiting..."
		} | sed -ne '/Subject Alternative Name:/{
			s/^.*$/Defined Subject Alternative Names:/p; n;
			s/[[:space:]][[:space:]]*DNS:\([^,]*\)[,]*/- \1\n/g;
			s/\n$//p; }'
	fi
}

###
## @fn listInstalledCertificates()
##
## @brief list system wide installed certificates.
##
## @globalstart
## @global{DOMAIN,in,the domain to get certificates for}
## @global{SSLCERTDIR,in,systemwide location of certificates}
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
function listInstalledCertificates
{
	local certfile=${SSLCERTDIR}/${DOMAIN}.crt
	local fallback=$(listSANS | head -n 1)
	local nextcertfile=''

	log "listing certificate(s)" 2

	[[ ! -f ${certfile} ]] && {
		nextcertfile=${SSLCERTDIR}/${fallback}.crt
		log "certificate file ${certfile} doesn't exist, trying $nextcertfile}" 2
		certfile=${nextcertfile}
	}
	[[ ! -f ${certfile} ]] && usage 26 "${certfile} doesn't exist, exiting..."

	echo "Information on $(basename ${certfile}):"
	{
		openssl x509 -noout -issuer -subject -dates -in ${certfile} ||
			usage 27 "${certfile} couldn't be listed, exiting..."
	} | sed -ne '/^[sS]ubject/{ s@^[sS]ubject=[[:space:]]*/@- Subject: @; s@/O=@O=@; s@/@, @g; p; }' \
		-e '/notBefore/{ s/notBefore=/- Valid from: /p; }' \
		-e '/notAfter/{ s/notAfter=/-         to: /p;}' \
		-e '/[Ii]ssuer/{ s@^.*CN=Fake.*$@- Purpose: unusable test/staging certificate@p;
				 s@^.*CN=\(.*\)$@- Purpose: valid certificate from \1@p; }'
		# -e '/CN=Fake/{ s@^.*$@- Usability: unusable test/staging certificate@p; }' \
	echo "- days left: $(certificateDaysLeft ${certfile})"

	if [[ ${VERBOSE} -ne 0 ]]; then
		{
			openssl x509 -noout -text -in ${certfile} ||
				usage 28 "${certfile} couldn't be listed, exiting..."
		} | sed -ne '/Subject Alternative Name:/{
			s/^.*$/Defined Subject Alternative Names:/p; n;
			s/[[:space:]][[:space:]]*DNS:\([^,]*\)[,]*/- \1\n/g;
			s/\n$//p; }'
	fi
}

###
## @fn installCertificates()
##
## @brief install certificates
##
## @globalstart
## @global{CERTDIR,in,location where the certificates are stored}
## @global{DOMAIN,in,the domain to get certificates for}
## @global{SSLCERTDIR,in,systemwide location of certificates}
## @globalend
##
## @retval none
#
function installCertificates
{
	local TS="$(date +%Y%m%dT%H%M%S.%3N)"
	local certfile=''

	log "installing certificates"

	[[ ! -f ${CERTDIR}/${DOMAIN}.crt ]] && usage 29 "certificate ${DOMAIN}.crt doesn't exit, exiting..."

	log "saving current ${DOMAIN} certificate with the date code: ${TS}"
	mv ${SSLCERTDIR}/${DOMAIN}.crt ${SSLCERTDIR}/${DOMAIN}.crt-${TS} ||
	       	usage 30 "couldn't save current ${DOMAIN} certificate, exiting..."

	#
	# and yes, 'ln -f --backup --suffix="-${TS}"' could have been used...
	# but for isn't used for maintainablilty
	log "removing Subject Alternate Name certificates"
	for certfile in $(listSANS); do
		rm ${SSLCERTDIR}/${certfile}.crt ||
			usage 31 "couldn't remove current Subject Alternative Name certificate ${certfile}.crt, exiting..."
	done

	log "installing ${DOMAIN} certificate"
	cp ${CERTDIR}/${DOMAIN}.crt ${SSLCERTDIR}/${DOMAIN}.crt ||
	       	usage 32 "couldn't install ${DOMAIN} certificate, exiting..."

	log "creating Subject Alternate Name certificates"
	for certfile in $(listSANS); do
		ln ${SSLCERTDIR}/${DOMAIN}.crt ${SSLCERTDIR}/${certfile}.crt ||
			usage 33 "couldn't install Subject Alternative Name certificate ${certfile}.crt, exiting..."
	done

	log "installing ${DOMAIN} key"
	cp ${KEYDIR}/${DOMAIN}.crt ${SSLKEYDIR}/${DOMAIN}.crt ||
	       	usage 34 "couldn't install ${DOMAIN} key, exiting..."

	log "restarting httpd"
	systemctl restart httpd || usage 35 "couldn't restart httpd, exiting..."
}

###
## @fn daysLeft()
##
## @brief give number of days the installed/current TLD certificate has left
##
## @globalstart
## @global{DOMAIN,in,the domain to get certificates for}
## @global{SSLCERTDIR,in,systemwide location of certificates}
## @globalend
##
## @retval none
#
function daysLeft
{
	local notAfter=0
	local now=$(date +%s)
	local days=0
	local certfile="${SSLCERTDIR}/${DOMAIN}.crt"
	local nextcertfile=''
	local fallback=$(listSANS | head -n 1)

	# do some checks and if needed, do an educated guess
	[[ ! -f ${certfile} ]] && {
		nextcertfile="${SSLCERTDIR}/${fallback}.crt"
		log "certificate file $(basename ${certfile}) doesn't exist, trying i$(basename ${nextcertfile})" 2
		certfile=${nextcertfile}
	}

	if [[ -f ${certfile} ]]; then
		eval $(openssl x509 -dates -noout -in ${certfile} |
			sed -n -e 's/^\(notAfter\)=\(.*\)$/\1=$(date +%s -d "\2")/p')
		days=$(( (${notAfter} - ${now}) / 86400))
		[[ ${days} -lt 0 ]] && days=0
	fi

	echo ${days}
}

###
## @fn certificateDaysLeft(string certfile)
##
## @brief give number of days the given certificate has left
##
## @param[in] certfile ${1} certificate to get information from
##
## @globalstart
## @global{VERBOSE,in,be more verbose}
## @globalend
##
## @retval none
#
#
function certificateDaysLeft
{
	local certfile="${1}"
	local days=0
	local notAfter=0
	local now=$(date +%s)

	if [[ -f ${certfile} ]]; then
		eval $(openssl x509 -dates -noout -in ${certfile} |
			sed -n -e 's/^\(notAfter\)=\(.*\)$/\1=$(date +%s -d "\2")/p')
		days=$(( (${notAfter} - ${now}) / 86400))
		[[ ${days} -lt 0 ]] && days=0
	fi

	echo ${days}
}

[[ -z "${ACMEDIR}" ]] && {
	echo "$(basename ${0}) can't be used standalone, exiting" 1>&2
	exit 1
}
