#!/usr/bin/perl -w

use strict;
use FileHandle;

my @twitter_fields = qw{ source favorited truncated created_at text user in_reply_to_user_id id in_reply_to_status_id in_reply_to_screen_name};
my $max_return_tweets = 200;
my $twitter_module = "Net::Twitter";
my $DEBUG = 0;

my $most_recent_tweet= 1;
my $newest_tweet = "";
my $oldest_tweet = "";
my $returns = 200;
my $countimported = 0;
my $outfile;


if( $#ARGV < 1) {
	die "Please provide at least your Twitter username and password as command line arguments!\n";
}

# Load Twitter-Module at runtime
eval "use $twitter_module";
die "couldn't load module $twitter_module. Reason: $!\n" if ($@);

# Initialize Twitter connections
my $nt = $twitter_module->new(
	traits   => [qw/API::REST/],
	username => $ARGV[0],
	password => $ARGV[1],
);
if( not defined($nt) or $@ ) {
	die "Could not create Twitter connection! " . $@ . "\n";
}

# Which user's Tweets should be stored? Default: logged in user
my $user2backup = (defined($ARGV[2]) and $ARGV[2] ne '') ? $ARGV[2] : $ARGV[0];

# Get last fetched tweet, if possible
my $csv_file =  $user2backup . "_twitter.csv";
if ( -f $csv_file ) { # handle existing csv file
	$most_recent_tweet = get_most_recent_tweet($csv_file);
}

# Open output CSV file
$outfile = &opencsv($csv_file);

while ($returns == 200) {
	my $ratelimit = $nt->rate_limit_status();
	print "\nRemaining API calls: " . $ratelimit->{'remaining_hits'} . "/" . $ratelimit->{'hourly_limit'} . " (reset at " . $ratelimit->{'reset_time'} . ")\n";
	eval {
		my $statuses;
		my $localcount = 0;
		# Handle multiple calls to user_timeline with different "start" Twitter-IDs
		if( $oldest_tweet eq '' and $newest_tweet eq '') {
			$statuses = $nt->user_timeline({ count => $max_return_tweets,
					since_id	=> $most_recent_tweet,
					id			=> $user2backup });
		} else {
			$statuses = $nt->user_timeline({ max_id => $oldest_tweet, count => $max_return_tweets,
					since_id	=> $most_recent_tweet,
					id => $user2backup });
		}
		my @erglist = @$statuses;
		$returns = scalar @erglist;
	
		for my $status ( @$statuses ) {
			$oldest_tweet = $status->{'id'};
			if( $localcount == 0 and $oldest_tweet ne '') { # Don't add double entries
				$localcount++;
				next;
			}
			$localcount++;
			$countimported++;
			my $csv = '';
			my $c = 0;
			foreach my $f (@twitter_fields) {
				$csv .= "\t" if ($c > 0);
				my $t;
				if( $f eq "user") {
					$t = $status->{$f}->{'id'};
				} else {
					$t = $status->{$f};
				}
				$t = "" if (not defined $t);
				$t =~ s/(\n|\r)+/ /gs;	# remove newlines from Tweets
				$t =~ s/\t/    /g;		# replace tabs with four spaces in Tweets
				$csv .= '"' . $t . '"';
				$c++;
			}
			$outfile->print ("$csv\n"); 
		}
		print "\t$localcount Tweets imported in this run.\n"; 
	};

	if ( my $err = $@ ) { # errorhandling
		$outfile->close;
		print "All in all: $countimported Tweets stored.\n";
		die $@ unless blessed $err && $err->isa('Net::Twitter::Error');

		die "HTTP Response Code: ", $err->code, "\n",
			"HTTP Message......: ", $err->message, "\n",
			"Twitter error.....: ", $err->error, "\n";
	}
	print "Sleeping 5 seconds (just in case) ...\n";
	sleep(5);
}

$outfile->close;
print "All in all: $countimported Tweets stored.\n";

exit;



sub opencsv {
	my($filename) = @_;
	my $fh;

	if ( -f $csv_file ) { # handle existing csv file
		print STDERR "$csv_file exists!\n" if( $DEBUG );
    	$fh = new FileHandle ">> $filename";
		die "Couldn't open file '$filename' for writing! Reason: $!\n" if (not defined $fh);
		$fh->binmode(":utf8");
	} else {	# create new csv file
    	$fh = new FileHandle ">> $filename";
		die "Couldn't open file '$filename' for writing! Reason: $!\n" if (not defined $fh);
		$fh->binmode(":utf8");
		&print_csv_header();
	}
	return($fh);
}

sub get_most_recent_tweet {
	my ($filename) = @_;
	my $highest_id = 1;

    my $fh = new FileHandle "< $filename";
	die "Couldn't open file '$filename' for reading! Reason: $!\n" if (not defined $fh);
	$fh->binmode(":utf8");
	$fh->getline();	# Skip the header-line

	while($_ = $fh->getline()) {
		chomp;
		my @data = split/\t/;
		$data[6] =~ s/\"//g;
		$highest_id = $data[6] if( $highest_id eq '' or $data[6] > $highest_id );
	}
	$fh->close;
	return($highest_id);
}

sub print_csv_header {
	my($fh) = @_;

	my $hc = 0;
	my $header = '';
	foreach my $field (@twitter_fields) {
		$header .= "\t" if ($hc > 0);
		$header .= '"' . $field . '"';
		$hc++;
	}
	$fh->print( "$header\n" );
}
