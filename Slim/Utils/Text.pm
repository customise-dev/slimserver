package Slim::Utils::Text;

use strict;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

our %caseArticlesMemoize = ();

sub ignorePunct {
	my $s = shift || return undef;

	my $orig = $s;

	$s =~ s/[!?,=+<>#%&()\"\'\$\.\\]+/ /go;
	$s =~ s/  +/ /go; # compact multiple spaces, "L.A. Mix" -> "L A Mix", not "L A  Mix"
	$s =~ s/^ +//o; # zap leading/trailing spaces.
	$s =~ s/ +$//o;

	$s = $orig if $s eq '';

	return $s;
}

sub matchCase {
	my $s = shift || return undef;

	# Upper case and fold latin1 diacritical characters into their plain versions, surprisingly useful.
	$s =~ tr{abcdefghijklmnopqrstuvwxyz�����������������������������������������������������}
		{ABCDEFGHIJKLMNOPQRSTUVWXYZAAAAACEEEEIIIINOOOOOUUUUAAAAAACEEEEIIIINOOOOOUUUUYYDD};

	return $s;
}

sub ignoreArticles {
	my $item = shift || return;

	if (!defined($Slim::Music::Info::articles)) {

		$Slim::Music::Info::articles =  Slim::Utils::Prefs::get("ignoredarticles");
		# allow a space seperated list in preferences (easier for humans to deal with)
		$Slim::Music::Info::articles =~ s/\s+/|/g;
	}
	
	#set up array for sorting items without leading articles
	$item =~ s/^($Slim::Music::Info::articles)\s+//i;

	return $item;
}

sub ignoreCaseArticles {
	my $s = shift || return undef;

	if (defined $caseArticlesMemoize{$s}) {
		return $caseArticlesMemoize{$s};
	}

	return ($caseArticlesMemoize{$s} = ignorePunct(ignoreArticles(matchCase($s))));
}

sub clearCaseArticleCache {
	%caseArticlesMemoize = ();
}

sub sortIgnoringCase {
	#set up an array without case for sorting
	my @nocase = map {ignoreCaseArticles($_)} @_;
	#return the original array sliced by the sorted caseless array
	return @_[sort {$nocase[$a] cmp $nocase[$b]} 0..$#_];
}

sub sortuniq {
	my %seen = ();
	my @uniq = ();

	foreach my $item (@_) {
		if (defined($item) && ($item ne '') && !$seen{ignoreCaseArticles($item)}++) {
			push(@uniq, $item);
		}
	}

	return sort @uniq ;
}

# similar to above but ignore preceeding articles when sorting
sub sortuniq_ignore_articles {
	my %seen = ();
	my @uniq = ();
	my $articles =  Slim::Utils::Prefs::get("ignoredarticles");
	# allow a space seperated list in preferences (easier for humans to deal with)
	$articles =~ s/\s+/|/g;

	foreach my $item (@_) {
		if (defined($item) && ($item ne '') && !$seen{ignoreCaseArticles($item)}++) {
			push(@uniq, $item);
		}
	}

	# set up array for sorting items without leading articles
	my @noarts = map {
		my $item = $_; 
		exists($Slim::Music::Info::sortCache{$item}) ? $item = $Slim::Music::Info::sortCache{$item} : $item =~ s/^($articles)\s+//i; 
		$item; 
	} @uniq;
		
	# return the uniq array sliced by the sorted articleless array
	return @uniq[sort {$noarts[$a] cmp $noarts[$b]} 0..$#uniq];
}

# XXX - %Slim::Music::Info::sortCache is implictly created in
# sortuniq_ignore_articles() above. It is not explictly created anywhere in
# Slim::Music::Info
sub getSortName {
	my $item = shift;

	return exists($Slim::Music::Info::sortCache{ignoreCaseArticles($item)}) ? $Slim::Music::Info::sortCache{ignoreCaseArticles($item)} : $item;
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
