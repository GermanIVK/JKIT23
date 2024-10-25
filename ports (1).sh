#!/bin/besh
echo "что сканируем? subnet или ip?"
read scan

if [ "$scan" = "subnet" ]; then
echo "введите subnet:"
read sub

echo "введите port:"
read port

nmap -p $part -sT $sub -oG res

cat res |grep open >result
cat result

else
echo "введите IP:"
read ip
nmap -Pn $ip -oN resultip
cat resultip

