# getcerts.sh

The package `getcerts.sh` is an all-in-one solution to create private keys,
generate a signing request (csr) and obtain certificates from Let's Encrypt
for multiple domains. And, of course, subject alternative names are supported.

Furthermore, the script can install (new) certificates and restart the web server.

New certificates can be requested and installed without any downtime. The only
downtime needed, is to activate the (new) certificates.

The package `getcerts.sh` is based upon the excellent work done by Daniel Roesler and Jon Lundi:

[acme-tiny.py](https://github.com/diafygi/acme-tiny)<br/>
[conv.py](https://gist.github.com/JonLundy/f25c99ee0770e19dc595)

An option, `--staging`, to use Let's Encrypt's staging directory has been added
to `acme-tiny.py`.

## Directory structure

The package `getcerts.sh` expects the following directory structure:

```
ACMEHOME
       |-- bin
       |   |-- acme-tiny.py
       |   |-- conv.py
       |   `-- getcerts
       |-- certs
       |   |-- <domain>.crt
       |   |-- <domain>.csr
       |   `-- lets-encrypt-x1-cross-signed-0001.crt
       |-- doxygen
       |   |-- Doxyfile
       |   `-- doxygen-bash.sed
       |-- etc
       |   |-- domain.txt
       |   |-- <domain>-san.txt
       |   `-- openssl.cnf
       |-- keys
       |   |-- <domain>.key
       |   `-- letsencrypt-account.key
       `-- lib
           |-- certificate.sh
           |-- csr.sh
           `-- misc.sh
```

Notes:
1. domain.txt contains all top level domains to create keys,
   signing requests and certificates for.
2. a file named \<domain\>.\* has to be named after the top level
   domain being processed.
3. file \<domain\>-san.txt has to contain all subject alternative
   names, one per line, for the top level domain being processed.
4. all \*.csr, \*.crt and \*.key files are in PEM format.
5. file letsencrypt-account.key contains the account key obtained
   from Let's Encrypt.
6. doxygen contains the necessary information to create HTML
   documentation.

## Installation, configuration and usage

### Create a single purpose user

It is advised to create a single purpose user to install `getcerts.sh` into,
for example `acme`.

```sh
# create user 'acme'
sudo useradd -c 'ACME User' -m -d /home/acme acme

# if needed, set a strong password
sudo passwd acme
```

`ACMEHOME` in this document refers to `/home/acme`.

### Installation

To install `getcerts.sh`, download a release or clone from Github, extract
the contents in a directory and configure `getcerts.sh`.

### Configuration

After installing `getcerts.sh`, the following files, all relative to
`ACMEHOME`, need to be configured:

- etc/domain.txt<br/>
This file contains all the top level domains, each on a separate line,
to get certificates for. Example: example.com.
- etc/\<domain\>-san.txt<br/>
This file contains all the subject alternative names for a single
domain. The \<domain\>-part has to be replaced with the TLD.
Example: example.com-san.txt.
- keys/letsencrypt-account.key<br/>
Let's Encrypt account key.
- /var/www/acme/.well-known/acme-challenge<br/>
Your web server has to be configured to provide a challenge directory for each
and every website for which a certificate will be requested.
- etc/openssl.conf<br/>
In this file, at least the \*\_default items have to be adjusted:<br/>
 - `emailAddress_default        = cert@example.com`
 - `0.organizationName_default  = Example Organisation`
 - `localityName_default        = City`
 - `stateOrProvinceName_default = Province/state`
 - `countryName_default         = XX`<br/><br/>

 Please leave `commonName_default` as is as it references a variable, using
 `${ENV::CN}`, which will be set by `getcerts.sh`.

#### Previous Let's Encrypt account keys

If a previous Let's Encrypt account key is present, after using `certbot`, this
has to be converted into a PEM format. Perform these steps:

```sh
# Copy your private key to your working directory
cp /etc/letsencrypt/accounts/acme-v0[12].api.letsencrypt.org/directory/<id>/private_key.json private_key.json

# convert private key to asn1
python2 bin/conv.py private_key.json > private_key.asn1

# Create a DER encoded private key
openssl asn1parse -noout -out private_key.der -genconf private_key.asn1

# Convert to PEM
openssl rsa -in private_key.der -inform der -out keys/letsencrypt-account.key

# remove temporary information
rm private_key.asn1 private_key.der private_key.json
```

#### Sudo
If a single purpose user, e.g. `acme`, has been created, it needs a sudo entry
to be able to install the new certificates and to restart the web server.
Create a file in `/etc/sudoers.d`. For example `/etc/sudoers/acme`, with the
following (or similar) content:

```
acme    ALL=(ALL)       NOPASSWD: /home/acme/bin/getcerts.sh
```

And yes, this could be a security problem if certificate installation
and web server restart is delegated to a non-sysadmin user or third party!

It's left as an exercise to the reader to provide a more secure solution.

#### Change default values in getcerts.sh

In `getcerts.sh`, the default values in function init() can be adjusted.

```
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
	export CHAINDIR=${ACMEHOME}/certs
	export CONFIGDIR=${ACMEHOME}/etc
	export ACMEKEY=${ACMEHOME}/keys/letsencrypt-account.key
	export LOGDIR=${ACMEHOME}/log

	# where are the 'official' certificates installed?
	export SSLCERTDIR=/etc/pki/tls/certs

	# where to put the challenge
	export ACMEDIR=/var/www/acme/.well-known/acme-challenge/

	# contact email
	export EMAIL="mailto:certs@example.com"

	# do some basic configuration checks
	[[ ${doConfigVerify} -eq 1 ]] && {
		verifyConfig "init" ||
	       		usage 30 "configuration verification was unsuccessful, run ${PROGNAME} -C|--config for more information"
	}
}
```

The variables should be self explanatory.

#### Challenge directory

During the verification phase, `getcerts.sh` places a token in the challenge
directory to verify if it has access to the web servers where certificates
are requested for. In order to be able to this, all virtual servers need to
have an entry to point to the challenge directory.

In a proxying web server, in this case apache on a Red Hat platform, this can
be configured as follows:

```
<VirtualHost *:443>
  ServerName www.example.com
  Alias "/.well-known/" "/var/www/acme/.well-known/"
  <Directory "/var/www/acme/.well-known/">
    Require all granted
  </Directory>

  #
  # rest of SSL configuration goes here...
  #

  # proxy forward
  ProxyRequests Off
  ProxyPreserveHost On
  <proxy *>
    AddDefaultCharSet off
    Order deny,allow
    Allow from all
  </proxy>
  # forward rules
  <Location />
    ProxyPass http://wwwbe.example.com:80/
    ProxyPassReverse http://wwwbe.example.com:80/
  </Location>

  # do not proxy /.well-known/acme-challenge
  <Location /.well-known/acme-challenge>
    ProxyPass "!"
  </Location>
</VirtualHost>
```

### Usage

Running `getcerts.sh --help` as a regular user shows this information:

```
getcerts.sh: usage: getcerts.sh [-h|-u]
or: getcerts.sh [-C]
or: getcerts.sh [-D <tld>] [-H <home>] [-S] [-v] -L|-V|-a|-c|-d|-g|-i|-k|-l|-s]

options:
	-C,--config               - do some basic configuration verification
	-D,--domain <tld>         - top level domain to use, default: example.com
	-H,--home <home>          - home to use, default: /home/acme
	-L,--list-csr             - list certificate signing request
	-S,--staging              - use Let's Encrypt staging directory
	-V,--verify-csr           - verify the certificate signing request
	-a,--auto-generate        - automagically create a new CSR and request new certificate
	-c,--create-csr           - create new certificate signing request
	-d,--list-domains         - list domains
	-g,--get-certificates     - get new certificates
	-h,--help                 - show this information
	-i,--install-certificates - install (new) certificates
	-k,--create-key           - create a domain key
	-l,--list-certificates    - list current certificates (default)
	-s,--list-sans            - list subject alternative names
	-u,--usage                - show some brief usage information
	-v,--verbose              - be more verbose
	--version                 - show version

options can be specified in any order
```

Running `getcerts.sh --help` as 'root' shows this information:

```
getcerts.sh: usage: getcerts.sh [-h|-u]
or: getcerts.sh [-C]
or: getcerts.sh [-H <home>] [-i] [-v]

options:
	-C,--config               - do some basic configuration verification
	-H,--home <home>          - home to use, default: /home/acme
	-h,--help                 - show this information
	-i,--install-certificates - install (new) certificates
	-u,--usage                - show some brief usage information
	-v,--verbose              - be more verbose
	--version                 - show version

options can be specified in any order
```
