#!/bin/bash

#WG_COLOR_MODE=always
#sudo wg show | while read LINE; do
#	sudo find /etc/wireguard/keys -name "*hostname" | while read HOSTFILE; do
#		; to-do
#	done
#done

echo "IP Address        Hostname        Public Key"
echo "------------------------------------------------------------------------------"
printf " 10  48   0   1   %-15s " $HOSTNAME
sudo cat /etc/wireguard/publickey
sudo find /etc/wireguard/keys -name "*hostname" | sort -V | while read HOSTFILE; do
	ADDRESS=$(echo $HOSTFILE | tr '/' ' ' | awk '{print $4,$5,$6,$7}' | tr ' ' '.')
	A=$(echo $ADDRESS | tr '.' ' ' | awk '{print $1}')
	B=$(echo $ADDRESS | tr '.' ' ' | awk '{print $2}')
	C=$(echo $ADDRESS | tr '.' ' ' | awk '{print $3}')
	D=$(echo $ADDRESS | tr '.' ' ' | awk '{print $4}')
	CLIENT_HOSTNAME=$(sudo cat $HOSTFILE)
	CLIENT_PUBLICKEY=$(sudo cat $(echo $HOSTFILE | sed 's/hostname/publickey/'))

	#echo "ADDRESS: $ADDRESS"
	#echo "HOSTNAME: $CLIENT_HOSTNAME"
	#echo

	#printf "%3d %3d %3d %3d\t" $A $B $C $D
	#echo $CLIENT_HOSTNAME
	#echo

	#echo -e "$ADDRESS\t$CLIENT_HOSTNAME"
	#echo

#	printf "%15s   %s\n" $ADDRESS $CLIENT_HOSTNAME
	printf "%3d %3d %3d %3d   %-15s %s\n" $A $B $C $D $CLIENT_HOSTNAME $CLIENT_PUBLICKEY
done
