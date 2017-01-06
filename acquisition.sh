#!/bin/bash

### usage:
### ./acquisition.sh <timeout[s]> <comment>

timeout=$1
timestamp=$(date '+%Y-%m-%d_%H:%M:%S')
outdir=${timestamp}_data_$2

tdc_interface=$(cat settings.ini | grep "tdc_interface" | sed 's/tdc_interface=//')

mkdir $outdir
./spi chip0_black_settings_thr100
./spi chip1_black_settings_thr100

cp $0 $outdir/copy_of_acquisition.sh

for i in 30; do

filename=$(printf "%03d.dat" $i)
tsfile=$outdir/${filename}_ts
echo "setting threshold $i"
./threshold $i
echo "recording data to $filename"
echo "acq start : "$(date '+%Y-%m-%d_%H:%M:%S')| tee -a $tsfile
echo "scheduled run time : "$timeout | tee -a $tsfile
timeout -s SIGINT $timeout ./readdata2.pl -d $tdc_interface -v -t 8 -m 0x00 > $outdir/$filename 2>$outdir/${filename}_STDERR
echo "acq stop : "$(date '+%Y-%m-%d_%H:%M:%S') | tee -a $tsfile
done

