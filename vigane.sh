#!/bin/bash 
set -u 
LOGFILE="/tmp/minu_logi.txt" 
FAIL="/tmp/test fail.txt" 
echo "Kontroll algas: $(date)" >> "$LOGFILE" 
if [ -f $FAIL ]; then 
echo "Fail leitud: $FILE" >> "$LOGFILE" 
else 
echo "Faili ei leitud" >> "$LOGFILE" 
fi 
cp "$FAIL" /tmp/backup/ 
echo "Kopeerimine lõpetatud" >> "$LOGFILE"
