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

	log "getting certificates"

	[[ ${USESTAGING} -ne 0 ]] && staging='--staging'
	[[ ${VERBOSE} -ne 0 ]] && quiet=''

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
				usage 27 "couldn't create ${DOMAIN} certificate, exiting"
		elif openssl x509 -noout -text -in ${certfile} | grep -qi 'lets'; then
			mv ${certfile} ${CERTDIR}/lets-encrypt-x1-cross-signed-$(printf "%04d" ${n}).crt ||
				usage 28 "could create Let's Encrypt cross signed certificate, exiting..."
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

	[[ ! -f ${CERTDIR}/${DOMAIN}.crt ]] && usage 19 "${CERTDIR}/${DOMAIN}.crt doesn't exist, exiting..."

	echo "Information on ${DOMAIN}.crt:"
	{
		openssl x509 -noout -issuer -subject -dates -in ${CERTDIR}/${DOMAIN}.crt ||
			usage 17 "${CERTDIR}/${DOMAIN}.crt couldn't be listed, exiting..."
	} | sed -ne '/^[sS]ubject/{ s@^[sS]ubject=[[:space:]]*/@- Subject: @; s@/O=@O=@; s@/@, @g; p; }' \
		-e '/notBefore/{ s/notBefore=/- Valid from: /p; }' \
		-e '/notAfter/{ s/notAfter=/-         to: /p;}' \
		-e '/[Ii]ssuer/{ s@^.*CN=Fake.*$@- Purpose: unusable test/staging certificate@p;
				 s@^.*CN=\(.*\)$@- Purpose: valid certificate from \1@p; }'
		# -e '/CN=Fake/{ s@^.*$@- Usability: unusable test/staging certificate@p; }' \

	if [[ ${VERBOSE} -ne 0 ]]; then
		{
			openssl x509 -noout -text -in ${CERTDIR}/${DOMAIN}.crt ||
				usage 20 "${CERTDIR}/${DOMAIN}.crt couldn't be listed, exiting..."
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

	[[ ! -f ${CERTDIR}/${DOMAIN}.crt ]] && usage 21 "certificate ${DOMAIN}.crt doesn't exit, exiting..."

	log "saving current ${DOMAIN} certificate with the date code: ${TS}"
	mv ${SSLCERTDIR}/${DOMAIN}.crt ${SSLCERTDIR}/${DOMAIN}.crt-${TS} ||
	       	usage 22 "couldn't save current ${DOMAIN} certificate, exiting..."

	#
	# and yes, 'ln -f --backup --suffix="-${TS}"' could have been used...
	# but for isn't used for maintainablilty
	log "removing Subject Alternate Name certificates"
	for certfile in $(listSANS); do
		rm ${SSLCERTDIR}/${certfile}.crt ||
			usage 23 "couldn't remove current Subject Alternative Name certificate ${certfile}.crt, exiting..."
	done

	log "installing ${DOMAIN} certificate"
	cp ${CERTDIR}/${DOMAIN}.crt ${SSLCERTDIR}/${DOMAIN}.crt ||
	       	usage 24 "couldn't create ${DOMAIN} certificate, exiting..."

	log "creating Subject Alternate Name certificates"
	for certfile in $(listSANS); do
		ln ${SSLCERTDIR}/${DOMAIN}.crt ${SSLCERTDIR}/${certfile}.crt ||
			usage 25 "couldn't create Subject Alternative Name certificate ${certfile}.crt, exiting..."
	done

	log "restarting httpd"
	systemctl restart httpd || usage 26 "couldn't restart httpd, exiting..."
}

[[ -z "${ACMEDIR}" ]] && {
	echo "certificate.sh can't be used standalone, exiting" 1>&2
	exit 1
}
