#!/usr/bin/perl -w

use strict;
use Net::Twitter;

my @twitter_fields = qw{ source favorited truncated created_at text user in_reply_to_user_id id in_reply_to_status_id in_reply_to_screen_name};

if( $#ARGV != 1) {
	die "Please provide your Twitter username and password als command line arguments!\n";
}



# Initialize Twitter connections
my $nt = Net::Twitter->new(
	traits   => [qw/API::REST/],
	username => $ARGV[0],
	password => $ARGV[1],
);
if( not defined($nt) or $@ ) {
	die "Could not create Twitter connection! " . $@ . "\n";
}

# Open output CSV file
open(CSV, ">twitter.csv") or die "Write error 'twitter.csv'! $!\n";
binmode CSV, ":utf8";
my $hc = 0;
my $header = '';
foreach my $field (@twitter_fields) {
	$header .= "\t" if ($hc > 0);
	$header .= '"' . $field . '"';
	$hc++;
}
print CSV "$header\n";



my $ratelimit = $nt->rate_limit_status();
print "Remaining API calls: " . $ratelimit->{'remaining_hits'} . "/" . $ratelimit->{'hourly_limit'} . " (reset at " . $ratelimit->{'reset_time'} . ")\n";

my $lastid = '';
my $returns = 200;

while ($returns == 200) {
	eval {
		my $statuses;
		my $localcount = 0;
		if( $lastid eq '') {
			$statuses = $nt->user_timeline({ count => 200 });
		} else {
			$statuses = $nt->user_timeline({ max_id => $lastid, count => 200 });
		}
		my @erglist = @$statuses;
		$returns = scalar @erglist;
	
		for my $status ( @$statuses ) {
			$lastid = $status->{'id'};
			if( $localcount == 0 and $lastid ne '') { # Don' add double entries
				$localcount++;
				next;
			}
			$localcount++;
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
				$csv .= '"' . $t . '"';
				$c++;
			}
			print CSV "$csv\n"; 
		}
	};

	if ( my $err = $@ ) { # errorhandling
		close(CSV);
		die $@ unless blessed $err && $err->isa('Net::Twitter::Error');

		die "HTTP Response Code: ", $err->code, "\n",
			"HTTP Message......: ", $err->message, "\n",
			"Twitter error.....: ", $err->error, "\n";
	}
	print "Sleeping 5 seconds (just in case) ...\n";
	sleep(5);
}

close(CSV);

