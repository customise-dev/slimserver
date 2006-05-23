package Slim::DataStores::DBI::Comment;

# $Id$

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('comments');

	$class->add_columns(qw(id track value));

	$class->set_primary_key('id');

	$class->belongs_to(track => 'Slim::DataStores::DBI::Track');

	if ($] > 5.007) {
		$class->utf8_columns(qw/value/);
	}
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
