#!/bin/bash

CSV=$1

FAST5=$2

THREADS=$3

GPU_MEMORY=$4

LIBRARY_PATH=$VGAP/LIBRARIES

LIBRARY_NAME=$(basename "$CSV" | awk -F. '{print $1}')

PRIMER_SCHEME=$(cat "$CSV" | awk -F, '{print $3}' | uniq)

REFSEQ=$(cat "$CSV" | awk -F, '{print $3}' | awk -F/ '{print $1}' | uniq)

MIN=$(paste <(awk -F"\t" '$4~/RIGHT|R|REVERSE|REV|RV|R/ {print $2}' $VGAP/PRIMER_SCHEMES/"$PRIMER_SCHEME"/"$REFSEQ".scheme.bed) \
<(awk -F"\t" '$4~/LEFT|L|FORWARD|FWD|FW|F/ {print $3}' $VGAP/PRIMER_SCHEMES/"$PRIMER_SCHEME"/"$REFSEQ".scheme.bed) | \
awk -F"\t" '{print $1-$2}' | awk '{if ($0>0) print $0}' | sort -n | sed -n '1p')

MAX=$(paste <(awk -F"\t" '$4~/RIGHT|R|REVERSE|REV|RV|R/ {print $2}' $VGAP/PRIMER_SCHEMES/"$PRIMER_SCHEME"/"$REFSEQ".scheme.bed) \
<(awk -F"\t" '$4~/LEFT|L|FORWARD|FWD|FW|F/ {print $3}' $VGAP/PRIMER_SCHEMES/"$PRIMER_SCHEME"/"$REFSEQ".scheme.bed) | \
awk -F"\t" '{print $1-$2}' | awk '{if ($0>0) print $0+200}' | sort -nr | sed -n '1p')

mkdir $LIBRARY_PATH/$LIBRARY_NAME $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS $LIBRARY_PATH/$LIBRARY_NAME/CONSENSUS -v

guppy_basecaller -r -x auto --verbose_logs --disable_pings \
-c dna_r9.4.1_450bps_hac.cfg -i "$FAST5" -s $LIBRARY_PATH/$LIBRARY_NAME/BASECALL \
--gpu_runners_per_device $GPU_MEMORY --chunks_per_runner 800 --chunk_size 2000 \
--num_callers $THREADS

guppy_barcoder -r --require_barcodes_both_ends --trim_barcodes -t "$THREADS" -x auto \
-i $LIBRARY_PATH/$LIBRARY_NAME/BASECALL -s $LIBRARY_PATH/$LIBRARY_NAME/DEMUX

source activate ont_qc

pycoQC -q -f $LIBRARY_PATH/$LIBRARY_NAME/BASECALL/sequencing_summary.txt \
-b $LIBRARY_PATH/$LIBRARY_NAME/DEMUX/barcoding_summary.txt \
-o $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME"_QC.html --report_title "$LIBRARY_NAME"

source activate ont_assembly

for i in $(find $LIBRARY_PATH/$LIBRARY_NAME/DEMUX -type d -name "barcode*" | sort); do \
artic guppyplex --min-length "$MIN" --max-length "$MAX" --directory "$i" \
--output $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/BC"$(basename $i | awk -Fe '{print $2}')"_"$LIBRARY_NAME".fastq; done

echo "SampleId#NumberReadsMapped#AverageDepth#Coverage10x#Coverage100x#Coverage1000x#ReferenceCovered" | \
tr '#' '\t' > $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME".stats.txt

samtools faidx $VGAP/PRIMER_SCHEMES/"$PRIMER_SCHEME"/"$REFSEQ".reference.fasta

cd $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS

for i in $(cat "$CSV"); do
    SAMPLE=$(echo "$i" | awk -F, '{print $1}' | sed '/^$/d')
    BARCODE=$(echo "$i"| awk -F, '{print $2}' | sed '/^$/d')
    BARCODENB=$(echo "$BARCODE" | sed -e 's/BC//g')
    if [ $(echo "$BARCODE" | awk '{if ($0 ~ /-/) {print "yes"} else {print "no"}}') == "yes" ]; then for i in $(echo "$BARCODE" | tr '-' '\n'); do cat $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$i"_"$LIBRARY_NAME".fastq; done > $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$BARCODE"_"$LIBRARY_NAME".fastq ; fi
    artic minion --threads "$THREADS" --medaka --medaka-model r941_min_high_g360 --normalise 1000 --read-file $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$BARCODE"_"$LIBRARY_NAME".fastq --scheme-directory $VGAP/PRIMER_SCHEMES "$PRIMER_SCHEME" "$SAMPLE"

done

echo -n "$SAMPLE""#" | tr '#' '\t' >> $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME".stats.txt
samtools view -F 0x904 -c "$SAMPLE".primertrimmed.rg.sorted.bam | awk '{printf $1"#"}' | tr '#' '\t' >> $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME".stats.txt
samtools depth "$SAMPLE".primertrimmed.rg.sorted.bam | awk '{sum+=$3} END {print sum/NR}' | awk '{printf $1"#"}' | tr '#' '\t' >> ' >> $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME".stats.txt
samtools depth "$SAMPLE".primertrimmed.rg.sorted.bam 20 | awk '{if ($3 > '"$2"') {print $0}}' | wc -l | sed -e 's/^ *//g' | awk '{printf $1"@"}' | tr '@' '\t' >> $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME".stats.txt
100
1000
REF_LENGTH=$(fastalength $VGAP/PRIMER_SCHEMES/"$PRIMER_SCHEME"/"$REFSEQ".reference.fasta | awk '{print $1}')
fastalength "$SAMPLE".consensus.fasta | awk '{print $2, $1/'"$REF_LENGTH"'*100}' | awk '{print $2}' >> $LIBRARY_PATH/$LIBRARY_NAME/ANALYSIS/"$LIBRARY_NAME".stats.txt

#cat *.consensus.fasta > "$library".consensus.fasta

#mv "$library".consensus.fasta ../CONSENSUS -v

#mv "$library".stats.txt ../CONSENSUS -v

#rm -rf $VGAP/LIBRARIES/$(basename $RAWPATH)/ANALYSIS/*.reference.fasta*

#rm -rf $VGAP/LIBRARIES/$(basename $RAWPATH)/ANALYSIS/*.score.bed

#tar -czf $HOME/VirWGS/LIBRARIES/$(basename $RAWPATH).tar.gz -P $HOME/VirWGS/LIBRARIES/$(basename $RAWPATH)*
