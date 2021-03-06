#!/bin/bash

# Create a temporary working directory
TMPDIR=/tmp/backup-$RANDOM$RANDOM
mkdir $TMPDIR

if [ $# -ne 1 ]
then
  echo "Usage: $0 <archive file>"
  exit 1
fi

if [ ! -f "$1" ]
then
  echo "File not found - $1"
  exit 1
fi

# Unpack archive to temporary directory
tar -xf $1 -C $TMPDIR

# Get docker container ID for openldap container
OPENLDAP="$(kubectl get --no-headers=true pods -l app=iamlab-isamopenldap -o custom-columns=:metadata.name)"

# Restore LDAP Data to OpenLDAP
kubectl cp ${TMPDIR}/secauthority.ldif ${OPENLDAP}:/tmp/secauthority.ldif
kubectl exec ${OPENLDAP} -- ldapadd -c -f /tmp/secauthority.ldif -H "ldaps://localhost:636" -D "cn=root,secAuthority=Default" -w "Passw0rd"
kubectl cp ${TMPDIR}/ibmcom.ldif ${OPENLDAP}:/tmp/ibmcom.ldif
kubectl exec ${OPENLDAP} -- ldapadd -c -f /tmp/ibmcom.ldif -H "ldaps://localhost:636" -D "cn=root,secAuthority=Default" -w "Passw0rd"
kubectl exec ${OPENLDAP} -- rm /tmp/secauthority.ldif
kubectl exec ${OPENLDAP} -- rm /tmp/ibmcom.ldif

# Get docker container ID for postgresql container
POSTGRESQL="$(kubectl get --no-headers=true pods -l app=iamlab-isampostgresql -o custom-columns=:metadata.name)"

# Restore DB
kubectl exec ${POSTGRESQL} -i -- /usr/local/bin/psql isam < ${TMPDIR}/isam.db

# Get docker container ID for isamconfig container
ISAMCONFIG="$(kubectl get --no-headers=true pods -l app=iamlab-isamconfig -o custom-columns=:metadata.name)"

# Copy snapshots to the isamconfig container
SNAPSHOTS=`ls ${TMPDIR}/*.snapshot`
for SNAPSHOT in $SNAPSHOTS; do
kubectl cp ${SNAPSHOT} ${ISAMCONFIG}:/var/shared/snapshots
done

rm -rf $TMPDIR

# Restart config container to apply updated files
echo "Performing reload on config container..."
kubectl exec ${ISAMCONFIG} -- isam_cli -c reload all

echo Done.
