#!usr/bin/perl
### Robert Ernst
### bamStats
### Tool for generating html and/or pdf reports with bam statistics

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use POSIX qw(tmpnam);
use Cwd qw(cwd abs_path);
use File::Basename qw( dirname );

### Input options ###

# Declare options
my @bams;

my $wgs = "";
my $coverage_cap = 250;

my $rna = "";
my $ref_flat = "/hpc/cog_bioinf/data/annelies/RNA_Seq/hg19.refFlat.gz";
my $strand = "SECOND_READ_TRANSCRIPTION_STRAND";

my $capture = "";
my $targets = "/hpc/cog_bioinf/GENOMES/Homo_sapiens.GRCh37.GATK.illumina/sorted_Homo_sapiens.GRCh37.74_nopseudo_noRNA_CDS_picard.bed";
my $baits = "/hpc/cog_bioinf/ENRICH/PICARD/sorted_SS_exome_v5_S04380110_Covered_picard.bed";

my $pdf = "";
my $html = "";
my $output_dir = cwd()."/bamStats";

# Picard and Cluster settings
my $queue = "veryshort";
my $queue_threads = 1;
my $queue_mem = 8;
my $picard_path = "/hpc/cog_bioinf/common_scripts/picard-tools-1.119";
my $genome = "/hpc/cog_bioinf/GENOMES/Homo_sapiens.GRCh37.GATK.illumina/Homo_sapiens.GRCh37.GATK.illumina.fasta";

# Parse options
GetOptions ("bam=s" => \@bams,
	    "wgs" => \$wgs,
	    "coverage_cap=i" => \$coverage_cap,
	    "rna" => \$rna,
	    "ref_flat=s" => \$ref_flat,
	    "strand=s" => \$strand,
	    "capture" => \$capture,
	    "targets=s" => \$targets,
	    "baits=s" => \$baits,
	    "pdf" => \$pdf,
	    "html" => \$html,
	    "output_dir=s" => \$output_dir,
	    "queue=s" => \$queue,
	    "queue_threads=i" =>  \$queue_threads,
	    "queue_mem=i" => \$queue_mem,
	    "picard_path=s" => \$picard_path,
	    "genome=s" => \$genome
	    ) or pod2usage(1);

# Check user input
if( !@bams ) { pod2usage(1) };
	### check file existence

### Create output dirs
if(! -e $output_dir){
    mkdir($output_dir) or die "Could not create directory: $output_dir";
}
my $tmpDir = $output_dir."/tmp";
if(! -e $tmpDir){
    mkdir($tmpDir) or die "Could not create directory: $tmpDir";
}

### Run picard tools ###
my @picardJobs;
my @wgsmetrics;
my @hsmetrics;
my $javaMem = $queue_threads * $queue_mem;
my $picard = " java -Xmx".$javaMem."G -jar ".$picard_path;

foreach my $bam (@bams) {
    $bam = abs_path($bam);
    my $bamName = (split("/",$bam))[-1];
    $bamName =~ s/.bam//;
    print "\n$bamName \t $bam \n";
    
    # Multiple metrics
    my $output = $output_dir."/".$bamName."_MultipleMetrics.txt";
    if(! (-e $output."alignment_summary_metrics" && -e $output.".base_distribution_by_cycle_metrics" && -e $output.".insert_size_metrics" && -e $output.".quality_by_cycle_metrics" && -e $output.".quality_distribution_metrics") ) {
	my $command = $picard."/CollectMultipleMetrics.jar R=".$genome." ASSUME_SORTED=TRUE INPUT=".$bam." OUTPUT=".$output." PROGRAM=CollectAlignmentSummaryMetrics PROGRAM=CollectInsertSizeMetrics PROGRAM=QualityScoreDistribution PROGRAM=QualityScoreDistribution";
	my $jobID = bashAndSubmit(
	    command => $command,
	    jobName => "$bamName\_MultipleMetrics",
	    tmpDir => $tmpDir,
	    outputDir => $output_dir,
	    queue => $queue,
	    queueThreads => $queue_threads,
	    );
	push(@picardJobs, $jobID);
    }
    # Library Complexity
    $output = $output_dir."/".$bamName."_LibComplexity.txt";
    if(! -e $output) {
	my $command = $picard."/EstimateLibraryComplexity.jar INPUT=".$bam." OUTPUT=".$output;
	my $jobID = bashAndSubmit(
	    command => $command,
	    jobName => "$bamName\_LibComplexity",
	    tmpDir => $tmpDir,
	    outputDir => $output_dir,
	    queue => $queue,
	    queueThreads => $queue_threads,
	    );
	push(@picardJobs, $jobID);
    }
    # WGS
    if($wgs){
	my $output = $output_dir."/".$bamName."_WGSMetrics.txt";
	push(@wgsmetrics, $output);
	if(! -e $output) {
	    my $command = $picard."/CollectWgsMetrics.jar R=".$genome." INPUT=".$bam." OUTPUT=".$output." MINIMUM_MAPPING_QUALITY=1 COVERAGE_CAP=".$coverage_cap;
	    my $jobID = bashAndSubmit(
		command => $command,
		jobName => "$bamName\_WGSMetrics",
		tmpDir => $tmpDir,
		outputDir => $output_dir,
		queue => $queue,
		queueThreads => $queue_threads,
		);
	    push(@picardJobs, $jobID);
	}
	## Add sambamba stats?
    }

    # RNA
    if($rna){
	my $output = $output_dir."/".$bamName."_RNAMetrics.txt";
	if(! -e $output) {
	    my $command = $picard."/CollectRnaSeqMetrics.jar R=".$genome." REF_FLAT=".$ref_flat." ASSUME_SORTED=TRUE INPUT=".$bam." OUTPUT=".$output." STRAND_SPECIFICITY=".$strand;
	    my $jobID = bashAndSubmit(
		command => $command,
		jobName => "$bamName\_RNAMetrics",
		tmpDir => $tmpDir,
		outputDir => $output_dir,
		queue => $queue,
		queueThreads => $queue_threads,
		);
	    push(@picardJobs, $jobID);
	}
    }

    # CAPTURE
    if($capture){
	my $output = $output_dir."/".$bamName."_HSMetrics.txt";
	push(@hsmetrics, $output);
	if(! -e $output) {
	    my $command = $picard."/CalculateHsMetrics.jar R=".$genome." INPUT=".$bam." OUTPUT=".$output." BAIT_INTERVALS=".$baits." TARGET_INTERVALS=".$targets." METRIC_ACCUMULATION_LEVEL=SAMPLE";
	    my $jobID = bashAndSubmit(
		command => $command,
		jobName => "$bamName\_HSMetrics",
		tmpDir => $tmpDir,
		outputDir => $output_dir,
		queue => $queue,
		queueThreads => $queue_threads,
		);
	    push(@picardJobs, $jobID);
	}
    }
}

### Parse HSMetrics or WGSMetrics
my $root_dir = dirname(abs_path($0));

if( @wgsmetrics ) {}
if( @hsmetrics ) {
    my $command = "perl $root_dir/parsePicardOutput.pl -output_dir ".$output_dir." ";
    foreach my $hsmetric (@hsmetrics) { $command .= "-hsmetrics $hsmetric "}
    my $jobID = bashAndSubmit(
	command => $command,
	jobName => "parse_hsmetrics",
	tmpDir => $tmpDir,
	outputDir => $output_dir,
	queue => $queue,
	queueThreads => $queue_threads,
	holdJobs => join(",",@picardJobs),
	);
    push(@picardJobs, $jobID);
}

### Run Rplots ###


### Functions ###
sub bashAndSubmit {
    my %args = (
	jobName => "bamStats",
	holdJobs => "",
	@_);

    my $jobID = $args{jobName}."_".get_job_id();
    my $bashFile = $args{tmpDir}."/".$jobID.".sh";
    
    open BASH, ">$bashFile" or die "cannot open file $bashFile\n";
    print BASH "#!/bin/bash\n\n";
    print BASH "cd $args{outputDir}\n";
    print BASH "$args{command}\n";
    close BASH;
    
    if( $args{holdJobs} ){
	system "qsub -q $args{queue} -pe threaded $args{queueThreads} -o $args{tmpDir} -e $args{tmpDir} -N $jobID -hold_jid $args{holdJobs} $bashFile";
    } else { 
	system "qsub -q $args{queue} -pe threaded $args{queueThreads} -o $args{tmpDir} -e $args{tmpDir} -N $jobID $bashFile";
    }
    return $jobID;
}

sub get_job_id {
    my $id = tmpnam();
    $id =~ s/\/tmp\/file//;
    return $id;
}

__END__

=head1 SYNOPSIS

$ perl bamStats.pl [options] -bam <bamfile1.bam> -bam <bamfile2.bam>
    
    Required:
     -bam
     
=head1 OPTIONS
    
    Whole genome sequencing statistics
     -wgs
     -coverage_cap <250>
    
    RNA sequencing statistics
    -rna
    -ref_flat </hpc/cog_bioinf/data/annelies/RNA_Seq/hg19.refFlat.gz>
    -strand [NONE, FIRST_READ_TRANSCRIPTION_STRAND, SECOND_READ_TRANSCRIPTION_STRAND]
    
    Capture sequencing statistics (exome)
    -capture
    -targets </hpc/cog_bioinf/GENOMES/Homo_sapiens.GRCh37.GATK.illumina/sorted_Homo_sapiens.GRCh37.74_nopseudo_noRNA_CDS_picard.bed>
    -baits </hpc/cog_bioinf/ENRICH/PICARD/sorted_SS_exome_v5_S04380110_Covered_picard.bed>
    
    Other:
    -html
    -pdf
    -output_dir = <./bamStats>
    -genome </hpc/cog_bioinf/GENOMES/Homo_sapiens.GRCh37.GATK.illumina/Homo_sapiens.GRCh37.GATK.illumina.fasta>
    -queue <veryshort>
    -queue_threads 1;
    -queue_mem 8;
    -picard_path </hpc/cog_bioinf/common_scripts/picard-tools-1.119>

=cut

