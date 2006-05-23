package Slim::DataStores::DBI::DataModel;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This file is a subclass of Class::DBI, which allows an object <-> relational
# mapping for the data in the database. ::Track, ::Album, etc all inherit from
# it. 
#
# It also includes code to do complex joins given our schema.

use strict;

use base 'DBIx::Class';
use DBI;
use File::Basename;
use File::Path;
use Scalar::Util qw(blessed);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use FindBin qw($Bin);
use SQL::Abstract;
use SQL::Abstract::Limit;
use Scalar::Util qw(blessed);

use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::OSDetect;
use Slim::Utils::SQLHelper;

our $driver;
our $dirtyCount = 0;

# Pref or not? pingInterval is in seconds.
our $lastPingTime = 0;
our $pingInterval = 1800;

{
	my $class = __PACKAGE__;

	my @components = qw(PK::Auto Core DB);
	
	if ($] > 5.007) {
		unshift @components, 'UTF8Columns';
	}

	# DBIx::Class config
	# XXX - move to ::Schema
	$class->mk_classdata(schema_instance => bless({}, 'DBIx::Class::Schema'));

	$class->load_components(@components);
}

sub init {
	my $class = shift;

	my $source   = sprintf(Slim::Utils::Prefs::get('dbsource'), 'slimserver');
	my $username = Slim::Utils::Prefs::get('dbusername');
	my $password = Slim::Utils::Prefs::get('dbpassword');
	my $driver   = $class->driver;

	$class->connection($source, $username, $password, { 
		RaiseError => 1,
		AutoCommit => 0,
		PrintError => 1,
		Taint      => 1,
	});

	my $dbh = $class->storage->dbh || do {

		# Not much we can do if there's no DB.
		msg("Couldn't connect to info database! Fatal error: [$!] Exiting!\n");
		bt();
		exit;
	};

	$::d_info && msg("Connected to database $source\n");

	# XXX - this is a mess. Replace with DBIx::Migration
	my $version;
	my $nextversion;
	do {
		if (grep { /metainformation/ } $dbh->tables()) {
			($version) = $dbh->selectrow_array("SELECT value FROM metainformation WHERE name = 'version'");
		}

		if (defined $version) {

			$nextversion = Slim::Utils::SQLHelper->findUpgrade($driver, $version);
			
			if ($nextversion && ($nextversion ne 99999)) {

				my $upgradeFile = catdir("Upgrades", $nextversion.".sql" );
				$::d_info && msg("Upgrading to version ".$nextversion." from version ".$version.".\n");

				Slim::Utils::SQLHelper->executeSQLFile($driver, $dbh, $upgradeFile);

			} elsif ($nextversion && ($nextversion eq 99999)) {

				$::d_info && msg("Database schema out of date and purge required. Purging db.\n");

				Slim::Utils::SQLHelper->executeSQLFile($driver, $dbh, "dbdrop.sql");

				$version = undef;
				$nextversion = 0;
			}
		}

	} while ($nextversion);
	
	if (!defined($version)) {
		$::d_info && msg("Creating new database.\n");

		Slim::Utils::SQLHelper->executeSQLFile($driver, $dbh, "dbcreate.sql");
	}
}

sub driver {
	my $class = shift;

	if (!defined $driver) {

		$driver = Slim::Utils::Prefs::get('dbsource');
		$driver =~ s/dbi:(.*?):(.*)$/$1/;
	}

	return $driver;
}

sub wipeDB {
	my $class = shift;

	Slim::Utils::SQLHelper->executeSQLFile(
		$class->driver, $class->storage->dbh, "dbclear.sql"
	);

	$class->storage->dbh->commit;
	$class->storage->dbh->disconnect;
}

sub getWhereValues {
	my $term = shift;

	return () unless defined $term;

	my @values = ();

	if (ref $term eq 'ARRAY') {

		for my $item (@$term) {

			if (ref $item eq 'ARRAY') {

				# recurse if needed
				push @values, getWhereValues($item);

			} elsif (blessed($item) && $item->isa('Slim::DataStores::DBI::DataModel')) {

				push @values, $item->id();

			} elsif (defined($item) && $item ne '') {

				push @values, $item;
			}
		}

	} elsif (blessed($term) && $term->isa('Slim::DataStores::DBI::DataModel')) {

		push @values, $term->id();

	} elsif (defined($term) && $term ne '') {

		push @values, $term;
	}

	return @values;
}

our %fieldHasClass = (
	'track' => 'Slim::DataStores::DBI::Track',
	'lightweighttrack' => 'Slim::DataStores::DBI::LightWeightTrack',
	'playlist' => 'Slim::DataStores::DBI::LightWeightTrack',
	'genre' => 'Slim::DataStores::DBI::Genre',
	'album' => 'Slim::DataStores::DBI::Album',
	'artist' => 'Slim::DataStores::DBI::Contributor',
	'contributor' => 'Slim::DataStores::DBI::Contributor',
	'conductor' => 'Slim::DataStores::DBI::Contributor',
	'composer' => 'Slim::DataStores::DBI::Contributor',
	'band' => 'Slim::DataStores::DBI::Contributor',
	'comment' => 'Slim::DataStores::DBI::Comment',
);

our %searchFieldMap = (
	'id' => 'tracks.id',
	'url' => 'tracks.url', 
	'title' => 'tracks.titlesort', 
	'track' => 'tracks.id', 
	'track.title' => 'tracks.title', 
	'track.titlesort' => 'tracks.titlesort', 
	'track.titlesearch' => 'tracks.titlesearch', 
	'tracknum' => 'tracks.tracknum', 
	'ct' => 'tracks.content_type', 
	'content_type' => 'tracks.content_type', 
	'age' => 'tracks.timestamp', 
	'timestamp' => 'tracks.timestamp', 
	'size' => 'tracks.audio_size', 
	'audio_size' => 'tracks.audio_size', 
	'year' => 'tracks.year', 
	'secs' => 'tracks.secs', 
	'vbr_scale' => 'tracks.vbr_scale',
	'bitrate' => 'tracks.bitrate', 
	'rate' => 'tracks.samplerate', 
	'samplerate' => 'tracks.samplerate', 
	'samplesize' => 'tracks.samplesize', 
	'channels' => 'tracks.channels', 
	'bpm' => 'tracks.bpm', 
	'remote' => 'tracks.remote',
	'audio' => 'tracks.audio',
	'lastPlayed' => 'tracks.lastPlayed',
	'playCount' => 'tracks.playCount',
	'album' => 'tracks.album',
	'album.title' => 'albums.title',
	'album.titlesort' => 'albums.titlesort',
	'album.titlesearch' => 'albums.titlesearch',
	'album.compilation' => 'albums.compilation',
	'genre' => 'genre_track.genre', 
	'genre.name' => 'genres.name', 
	'genre.namesort' => 'genres.namesort', 
	'genre.namesearch' => 'genres.namesearch', 
	'contributor' => 'contributor_track.contributor', 
	'contributor.name' => 'contributors.name', 
	'contributor.namesort' => 'contributors.namesort', 
	'contributor.namesearch' => 'contributors.namesearch', 
	'artist' => 'contributor_track.contributor', 
	'artist.name' => 'contributors.name', 
	'artist.namesort' => 'contributors.namesort', 
	'artist.namesearch' => 'contributors.namesearch', 
	'conductor' => 'contributor_track.contributor', 
	'conductor.name' => 'contributors.name', 
	'composer' => 'contributor_track.contributor', 
	'composer.name' => 'contributors.name', 
	'band' => 'contributor_track.contributor', 
	'band.name' => 'contributors.name', 
	'comment' => 'comments.value', 
	'contributor.role' => 'contributor_track.role',
);

our %cmpFields = (
	'contributor.namesort' => 1,
	'genre.namesort' => 1,
	'album.titlesort' => 1,
	'track.titlesort' => 1,

	'contributor.namesearch' => 1,
	'genre.namesearch' => 1,
	'album.titlesearch' => 1,
	'track.titlesearch' => 1,

	'comment' => 1,
	'comment.value' => 1,
	'url' => 1,
);

our %sortFieldMap = (
	'title' => ['tracks.titlesort'],
	'genre' => ['genres.namesort'],
	'album' => ['albums.titlesort','albums.disc'],
	'contributor' => ['contributors.namesort'],
	'artist' => ['contributors.namesort'],
	'track' => ['albums.titlesort','tracks.disc','tracks.tracknum','tracks.titlesort'],
	'tracknum' => ['tracks.disc','tracks.tracknum','tracks.titlesort'],
	'year' => ['tracks.year'],
	'lastPlayed' => ['tracks.lastPlayed'],
	'playCount' => ['tracks.playCount desc'],
	'age' => ['tracks.timestamp desc', 'tracks.disc', 'tracks.tracknum', 'tracks.titlesort'],
);

our %sortRandomMap = (
	'mysql'  => 'RAND()',
);

# This is a weight table which allows us to do some basic table reordering,
# resulting in a more optimized query. EXPLAIN should tell you more.
our %tableSort = (
	'albums' => 0.6,
	'contributors' => 0.7,
	'contributor_track' => 0.9,
	'contributor_album' => 0.85,
	'genres' => 0.1,
	'genre_track' => 0.75,
	'tracks' => 0.8,
);

# The joinGraph represents a bi-directional graph where tables are
# nodes and columns that can be used to join tables are named
# arcs between the corresponding table nodes. This graph is similar
# to the entity-relationship graph, but not exactly the same.
# In the hash table below, the keys are tables and the values are
# the arcs describing the relationship.
our %joinGraph = (
	'genres' => {
		'genre_track' => 'genres.id = genre_track.genre',
	},

	'genre_track' => {
		'genres' => 'genres.id = genre_track.genre',
		'contributor_track' => 'genre_track.track = contributor_track.track',
		'tracks' => 'genre_track.track = tracks.id',
	},

	'contributors' => {
		'contributor_track' => 'contributors.id = contributor_track.contributor',
	},

	'contributor_album' => {
		'contributors' => 'contributors.id = contributor_album.contributor',
		'albums' => 'contributor_album.album = albums.id',
	},

	'contributor_track' => {
		'contributors' => 'contributors.id = contributor_track.contributor',
		'genre_track' => 'genre_track.track = contributor_track.track',
		'tracks' => 'contributor_track.track = tracks.id',
	},

	'tracks' => {
		'contributor_track' => 'contributor_track.track = tracks.id',
		'genre_track' => 'genre_track.track = tracks.id',
		'albums' => 'albums.id = tracks.album',
	},

	'albums' => {
		'tracks' => 'albums.id = tracks.album',
	},

	'comments' => {
		'tracks' => 'comments.track = tracks.id',
	},

);

# The hash below represents the shortest paths between nodes in the
# joinGraph above. The keys of this hash are tuples representing the
# start node (the field used in the findCriteria) and the end node
# (the field that we are querying for). The shortest path in the 
# joinGraph represents the smallest number of joins we need to do
# to be able to formulate our query.
# Note that while the paths below are hardcoded, for a larger graph we
# could compute the shortest path algorithmically, using Dijkstra's
# (or other) shortest path algorithm.
our %queryPath = (
	'genre:album' => ['genre_track', 'tracks', 'albums'],
	'genre:genre' => ['genre_track', 'genres'],
	'genre:contributor' => ['genre_track', 'contributor_track', 'contributors'],
	'genre:default' => ['genres', 'genre_track', 'tracks'],
	'contributor:album' => ['contributor_track', 'tracks', 'albums'],
	'contributor:genre' => ['contributor_track', 'genre_track', 'genres'],
	'contributor:contributor' => ['contributor_track', 'contributors'],
	'contributor:default' => ['contributors', 'contributor_track', 'tracks'],
	'album:album' => ['albums', 'tracks'],
	'album:genre' => ['albums', 'tracks', 'genre_track', 'genres'],
	'album:contributor' => ['tracks', 'contributor_track', 'contributors'],
	'album:default' => ['albums', 'tracks'],
	'default:album' => ['tracks', 'albums'],
	'default:genre' => ['tracks', 'genre_track', 'genres'],
	'comment:default' => ['comments', 'tracks'],
	'default:default' => ['tracks'],
);

our %fieldToNodeMap = (
	'album' => 'album',
	'genre' => 'genre',
	'contributor' => 'contributor',
	'artist' => 'contributor',
	'conductor' => 'contributor',
	'composer' => 'contributor',
	'band' => 'contributor',
	'comment' => 'comment',
);

sub findWithJoins {
	my ($class, $args) = @_;
	
	my $field  = $args->{'field'};
	my $find   = $args->{'find'};
	my $sortBy = $args->{'sortBy'};
	my $count  = $args->{'count'};
	my $idOnly = $args->{'idOnly'};
	my $c;

	# Build up a SQL query
	my $columns = "DISTINCT ";

	# The FROM tables involved in the query
	my %tables  = ();

	# The joins for the query
	my %joins = ();
	
	my $fieldTable;

	# First the columns to SELECT
	if ($c = $fieldHasClass{$field}) {

		$fieldTable = $c->table();

		$columns .= join(",", map {$fieldTable . '.' . $_ . " AS " . $_} $c->columns('Essential'));

	} elsif (defined($searchFieldMap{$field})) {

		$fieldTable = 'tracks';

		$columns .= $searchFieldMap{$field};

	} else {
		$::d_info && msg("Request for unknown field in query\n");
		return undef;
	}

	# Include the table containing the data we're selecting
	$tables{$fieldTable} = $tableSort{$fieldTable};

	# Then the WHERE clause
	my %whereHash = ();

	my $endNode = $fieldToNodeMap{$field} || 'default';

	while (my ($key, $val) = each %$find) {

		if (defined($searchFieldMap{$key})) {

			my @values = getWhereValues($val);

			if (scalar(@values)) {

				# Turn wildcards into SQL wildcards
				s/\*/%/g for @values;

				# Try to optimize and use the IN SQL
				# statement, instead of creating a massive OR
				#
				# Alternatively, create a multiple OR
				# statement for a LIKE clause
				if (scalar(@values) > 1) {

					if ($cmpFields{$key}) {

						for my $value (@values) {

							# Don't bother with a like if there's no wildcard.
							if ($value =~ /%/) {
								push @{$whereHash{$searchFieldMap{$key}}}, { 'like', $value };
							} else {
								push @{$whereHash{$searchFieldMap{$key}}}, { '=', $value };
							}
						}

					} else {

						$whereHash{$searchFieldMap{$key}} = { 'in', \@values };
					}

				} else {

					# Otherwise - we're a single value -
					# check to see if a LIKE compare is needed.
					if ($cmpFields{$key}) {

						# Don't bother with a like if there's no wildcard.
						if ($values[0] =~ /%/) {
							$whereHash{$searchFieldMap{$key}} = { 'like', $values[0] };
						} else {
							$whereHash{$searchFieldMap{$key}} = $values[0];
						}

					} else {

						$whereHash{$searchFieldMap{$key}} = $values[0];
					}
				}

			} else {

				if (ref $val && ref $val eq 'ARRAY' && scalar @$val > 0) {

					$whereHash{$searchFieldMap{$key}} = $val;

				} elsif (ref $val && ref $val eq 'HASH' && scalar keys %$val > 0) {

					$whereHash{$searchFieldMap{$key}} = $val;
				}
			}

			# if our $key is something like contributor.name -
			# strip off the name so that our join is correctly optimized.
			$key =~ s/(\.\w+)$//o;

			my $fieldQuery = $1;
			my $startNode = $fieldToNodeMap{$key} || 'default';

			# Find the query path that gives us the tables
			# we need to join across to fulfill the query.
			my $path = $queryPath{"$startNode:$endNode"};

			$::d_sql && msg("Start and End node: [$startNode:$endNode]\n");

			addQueryPath($path, \%tables, \%joins);
			if ($fieldQuery && exists($queryPath{"$startNode:$startNode"})) {
				$::d_sql && msg("Field query. Need additional join. start and End node: [$startNode:$startNode]\n");
				$path = $queryPath{"$startNode:$startNode"};
				addQueryPath($path, \%tables, \%joins);
			}
		}
	}

	# Now deal with the ORDER BY component
	my $sortFields = [];

	if (defined $sortBy) {

		if ($sortBy eq 'random') {

			$sortFields = [ $sortRandomMap{$driver} ];

		} elsif ($sortFieldMap{$sortBy}) {

			$sortFields = $sortFieldMap{$sortBy};
		}
	}

	for my $sfield (@$sortFields) {

		my ($table) = ($sfield =~ /^(\w+)\./);

		if (defined $table) {

			$tables{$table} = $tableSort{$table};

			# See if we need to do a join to allow the sortfield
			if ($table ne $fieldTable) {

				my $join = $joinGraph{$table}{$fieldTable};

				if (defined($join)) {
					$joins{$join} = 1;
				}
			}
		}
	}

	my $abstract = SQL::Abstract::Limit->new('limit_dialect' => $class->storage->dbh);

	my ($where, @bind) = $abstract->where(\%whereHash, $sortFields, $args->{'limit'}, $args->{'offset'});

	my $sql = "SELECT $columns ";
	   $sql .= "FROM " . join(", ", sort { $tables{$b} <=> $tables{$a} } keys %tables) . " ";

	if (scalar(keys %joins)) {

		$sql .= "WHERE " . join(" AND ", keys %joins ) . " ";

		$where =~ s/WHERE/AND/;
	}

	$sql .= $where;

	if ($count && $driver eq 'mysql') {

		$sql =~ s/^SELECT DISTINCT (\w+\.id) AS.*? FROM /SELECT COUNT\(DISTINCT $1\) FROM /;
	}

	# Raw - we only want the IDs
	if ($idOnly) {
		$sql =~ s/^SELECT DISTINCT (\w+\.id) AS.*? FROM /SELECT DISTINCT $1 FROM /;
	}

	if ($::d_sql) {
		#bt();
		msg("Running SQL query: [$sql]\n");
		msg(sprintf("Bind arguments: [%s]\n\n", join(', ', @bind))) if scalar @bind;
	}

	# XXX - wrap in eval?
	my $sth;

	eval {
		$sth = $class->storage->dbh->prepare_cached($sql);
	   	$sth->execute(@bind);
	};

	if ($@) {
		msg("Whoops! prepare_cached() or execute() failed on sql: [$sql] - [$@]\n");
		bt();

		# Try to return a graceful value.
		return 0 if $count;
		return [];
	}

	# Don't instansiate any objects if we're just counting.
	if ($count) {
		$count = ($sth->fetchrow_array)[0];

		$sth->finish();

		return $count;
	}

	# Always remember to finish() the statement handle, otherwise DBI will complain.
	if (!$idOnly && ($c = $fieldHasClass{$field})) {

		#my $objects = [ $c->sth_to_objects($sth) ];
		my @objects;

		while (my $h = $sth->fetchrow_hashref) {
			my $r = $c->inflate_result($c->result_source_instance, $h);
                        push(@objects, $r);
		}

		$sth->finish();
	
		return \@objects;
	}

	# Handle idOnly requests and any table that doesn't have a matching class.
	my $ref = $sth->fetchall_arrayref();

	my $objects = [ grep((defined($_) && $_ ne ''), (map $_->[0], @$ref)) ];

	$sth->finish();

	return $objects;
}

sub addQueryPath {
	my ($path, $tables, $joins) = @_;

	for my $i (0..$#{$path}) {

		my $table = $path->[$i];
		$tables->{$table} = $tableSort{$table};
				
		if ($i < $#{$path}) {
			my $nextTable = $path->[$i + 1];
			my $join = $joinGraph{$table}{$nextTable};
			$joins->{$join} = 1;
		}
	}	
}

sub print {
	my $self   = shift;
	my $fh	   = shift || *STDOUT;

	my $class  = ref($self);

	# array context lets us handle multi-column primary keys.
	print $fh join('.', $self->id) . "\n";

	# XXX - handle meta_info here, and recurse.
	for my $column (sort $class->columns) {

		my $value = defined($self->$column()) ? $self->$column() : '';

		next unless defined $value && $value !~ /^\s*$/;

		print $fh "\t$column: ";

		if (ref($value) && $value->isa('Slim::DataStores::DBI::DataModel') && $value->can('id')) {

			print $fh $value->id();

		} else {

			print $fh $value if defined $value;
		}

		print $fh "\n";
	}
}

# DBIx::Class overrides.
sub update {
	my $self  = shift;

	if ($self->is_changed) {

		$dirtyCount++;
		$self->SUPER::update;
	}

	return 1;
}

sub get {
	my $self = shift;

	return @{$self->{_column_data}}{@_};
}

sub set {
	return shift->set_column(@_);
}

# Walk any table and check for foreign rows that still exist.
sub removeStaleDBEntries {
	my $class   = shift;
	my $foreign = shift;

	$::d_import && msg("Import: Starting stale cleanup for class $class / $foreign\n");

	my $iterator = $class->search;

	# fetch one at a time to keep memory usage in check.
	while (my $obj = $iterator->next) {

		if (blessed($obj) && $obj->$foreign()->count() == 0) {

			$::d_import && msg("Import: DB garbage collection - removing $class: $obj - no more tracks!\n");

			$obj->delete;

			$dirtyCount++;
		}
	}

	$::d_import && msg("Import: Finished stale cleanup for class $class / $foreign\n");

	return 1;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
