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
## @global{HOMEDIR,-,the location where getcert.sh is installed}
## @global{PROGNAME,-,the name of the script}
## @global{USESTAGING,-,1 if Let's Encrypt's staging directory should be used\, 0 otherwise}
## @global{VERBOSE,-,be more verbose}
## @global{VERSION,-,version}
## @globalend

PROGNAME=${0##*/}
VERBOSE=0
USESTAGING=0
HOMEDIR='/home/acme'
VERSION="2.0"

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

	# where to put the challenge
	export ACMEDIR=/var/www/acme/.well-known/acme-challenge/

	# contact email
	export EMAIL="mailto:certs@edgar-matzinger.nl"

	# do some basic configuration checks
	[[ ${doConfigVerify} -eq 1 ]] && {
		verifyConfig "init" ||
	       		usage 30 "configuration verification was unsuccessful, run ${PROGNAME} -C|--config for more information"
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
			[[ ${MYID} -ne 0 ]] && echo -e "or: ${PROGNAME} [-D <tld>] [-H <home>] [-S] [-v] -L|-V|-a|-c|-d|-g|-i|-k|-l|-s]"
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
				fi
					echo -e "\t-H,--home <home>\t\t- home to use, default: ${HOMEDIR}"
				if [[ ${MYID} -ne 0 ]]; then
					echo -e "\t-L,--list-csr\t\t\t- list certificate signing request"
					echo -e "\t-S,--staging\t\t\t- use Let's Encrypt staging directory"
					echo -e "\t-V,--verify-csr\t\t\t- verify the certificate signing request"
					echo -e "\t-a,--auto-generate\t\t- automagically create a new CSR and request new certificate"
					echo -e "\t-c,--create-csr\t\t\t- create new certificate signing request"
					echo -e "\t-d,--list-domains\t\t- list domains"
					echo -e "\t-g,--get-certificates\t\t- get new certificates"
				fi
				echo -e "\t-h,--help\t\t\t- show this information"
				echo -e "\t-i,--install-certificates\t- install (new) certificates"
				if [[ ${MYID} -ne 0 ]]; then
					#
					# non-root user...
					echo -e "\t-k,--create-key\t\t\t- create a domain key"
					echo -e "\t-l,--list-certificates\t\t- list current certificates (default)"
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
while getopts ":CD:H:LSVacdghiklsuv-:" optchar; do
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
				install-cert*)	ACTION=installCertificates ;;
				list-csr)	ACTION=listCSR ;;
				list-domains)	ACTION=listDomains ;;
				list-cert*)	ACTION=listCertificates ;;
				list-sans)	ACTION=listSANS ;;
				staging)	USESTAGING=1 ;;
				usage)		usage 1 "" ;;
				verbose)	(( VERBOSE++ )) ;;
				verify-csr)	ACTION=verifyCSR ;;
				version)	usage 0 "version: ${VERSION}" ;;
				*)		usage 1 "unknown option --${OPTARG}" ;;
			esac;;
		C)	ACTION=verifyConfig ;;
		D)	export SINGLEDOMAIN="${OPTARG}" ;;
		H)	HOMEDIR="${OPTARG}"

			#
			# reinitialise settings and get default domain
			init 0 "${HOMEDIR}"
			getDefaultDomainIfExists
			;;
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
