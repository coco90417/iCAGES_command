#!/usr/bin/perl
use strict;
use warnings;
use List::Util qw(min max);
use Pod::Usage;
use Getopt::Long;

######################################################################################################################################
######################################################## variable declaration ########################################################
######################################################################################################################################

my ($rawInputFile, $icagesLocation);
my (%biosystem, %neighbors, %activity, %onc, %sup, %icagesGenes);
my ($biosystemRef, $activityRef, $oncRef, $supRef, $icagesGenesRef, $neighborsRef);

######################################################################################################################################
########################################################### main  ####################################################################
######################################################################################################################################

$rawInputFile = $ARGV[0];
$icagesLocation = $ARGV[1];
($biosystemRef, $activityRef, $oncRef, $supRef) = &loadDatabase($icagesLocation);
%biosystem = %{$biosystemRef};
%activity = %{$activityRef};
%onc = %{$oncRef};
%sup = %{$supRef};
$icagesGenesRef = &getiCAGES($rawInputFile);
%icagesGenes = %{$icagesGenesRef};
$neighborsRef = &getNeighbors(\%icagesGenes, \%biosystem);
%neighbors = %{$neighborsRef};
&getDrugs ($rawInputFile, $icagesLocation, \%neighbors, \%onc, \%sup);
&processDrugs($rawInputFile, \%neighbors, \%activity);

######################################################################################################################################
############################################################# subroutines ############################################################
######################################################################################################################################

sub loadDatabase {
    print "NOTICE: start loading Databases\n";
    my (%biosystem, %activity, %onc, %sup);
    my ($icagesLocation, $DBLocation, $biosystemDB, $activityDB, $oncDB, $supDB);
    $icagesLocation = shift;
    $DBLocation = $icagesLocation . "db/";
    $biosystemDB = $DBLocation . "biosystem.score";
    $activityDB = $DBLocation . "drug.score";
    $oncDB = $DBLocation . "oncogene.gene";
    $supDB = $DBLocation . "suppressor.gene";
    open(BIO, "$biosystemDB") or die "ERROR: cannot open $biosystemDB\n";
    open(ACT, "$activityDB") or die "ERROR: cannot open $activityDB\n";
    open(ONC, "$oncDB") or die "ERROR: cannot open $oncDB\n";
    open(SUP, "$supDB") or die "ERROR: cannot open $supDB\n";
    while(<BIO>){
        chomp;
        my @line = split("\t", $_);
        $biosystem{$line[0]}{$line[1]} = $line[2];
    }
    while(<ACT>){
        chomp;
        my @line = split("\t", $_);
        $activity{$line[0]} = $line[1];
    }
    while(<ONC>){
        chomp;
        my @line = split("\t", $_);
        $onc{$line[0]} = 1;

    }
    while(<SUP>){
        chomp;
        my @line = split("\t", $_);
        $sup{$line[0]} = 1;
        
    }
    close SUP;
    close ONC;
    close ACT;
    close BIO;
    return (\%biosystem, \%activity, \%onc, \%sup);
}

sub getiCAGES{
    print "NOTICE: start process gene files from iCAGES layer two\n";
    my ($rawInputFile, $icagesGenes);
    my %icagesGenes;
    $rawInputFile = shift;
    $icagesGenes = $rawInputFile . ".icagesGenes.csv";
    open(GENES, "$icagesGenes") or die "ERROR: cannot open $icagesGenes\n";
    my $header = <GENES>;
    while(<GENES>){
        chomp;
        my @line = split(",", $_);
        $icagesGenes{$line[0]} = $line[5];
    }
    return \%icagesGenes;
}

sub getNeighbors{
    print "NOTICE: start getting top five neighbors for mutated genes\n";
    my (%icagesGenes, %biosystem, %neighbors);
    my ($icagesGenesRef, $biosystemRef);
    my $index;
    $icagesGenesRef = shift;
    $biosystemRef = shift;
    %icagesGenes = %{$icagesGenesRef};
    %biosystem = %{$biosystemRef};
    foreach my $gene (sort keys %icagesGenes){
        $index = 0;
        $neighbors{$gene}{$gene}{"biosystem"} = 1;
        $neighbors{$gene}{$gene}{"icages"} = $icagesGenes{$gene};
        $neighbors{$gene}{$gene}{"product"} = $icagesGenes{$gene};
        foreach my $neighbor (sort { $biosystem{$b} <=> $biosystem{$a} }  keys %{$biosystem{$gene}}){
            last if $index == 5;
            $index ++;
            $neighbors{$neighbor}{$gene}{"biosystem"} = $biosystem{$gene}{$neighbor};
            $neighbors{$neighbor}{$gene}{"icages"} = $icagesGenes{$gene};
            $neighbors{$neighbor}{$gene}{"product"} =  $icagesGenes{$gene} * $biosystem{$gene}{$neighbor};
        }
    }
    return \%neighbors;
}

sub getDrugs{
    print "NOTICE: start getting drugs for seed genes\n";
    my (%neighbors, %onc, %sup);
    my ($neighborsRef, $oncRef, $supRef);
    my (@seeds, @onc, @sup, @other);
    my ($onc, $sup, $other);
    my ($rawInputFile, $supFile, $oncFile, $otherFile, $icagesLocation, $callDgidb);
    $rawInputFile = shift;
    $icagesLocation = shift;
    $neighborsRef = shift;
    $oncRef = shift;
    $supRef = shift;
    %neighbors = %{$neighborsRef};
    %onc = %{$oncRef};
    %sup = %{$supRef};
    @seeds = keys %neighbors;
    $callDgidb = $icagesLocation . "bin/DGIdb/getDrugList.pl";
    $supFile = $rawInputFile . ".suppressor.drug";
    $oncFile = $rawInputFile . ".oncogene.drug";
    $otherFile = $rawInputFile . ".other.drug";
    for(0..$#seeds){
        if(exists $sup{$seeds[$_]}){
            push @sup, $seeds[$_];
        }elsif(exists $onc{$seeds[$_]}){
            push @onc, $seeds[$_];
        }else{
            push @other, $seeds[$_];
        }
    }
    $sup = join(",", @sup);
    $onc = join(",", @onc);
    $other = join(",", @other);
    if($sup ne ""){
        !system("$callDgidb --genes='$sup' --interaction_type='activator,other/unknown,n/a,inducer,stimulator' --source_trust_levels='Expert curated' --output='$supFile'") or die "ERROR: cannot get drugs\n";
    }
    if($onc ne ""){
        !system("$callDgidb --genes='$onc' --interaction_type='inhibitor,suppressor,antibody,antagonist,blocker,other/unknown,n/a' --source_trust_levels='Expert curated' --output='$oncFile'") or die "ERROR: cannot get drugs\n";
    }
    if($other ne ""){
        !system("$callDgidb --genes='$other' --interaction_type='inhibitor,suppressor,antibody,antagonist,blocker,activator,other/unknown,n/a,inducer,stimulator' --source_trust_levels='Expert curated' --output='$otherFile'") or die "ERROR: cannot get drugs\n";
    }
}


sub processDrugs{
    print "NOTICE: start processing drugs from DGIdb\n";
    my ($rawInputFile, $matchFile, $allDrugs, $icagesDrugs);
    my (%neighbors, %activity, %icagesDrug, %icagesPrint);
    my ($neighborsRef, $activityRef);
    my ($oncDrugFile, $supDrugFile, $otherDrugFile);
    $rawInputFile = shift;
    $neighborsRef = shift;
    $activityRef = shift;
    %neighbors = %{$neighborsRef};
    %activity = %{$activityRef};
    $matchFile = $rawInputFile . ".*.drug";
    $oncDrugFile = $rawInputFile . ".oncogene.drug";
    $supDrugFile = $rawInputFile . ".suppressor.drug";
    $otherDrugFile = $rawInputFile . ".other.drug";
    $allDrugs = $rawInputFile . ".drug.all";
    $icagesDrugs = $rawInputFile . ".icagesDrugs.csv";
    if((-e $oncDrugFile) or (-e $supDrugFile) or (-e $otherDrugFile)){
        !system("cat $matchFile > $allDrugs") or die "ERROR: cannot concatenate drug files\n";
    }else{
        !system("cat $matchFile > $allDrugs") or die "ERROR: cannot concatenate drug files\n";
    }
    open(DRUG, "$allDrugs") or die "ERROR: cannot open drug file $allDrugs\n";
    open(OUT, ">$icagesDrugs") or die "ERROR: cannot open $icagesDrugs\n";
    while(<DRUG>){
        chomp;
        my @line = split("\t", $_);
        next unless defined $line[1];
        my $neighbor = $line[0];
        my $index = 0;
        foreach my $target (sort { $neighbors{$neighbor}{$b}{"product"} <=> $neighbors{$neighbor}{$a}{"product"} } keys %{$neighbors{$neighbor}}){
            last if $index == 1;
            if(exists $icagesDrug{$line[1]}{$neighbor}){
                if($neighbors{$neighbor}{$target}{"product"} > $icagesDrug{$line[1]}{$neighbor}{$target}{"biosystem"} * $icagesDrug{$line[1]}{$neighbor}{$target}{"icages"}){
                    $icagesDrug{$line[1]}{$neighbor}{$target}{"biosystem"} = $neighbors{$neighbor}{$target}{"biosystem"};
                    $icagesDrug{$line[1]}{$neighbor}{$target}{"icages"} = $neighbors{$neighbor}{$target}{"icages"} ;
                    if(exists $activity{$line[1]}){
                        $icagesDrug{$line[1]}{$neighbor}{$target}{"activity"} = $activity{$line[1]};
                    }else{
                        $icagesDrug{$line[1]}{$neighbor}{$target}{"activity"} = 0;
                    }
                }
            }else{
                $icagesDrug{$line[1]}{$neighbor}{$target}{"biosystem"} = $neighbors{$neighbor}{$target}{"biosystem"};
                $icagesDrug{$line[1]}{$neighbor}{$target}{"icages"} = $neighbors{$neighbor}{$target}{"icages"} ;
                if(exists $activity{$line[1]}){
                    $icagesDrug{$line[1]}{$neighbor}{$target}{"activity"} = $activity{$line[1]};
                }else{
                    $icagesDrug{$line[1]}{$neighbor}{$target}{"activity"} = 0;
                }
            }
            $index ++;
        }
    }
    foreach my $drug (sort keys %icagesDrug){
        foreach my $neighbor (sort keys %{$icagesDrug{$drug}}){
            foreach my $final (sort keys %{$icagesDrug{$drug}{$neighbor}}){
                my $icagesDrug = $icagesDrug{$drug}{$neighbor}{$final}{"biosystem"} * $icagesDrug{$drug}{$neighbor}{$final}{"icages"} * $icagesDrug{$drug}{$neighbor}{$final}{"activity"};
                $icagesPrint{$drug}{"score"} = $icagesDrug;
                $icagesPrint{$drug}{"content"} = "$drug,$final,$neighbor,$icagesDrug{$drug}{$neighbor}{$final}{\"icages\"},$icagesDrug{$drug}{$neighbor}{$final}{\"biosystem\"},$icagesDrug{$drug}{$neighbor}{$final}{\"activity\"},$icagesDrug";
            }
        }
    }
    print OUT "drugName,finalTarget,directTarget,maxRadialSVMScore,maxBioSystemsScore,maxActivityScore,icagesDrugScore\n";
    foreach my $drug (sort {$icagesPrint{$b}{"score"} <=> $icagesPrint{$a}{"score"}} keys %icagesPrint){
        print OUT "$icagesPrint{$drug}{\"content\"}\n";
    }
    close OUT;
    close DRUG;
}







