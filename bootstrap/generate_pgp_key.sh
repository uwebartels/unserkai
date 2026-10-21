#!/usr/bin/env bash
set -e

# configuration
email="terraform@unserkai.de"
keytype=RSA
keylength=2048
name=terraform
comment="technical user for terraform"

# code

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
  echo "** Trapped CTRL-C"
  rm -rf $GNUPGHOME
}

die(){
  local message=$1
  echo $message
  exit 1
}
binaries="gpg2 base64"
for binary in $binaries;do
  which $binary || die "please install $binary"
done

# create temporary directory
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME

cat >keydetails <<EOF
%echo Generating a OpenPGP key
Key-Type: $keytype
Key-Length: $keylength
Subkey-Type: $keytype
Subkey-Length: $keylength
Name-Real: $name
Name-Comment: $comment
Name-Email: $email
Expire-Date: 0
%no-ask-passphrase
%no-protection
#%pubring $name.pub
#%secring $name.sec
%commit
%echo done
EOF

gpg2 --verbose --batch --gen-key keydetails

# Set trust to 5 for the key so we can encrypt without prompt.
echo -e "5\ny\n" |  gpg2 --command-fd 0 --expert --edit-key $email trust;

# Test that the key was created and the permission the trust was set.
gpg2 --list-keys

# Test the key can encrypt and decrypt.
gpg2 -e -a -r $email keydetails

# Delete the options and decrypt the original to stdout.
rm keydetails
gpg2 -d keydetails.asc
rm keydetails.asc


set +x
## all successful so far
echo
echo
echo "Please tar $GNUPGHOME and copy to keepass."
echo "E.g.: tar czvf terraform.gnupg.tgz -C $GNUPGHOME ."
echo "Please use the string below as pgp_pkey in ./terraform.tfvars. This is the base64 encoded pgp public key."
gpg2 --export $email|base64
echo "Please remove temporary directory used for gpg2: $GNUPGHOME"
echo "for decrypting extract tar file and set variable GNUPGHOME to the tar target directory."
echo "E.g.: mkdir ~/src/local/terraform/.gnupg && tar xzf terraform.gnupg.tgz -C ~/src/local/terraform/.gnupg && export GNUPGHOME=~/src/local/terraform/.gnupg"
echo "Then use gpg2 -d for decryption"
