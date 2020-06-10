#! /bin/bash

###
## @file	getcerts.sh
## @brief	get certificates from Let's Encrypt using acme-tiny
##
## This script is an all-in-one to generate private keys, CSRs
## and request certificates from Let's Encrypt.
##
## @version	2.0
## @changelog	converted from certbot to acme-tiny
##
## @globalstart
## @global{FORCE,-,force the creation of a new certificate if unequal to 0}
## @global{HOMEDIR,-,the location where getcert.sh is installed}
## @global(MINDAYSLEFT,-,a new certificate is requested if current certificate has less than this number of days validity left}
## @global{PROGNAME,-,the name of the script}
## @global{USESTAGING,-,1 if Let's Encrypt's staging directory should be used\, 0 otherwise}
## @global{VERBOSE,-,be more verbose}
## @global{VERSION,-,version}
## @globalend
##
#

PROGNAME=${0##*/}
VERBOSE=0
USESTAGING=0
HOMEDIR='/home/acme'
VERSION="2.0"
MINDAYSLEFT=30
FORCE=0

##
## @fn init(number doConfigVerify, string acmehome)
##
## @brief Initialise the necessary global variables.
##
## @param[in] doConfigVerify ${1} if not set to 0, perform a configuration verification
## @param[in] acmehome ${2} the installation directory to use
##
## @globalstart
## @global{ACMEDIR,out,ACME challenge directory}
## @global{ACMEKEY,out,location where the Let's Encrypt key file is stored}
## @global{BINDIR,out,location where this script is stored}
## @global{CERTDIR,out,location where the certificates are stored}
## @global{CONFIGDIR,out,location where the configuration files are stored}
## @global{EMAIL,out,the contact address}
## @global{KEYDIR,out,location where the keys are stored}
## @global{LIBDIR,out,location where additional sources are stored}
## @global{LOGDIR,out,location of log files}
## @global{MYID,out,the UID of the user running this script}
## @global{PATH,out,the $PATH variable}
## @global{SSLCERTDIR,out,systemwide location of certificates}
## @global{SSLKEYDIR,out,systemwide location of SSL keys}
## @globalend
##
## @retval none
#
function init
{
	local doConfigVerify=${1}
	local ACMEHOME="${2:-/home/acme}"

	# limit $PATH to get some basic security
	export PATH=/usr/bin:/bin

	# set up some basic settings
	export MYID=$(id -u)
	export BINDIR=${ACMEHOME}/bin
	export LIBDIR=${ACMEHOME}/lib
	export CERTDIR=${ACMEHOME}/certs
	export KEYDIR=${ACMEHOME}/keys
	export CONFIGDIR=${ACMEHOME}/etc
	export ACMEKEY=${ACMEHOME}/keys/letsencrypt-account.key
	export LOGDIR=${ACMEHOME}/log
	export SSLCERTDIR=/etc/pki/tls/certs
	export SSLKEYDIR=/etc/pki/tls/private

	# where to put the challenge
	export ACMEDIR=/var/www/acme/.well-known/acme-challenge/

	# contact email
	export EMAIL="mailto:certs@edgar-matzinger.nl"

	# do some basic configuration checks
	[[ ${doConfigVerify} -eq 1 ]] && {
		verifyConfig "init" ||
	       		usage 3 "configuration verification was unsuccessful, run ${PROGNAME} -C|--config for more information"
	}
}

###
## @fn verifyConfig(string when)
##
## @brief verify getcerts configuration.
##
## @param[in] when ${1} either "init" or unset, specifies from where it has been called
##
## @globalstart
## @global{ACMEDIR,in,ACME challenge directory}
## @global{ACMEKEY,in,location where the Let's Encrypt key file is stored}
## @global{CONFIGDIR,in,location where the configuration files are stored}
## @global{KEYDIR,in,location where the keys are stored}
## @global{LIBDIR,in,location where additional sources are stored}
## @global{PROGNAME,in,the name of the script}
## @globalend
##
## @retval 0 everything OK
## @retval 99 something went wrong
##
#
function verifyConfig
{
	local when="${1}"
	local exitcode=0
	local msg=''
	local domain=''

	[[ ! -d ${ACMEDIR} ]] && {
		msg="- ACME challenge directory ${ACMEDIR} doesn't exist"
		exitcode=99
	}

	[[ ! -f ${ACMEKEY} ]] && {
		[[ -n "${msg}" ]] && msg="${msg}\n"
		msg="${msg}- Let's Encrypt account key ${ACMEKEY} doesn't exist"
		exitcode=99
	}

	[[ ! -f ${CONFIGDIR}/domain.txt ]] && {
		[[ -n "${msg}" ]] && msg="${msg}\n"
		msg="${msg}- domain configuration file ${CONFIGDIR}/domain.txt doesn't exist"
		exitcode=99
	}

	for domain in $(cat ${CONFIGDIR}/domain.txt 2> /dev/null); do
		[[ ! -f ${KEYDIR}/${domain}.key ]] && {
			[[ -n "${msg}" ]] && msg="${msg}\n"
			msg="${msg}- domain key ${KEYDIR}/${domain}.key doesn't exist"
			exitcode=99
		}

		[[ ! -f ${CONFIGDIR}/${domain}-san.txt ]] && {
			[[ -n "${msg}" ]] && msg="${msg}\n"
			msg="${msg}- domain subject altenative name file ${KEYDIR}/${domain}-san.txt doesn't exist"
			exitcode=99
		}
	done

	[[ ! -f ${CONFIGDIR}/openssl.cnf ]] && {
		[[ -n "${msg}" ]] && msg="${msg}\n"
		msg="${msg}- openssl configuration file ${CONFIGDIR}/openssl.cnf doesn't exist"
		exitcode=99
	}

	[[ "${when}" != "init" ]] && {
	       	if [[ ${exitcode} -eq 0 ]]; then
			echo "${PROGNAME}: basic configuration verification is successful"
		else
			echo -e "${PROGNAME}: please address the following configuration issues:\n${msg}" 1>&2
		fi
	}

	return ${exitcode}
}

###
## @fn usage(number exitcode, string msg)
##
## @brief show usage information.
##
## @param[in] exitcode ${1} exit code to exit script with
## @param[in] msg ${2} a message to show
##
## @globalstart
## @global{DOMAIN,in,the default domain}
## @global{HOMEDIR,in,the location where getcert.sh is installed}
## @global{MYID,in,the UID of the user running this script}
## @global{PROGNAME,in,the name of the script}
## @globalend
##
## @retval none
#
function usage
{
	local exitcode=${1}
	local msg="${2}"

	#
	# use a block to catch all output and send that to stderr and yes,
	# a heredocument could also be used, but I don't like them...
	{
		[[ -n "${msg}" ]] && echo -e "${PROGNAME}: ${msg}"

		#
		# if --help or --usage are specified, do this...
		if [[ ${exitcode} -eq 1 || ${exitcode} -eq 2 ]]; then
			#
			# always show usage...
			echo -e "${PROGNAME}: usage: ${PROGNAME} [-h|-u]"
			echo -e "or: ${PROGNAME} [-C]"
			[[ ${MYID} -ne 0 ]] && echo -e "or: ${PROGNAME} [-D <tld>] [-F] [-H <home>] [-I] [-m <days>] [-S] [-v] -L|-V|-a|-c|-d|-f|-g|-i|-k|-l|-s]"
			[[ ${MYID} -eq 0 ]] && echo -e "or: ${PROGNAME} [-H <home>] [-i] [-v]"
			if [[ ${exitcode} -eq 2 ]]; then
				#
				# show option explanation too based upon user...
				echo -e "\noptions:"
				echo -e "\t-C,--config\t\t\t- do some basic configuration verification"
				if [[ ${MYID} -ne 0 ]]; then
					#
					# non-root user...
					echo -e "\t-D,--domain <tld>\t\t- top level domain to use, default: ${DOMAIN}"
					echo -e "\t-F,--force\t\t\t- force the request of a new certificate"
				fi
					echo -e "\t-H,--home <home>\t\t- home to use, default: ${HOMEDIR}"
				if [[ ${MYID} -ne 0 ]]; then
					echo -e "\t-I,--info\t\t\t- show informatiopn about installed certificates"
					echo -e "\t-L,--list-csr\t\t\t- list certificate signing request"
					echo -e "\t-S,--staging\t\t\t- use Let's Encrypt staging directory"
					echo -e "\t-V,--verify-csr\t\t\t- verify the certificate signing request"
					echo -e "\t-a,--auto-generate\t\t- automagically create a new CSR and request new certificate"
					echo -e "\t-c,--create-csr\t\t\t- create new certificate signing request"
					echo -e "\t-d,--list-domains\t\t- list domains"
					echo -e "\t-f,--force\t\t\t- force the request of a new certificate"
					echo -e "\t-g,--get-certificates\t\t- get new certificates"
				fi
				echo -e "\t-h,--help\t\t\t- show this information"
				echo -e "\t-i,--install-certificates\t- install (new) certificates"
				if [[ ${MYID} -ne 0 ]]; then
					#
					# non-root user...
					echo -e "\t-k,--create-key\t\t\t- create a domain key"
					echo -e "\t-l,--list-certificates\t\t- list current certificates (default)"
					echo -e "\t-m,--min-days-left <days>\t- get a new certificate if validity current one has less than <days> left, default: ${MINDAYSLEFT}"
					echo -e "\t-s,--list-sans\t\t\t- list subject alternative names"
				fi
				echo -e "\t-u,--usage\t\t\t- show some brief usage information"
				echo -e "\t-v,--verbose\t\t\t- be more verbose"
				echo -e "\t--version\t\t\t- show version"
				echo -e "\noptions can be specified in any order"
			fi
		fi
	} 1>&2

	#
	# exit with exitcode
	exit ${exitcode}
}

###
## @fn autoCreateAndGetCertificate()
##
## @brief automate the process.
##
## @globalstart
## @global{CERTDIR,in,location where the certificates are stored}
## @global{KEYDIR,in,location where the keys are stored}
## @globalend
##
## @retval none
#
function autoCreateAndGetCertificate
{
	#
	# if needed, create a new key
	[[ ! -f ${KEYDIR}/${DOMAIN}.key ]] && createKey

	#
	# if needed, create a new CSR
	[[ ! -f ${CERTDIR}/${DOMAIN}.csr ]] && createCSR

	#
	# request a new certificate
	getCertificate
}

###
## @fn main()
##
## @brief main.
##
## @globalstart
## @global{DOMAIN,inout,the domain to get certificates for}
## @global{HOMEDIR,in,the location where getcert.sh is installed}
## @global{LIBDIR,in,location where additional sources are stored}
## @globalend

#
# initialise stuff
init 0 "${HOMEDIR}"

#
# include tool scripts
source ${LIBDIR}/misc.sh
source ${LIBDIR}/csr.sh
source ${LIBDIR}/certificate.sh

#
# get a default domain
getDefaultDomainIfExists

#
# set up default action
ACTION=listCertificates

#
# use default domain
SINGLEDOMAIN=''

#
# process arguments
while getopts ":CD:FH:ILSVacdghiklm:suv-:" optchar; do
	case "${optchar}" in
		-)	case "${OPTARG}" in
				auto-g*)	ACTION=autoCreateAndGetCertificate ;;
				config)		ACTION=verifyConfig ;;
				create-csr)	ACTION=createCSR ;;
				create-key)	ACTION=createKey ;;
				domain=*)	export SINGLEDOMAIN=${OPTARG##*=}
						_opt=${OPTARG%%=${SINGLEDOMAIN}}
						[[ -z "${SINGLEDOMAIN}" ]] && usage 1 "option --${_opt} needs an argument"
						;;
				domain)		export SINGLEDOMAIN=${!OPTIND}
						(( OPTIND++ ))
						[[ -z "${SINGLEDOMAIN}" ]] && usage 1 "option --${OPTARG} needs an argument"
						;;
				force)		FORCE=1 ;;
				get-cert*)	ACTION=getCertificate ;;
				help)		usage 2 "" ;;
				home=*)		export HOMEDIR=${OPTARG##*=}
						_opt=${OPTARG%%=${HOMEDIR}}
						[[ -z "${HOMEDIR}" ]] && usage 1 "option --${_opt} needs an argument"

						#
						# reinitialise settings and get default domain
						init 0 "${HOMEDIR}"
						getDefaultDomainIfExists
						;;
				home)		export HOMEDIR=${!OPTIND}
						(( OPTIND++ ))
						[[ -z "${HOMEDIR}" ]] && usage 1 "option --${OPTARG} needs an argument"

						#
						# reinitialise settings and get default domain
						init 0 "${HOMEDIR}"
						getDefaultDomainIfExists
						;;
				info)		ACTION=listInstalledCertificates ;;
				install-cert*)	ACTION=installCertificates ;;
				list-csr)	ACTION=listCSR ;;
				list-domains)	ACTION=listDomains ;;
				list-cert*)	ACTION=listCertificates ;;
				list-sans)	ACTION=listSANS ;;
				min-days-left=*)
						MINDAYSLEFT=${OPTARG##*=}
						_opt=${OPTARG%%=${MINDAYSLEFT}}
						[[ -z "${MINDAYSLEFT}" ]] && usage 1 "option --${_opt} needs an argument"
						;;
				min-days-left)	MINDAYSLEFT=${!OPTIND}
						(( OPTIND++ ))
						[[ -z "${MINDAYSLEFT}" ]] && usage 1 "option --${OPTARG} needs an argument"
						;;
				staging)	USESTAGING=1 ;;
				usage)		usage 1 "" ;;
				verbose)	(( VERBOSE++ )) ;;
				verify-csr)	ACTION=verifyCSR ;;
				version)	usage 0 "version: ${VERSION}" ;;
				*)		usage 1 "unknown option --${OPTARG}" ;;
			esac;;
		C)	ACTION=verifyConfig ;;
		D)	export SINGLEDOMAIN="${OPTARG}" ;;
		F)	FORCE=1 ;;
		H)	HOMEDIR="${OPTARG}"

			#
			# reinitialise settings and get default domain
			init 0 "${HOMEDIR}"
			getDefaultDomainIfExists
			;;
		I)	ACTION=listInstalledCertificates ;;
		L)	ACTION=listCSR ;;
		S)	USESTAGING=1 ;;
		V)	ACTION=verifyCSR ;;
		a)	ACTION=autoCreateAndGetCertificate ;;
		c)	ACTION=createCSR ;;
		d)	ACTION=listDomains ;;
		g)	ACTION=getCertificate ;;
		h)	usage 2 "" ;;
		i)	ACTION=installCertificates ;;
		k)	ACTION=createKey ;;
		l)	ACTION=listCertificates ;;
		m)	MINDAYSLEFT=${!OPTIND} ;;
		s)	ACTION=listSANS ;;
		u)	usage 1 "" ;;
		v)	(( VERBOSE++ )) ;;
		:)	usage 1 "option -${OPTARG} needs an argument" ;;
		*)	usage 1 "unknown option: '-${OPTARG}'" ;;
	esac
done

#
# verify configuration
[[ ${ACTION} == "verifyConfig" ]] && {
	verifyConfig
	exit $?
}

#
# reinitialise settings and get default domain
init 1 "${HOMEDIR}"
getDefaultDomain

#
# @brief process, possibly multiple, domain(s)
for domain in ${SINGLEDOMAIN:-$(listDomains)}; do
	export DOMAIN=${domain}

	#
	# root can only install certificate(s)
	[[ ${MYID} -eq 0 ]] && installCertificates

	#
	# any user can create a key, CSR or request a certificate
	[[ ${MYID} -ne 0 ]] && ${ACTION}
done

#
# all done
exit 0

# All defined exitcodes
##
## @exitcodestart
## @exitcode{1,option --${OPTARG} needs an argument (file: bin/getcerts.sh\, line: 325\, 341\, 361\, 396)}
## @exitcode{1,option --${_opt} needs an argument (file: bin/getcerts.sh\, line: 321\, 332\, 357)}
## @exitcode{2,<show brief usage information> (file: bin/getcerts.sh\, line: 329\, 388)}
## @exitcode{3,configuration verification was unsuccessful\, run ${PROGNAME} -C|--config for more information (file: bin/getcerts.sh\, line: 88)}
## @exitcode{10,${CONFIGDIR}/domain.txt doesn't exist (file: lib/misc.sh\, line: 43)}
## @exitcode{11,please create ${CONFIGDIR}/domain.txt (file: lib/misc.sh\, line: 88)}
## @exitcode{12,${CONFIGDIR}/${DOMAIN}-san.txt doesn't exist (file: lib/misc.sh\, line: 110)}
## @exitcode{13,key creation failed (file: lib/csr.sh\, line: 27)}
## @exitcode{14,no subject alternative names defined (file: lib/csr.sh\, line: 58)}
## @exitcode{15,${CERTDIR}/${DOMAIN}.csr doesn't exist (file: lib/csr.sh\, line: 90)}
## @exitcode{16,${CERTDIR}/${DOMAIN}.csr couldn't be listed (file: lib/csr.sh\, line: 95)}
## @exitcode{17,${CERTDIR}/${DOMAIN}.csr couldn't be listed (file: lib/csr.sh\, line: 101)}
## @exitcode{18,${CERTDIR}/${DOMAIN}.csr doesn't exist (file: lib/csr.sh\, line: 126)}
## @exitcode{19,${CERTDIR}/${DOMAIN}.csr couldn't be verified (file: lib/csr.sh\, line: 132)}
## @exitcode{20,current top level domain certificate has ${daysLeft} days validity left\, not requesting a new certificate (file: lib/certificate.sh\, line: 45)}
## @exitcode{21,couldn't create ${DOMAIN} certificate (file: lib/certificate.sh\, line: 88)}
## @exitcode{22,could create Let's Encrypt cross signed certificate (file: lib/certificate.sh\, line: 91)}
## @exitcode{23,${CERTDIR}/${DOMAIN}.crt doesn't exist (file: lib/certificate.sh\, line: 118)}
## @exitcode{24,${CERTDIR}/${DOMAIN}.crt couldn't be listed (file: lib/certificate.sh\, line: 123)}
## @exitcode{25,${CERTDIR}/${DOMAIN}.crt couldn't be listed (file: lib/certificate.sh\, line: 134)}
## @exitcode{26,${certfile} doesn't exist (file: lib/certificate.sh\, line: 168)}
## @exitcode{27,${certfile} couldn't be listed (file: lib/certificate.sh\, line: 173)}
## @exitcode{28,${certfile} couldn't be listed (file: lib/certificate.sh\, line: 185)}
## @exitcode{29,certificate ${DOMAIN}.crt doesn't exit (file: lib/certificate.sh\, line: 213)}
## @exitcode{30,couldn't save current ${DOMAIN} certificate (file: lib/certificate.sh\, line: 217)}
## @exitcode{31,couldn't remove current Subject Alternative Name certificate ${certfile}.crt (file: lib/certificate.sh\, line: 225)}
## @exitcode{32,couldn't create ${DOMAIN} certificate (file: lib/certificate.sh\, line: 230)}
## @exitcode{33,couldn't create Subject Alternative Name certificate ${certfile}.crt (file: lib/certificate.sh\, line: 235)}
## @exitcode{34,couldn't install ${DOMAIN} key (file: lib/certificate.sh\, line: 240)}
## @exitcode{35,couldn't restart httpd (file: lib/certificate.sh\, line: 243)}
## @exitcodeend
#
#
