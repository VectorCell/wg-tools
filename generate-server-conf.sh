#!/bin/bash

if [ $(whoami) != root ]; then
	echo "ERROR: must be run as root!"
	exit 1
fi

KEYDIR=keys
INTERFACE_CLIENT=wg0
INTERFACE_SERVER=wg0
PREFIX=10.48

cd /etc/wireguard || (echo "ERROR: unable to cd to /etc/wireguard"; exit 1)
umask 077

SERVER_PUBLICKEY=$(cat publickey)
SERVER_PRIVATEKEY=$(cat privatekey)

if [ ! -d $KEYDIR ]; then
	echo "ERROR: unable to locate /etc/wireguard/$KEYDIR"
	exit 1
fi

# server portion

INTERFACE_GATEWAY=$(ip r | grep ^default | awk '{print $5}')
if [ -z "$INTERFACE_GATEWAY" ]; then
	echo "ERROR: default route not found, unable to determine correct network interface."
	exit 1
fi

SERVER_CONF=$INTERFACE_SERVER.conf
# SERVER_CONF=test.conf
if [ -e $SERVER_CONF ]; then
	cp $SERVER_CONF /etc/wireguard/bak/$INTERFACE_SERVER.conf_bak_$(date +"%F_%R" | tr -d ':')
	# unneeded:
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

less $SERVER_CONF

wg syncconf $INTERFACE_SERVER <(wg-quick strip $INTERFACE_SERVER)

cp $GENERATED_SCRIPT /home/bismith/client-setup-${ADDRESS_CLIENT}-${HOSTNAME_CLIENT}.sh \
	&& chown bismith:bismith /home/bismith/client-setup-${ADDRESS_CLIENT}-${HOSTNAME_CLIENT}.sh
