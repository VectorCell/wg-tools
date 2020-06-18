#!/bin/bash

if [ $(whoami) != root ]; then
	echo "ERROR: must be run as root!"
	exit 1
fi

KEYDIR=keys
INTERFACE_CLIENT=wg0
INTERFACE_SERVER=wg0
PREFIX=10.48
ADDRESS_CLIENT=$1
HOSTNAME_CLIENT=$2

if [ -z "$ADDRESS_CLIENT" ] || [ -z "$HOSTNAME_CLIENT" ]; then
	echo "ERROR: Usage: add-client.sh ADDRESS_CLIENT HOSTNAME"
	exit 1
fi

cd /etc/wireguard || (echo "ERROR: unable to cd to /etc/wireguard"; exit 1)
umask 077

SERVER_PUBLICKEY=$(cat publickey)
SERVER_PRIVATEKEY=$(cat privatekey)

if [ ! -d $KEYDIR ]; then
	echo "ERROR: unable to locate $KEYDIR"
	echo "Please run this program from a directory containing $KEYDIR"
	exit 1
fi

A=$(echo $ADDRESS_CLIENT | tr '.' ' ' | awk '{print $1}')
B=$(echo $ADDRESS_CLIENT | tr '.' ' ' | awk '{print $2}')
C=$(echo $ADDRESS_CLIENT | tr '.' ' ' | awk '{print $3}')
D=$(echo $ADDRESS_CLIENT | tr '.' ' ' | awk '{print $4}')
PREFIX=$A.$B

mkdir -p $KEYDIR/$A/$B/$C/$D

GENERATED_SCRIPT=$KEYDIR/$A/$B/$C/$D/wg_give_${HOSTNAME_CLIENT}_${ADDRESS_CLIENT}.sh
CLIENT_PUBLICKEYFILE=$KEYDIR/$A/$B/$C/$D/publickey
CLIENT_PRIVATEKEYFILE=$KEYDIR/$A/$B/$C/$D/privatekey
CLIENT_CONF=$KEYDIR/$A/$B/$C/$D/$INTERFACE_CLIENT.conf
CLIENT_HOSTFILE=$KEYDIR/$A/$B/$C/$D/hostname

if [ -e $CLIENT_HOSTFILE ]; then
	echo
	echo "WARNING: IP address $ADDRESS_CLIENT is already allocated to $(cat $CLIENT_HOSTFILE)"
	while true; do read -p "Do you wish to proceed? [y/n]:" yn
		case $yn in
			[Yy]* ) break;;
			[Nn]* ) echo "exiting ..."; exit;;
			* ) echo "Please answer y or n.";;
		esac
	done
fi

echo "Generating keyfiles and configuration for $HOSTNAME_CLIENT"

wg genkey | tee $CLIENT_PRIVATEKEYFILE | wg pubkey > $CLIENT_PUBLICKEYFILE
CLIENT_PUBLICKEY=$(cat $CLIENT_PUBLICKEYFILE)
CLIENT_PRIVATEKEY=$(cat $CLIENT_PRIVATEKEYFILE)

# writing client conf

echo "[Interface]" > $CLIENT_CONF
echo "PrivateKey = $CLIENT_PRIVATEKEY" >> $CLIENT_CONF
echo "Address = $ADDRESS_CLIENT/32" >> $CLIENT_CONF
echo >> $CLIENT_CONF
echo "[Peer]" >> $CLIENT_CONF
echo "PublicKey = $SERVER_PUBLICKEY" >> $CLIENT_CONF
echo "Endpoint = apt.bismith.net:51820" >> $CLIENT_CONF
echo "AllowedIPs = $PREFIX.0.0/16" >> $CLIENT_CONF
echo "PersistentKeepalive = 25" >> $CLIENT_CONF

echo $HOSTNAME_CLIENT > $KEYDIR/$A/$B/$C/$D/hostname

rm -f $GENERATED_SCRIPT
echo "#!/bin/bash" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "if [ \$HOSTNAME == wireguard ]; then" >> $GENERATED_SCRIPT
echo "	echo 'ERROR: do not run this on the wireguard server!'" >> $GENERATED_SCRIPT
echo "	exit 1" >> $GENERATED_SCRIPT
echo "fi" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "if [ \$(whoami) != root ]; then" >> $GENERATED_SCRIPT
echo "	echo 'ERROR: must be run as root!'" >> $GENERATED_SCRIPT
echo "	exit 1" >> $GENERATED_SCRIPT
echo "fi" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "cd /etc/wireguard || (echo ERROR: /etc/wireguard not found; exit 1)" >> $GENERATED_SCRIPT
echo "umask 077" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "wg-quick down $INTERFACE_CLIENT" >> $GENERATED_SCRIPT
echo "systemctl disable wg-quick@$INTERFACE_CLIENT" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "echo $CLIENT_PUBLICKEY > publickey" >> $GENERATED_SCRIPT
echo "echo $CLIENT_PRIVATEKEY > privatekey" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "(" >> $GENERATED_SCRIPT
cat $CLIENT_CONF | base64 | while read LINE; do
	echo "echo $LINE" >> $GENERATED_SCRIPT
done
echo ") | base64 --decode > $INTERFACE_CLIENT.conf" >> $GENERATED_SCRIPT
echo >> $GENERATED_SCRIPT
echo "wg-quick up $INTERFACE_CLIENT" >> $GENERATED_SCRIPT
echo "wg show" >> $GENERATED_SCRIPT
echo "systemctl enable wg-quick@$INTERFACE_CLIENT" >> $GENERATED_SCRIPT

echo "client setup script in $GENERATED_SCRIPT"

# server portion

INTERFACE_HOST=$(ip r | grep ^default | awk '{print $5}')
if [ -z "$INTERFACE_HOST" ]; then
	echo "ERROR: default route not found, unable to determine correct network interface."
	exit 1
fi

SERVER_CONF=$INTERFACE_SERVER.conf
if [ -e $SERVER_CONF ]; then
	cp $SERVER_CONF /etc/wireguard/bak/$INTERFACE_SERVER.conf_bak_$(date +"%F_%R" | tr -d ':')
	# systemctl disable wg-quick@$INTERFACE_SERVER
	# wg-quick down $INTERFACE_SERVER
	# rm $SERVER_CONF
fi

echo "Writing server conf ..."
(
	echo "[Interface]"
	echo "Address = $PREFIX.0.1/16"
	echo "SaveConfig = true"
	echo "PostUp = iptables -A FORWARD -i $INTERFACE_SERVER -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE; ip6tables -A FORWARD -i $INTERFACE_SERVER -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ens3 -j MASQUERADE"
	echo "PostDown = iptables -D FORWARD -i $INTERFACE_SERVER -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE; ip6tables -D FORWARD -i $INTERFACE_SERVER -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ens3 -j MASQUERADE"
	echo "ListenPort = 51820"
	echo "PrivateKey = $SERVER_PRIVATEKEY"
) > $SERVER_CONF

# finds clients
find $KEYDIR -name "*hostname" | while read CLIENT_HOSTFILE; do
	CLIENT_HOSTNAME=$(cat $CLIENT_HOSTFILE)
	A=$(echo $CLIENT_HOSTFILE | tr '/' ' ' | awk '{print $2}')
	B=$(echo $CLIENT_HOSTFILE | tr '/' ' ' | awk '{print $3}')
	C=$(echo $CLIENT_HOSTFILE | tr '/' ' ' | awk '{print $4}')
	D=$(echo $CLIENT_HOSTFILE | tr '/' ' ' | awk '{print $5}')
	ADDRESS=$A.$B.$C.$D
	echo "adding client $CLIENT_HOSTNAME at $A.$B.$C.$D"
	(
		echo
		echo "#$CLIENT_HOSTNAME"
		echo "[Peer]"
		echo "PublicKey = $(cat $KEYDIR/$A/$B/$C/$D/publickey)"
		echo "AllowedIPs = $ADDRESS/32"
	) >> $SERVER_CONF
done

# wg-quick up $INTERFACE_SERVER
# wg show
# systemctl enable wg-quick@$INTERFACE_SERVER

wg syncconf $INTERFACE_SERVER <(wg-quick strip $INTERFACE_SERVER)

cp $GENERATED_SCRIPT /home/bismith/client-setup-${ADDRESS_CLIENT}-${HOSTNAME_CLIENT}.sh \
	&& chown bismith:bismith /home/bismith/client-setup-${ADDRESS_CLIENT}-${HOSTNAME_CLIENT}.sh
