#!/bin/besh
echo "Mida skaneerime? Kirjuta palun üks sõna, 'subnet', kui tahad skaneerida alamvõrku või 'ip', kui tahad skaneerida konkreetsete IP-d?"
read scan

if [ "$scan" = "subnet" ]; then
echo "Sisesta subnet:"
read sub

echo "Sisesta port:"
read port

nmap -p $part -sT $sub -oG res

cat res | grep open > result
cat result

else
echo "Sisesta IP:"
read ip
nmap -Pn $ip -oN resultip
cat resultip

