package Regexp::RegGrp;

use 5.008009;
use warnings;
use strict;
use Carp;
use Regexp::RegGrp::Data;

BEGIN {
    if ( $] < 5.010000 ) {
        require re;
        re->import( 'eval' );
    }
}

use constant {
    ESCAPE_BRACKETS => qr~(?<!\\)\[[^\]]+(?<!\\)\]|\(\?([\^dlupimsx-]+:|[:=!><])~,
    ESCAPE_CHARS    => qr~\\.~,
    BRACKETS        => qr~\(~,
    BACK_REF        => qr~(?:\\g?(\d+)|\\g\{(\d+)\})~
};

# =========================================================================== #

our $VERSION = '1.003_002';

sub new {
    my ( $class, $args ) = @_;
    my $self = {};

    bless( $self, $class );

    return unless ( $self->args_are_valid( $args ) );

    $self->{_restore_pattern} = $args->{restore_pattern};
    $self->{_reggrp}          = $args->{reggrp};

    $self->_create_reggrp_objects();
    $self->_adjust_restore_pattern_attribute();

    $self->_create_regexp_string();

    return $self;
}

sub _create_regexp_string {
    my ( $self ) = @_;

    my $offset      = 1;
    my $match_index = 0;

    my @reggrp = $self->reggrp_array();

    my @data_regexp_strings = ();

    foreach my $reggrp_data ( @reggrp ) {
        my $data_regexp_string = $self->_create_data_regexp_string( $reggrp_data, $offset, $match_index );

        push( @data_regexp_strings, $data_regexp_string );

        $offset = $self->_calculate_backref_offset( $reggrp_data, $offset );
        $match_index++;
    }

    # In perl versions < 5.10 hash %+ doesn't exist, so we have to initialize it
    $self->{_re_str} = ( ( $] < 5.010000 ) ? '(?{ %+ = (); })' : '' ) . join( '|', @data_regexp_strings );
}

sub _calculate_backref_offset {
    my ( $self, $reggrp_data, $offset ) = @_;

    my $regexp = $reggrp_data->regexp();

    # Count backref brackets
    $regexp =~ s/${\(ESCAPE_CHARS)}//g;
    $regexp =~ s/${\(ESCAPE_BRACKETS)}//g;
    my @nparen = $regexp =~ /${\(BRACKETS)}/g;

    $offset += scalar( @nparen ) + 1;

    return $offset;
}

sub _create_data_regexp_string {
    my ( $self, $data, $offset, $match_index ) = @_;

    my $regexp = $data->regexp();

    my $backreference_regexp = $regexp;

    # Count backref brackets
    $backreference_regexp =~ s/${\(ESCAPE_CHARS)}//g;
    $backreference_regexp =~ s/${\(ESCAPE_BRACKETS)}//g;
    my @nparen = $backreference_regexp =~ /${\(BRACKETS)}/g;

    my $backref_pattern = '\\g{%d}';

    if ( $] < 5.010000 ) {
        $backref_pattern = '\\%d';
    }

    $regexp =~ s/${\(BACK_REF)}/sprintf( $backref_pattern, $offset + ( $1 || $2 ) )/eg;

    if ( $] < 5.010000 ) {

        # In perl versions < 5.10 we need to fill %+ hash manually
        # perl 5.8 doesn't reset the %+ hash correctly if there are zero-length submatches
        # so this is also done here
        return '(' . $regexp . ')' . '(?{ %+ = ( \'_' . $match_index . '\' => $^N ); })';
    }
    else {
        return '(?\'_' . $match_index . '\'' . $regexp . ')';
    }
}

sub _create_reggrp_objects {
    my ( $self ) = @_;

    my $no = 0;

    map {
        $no++;

        unless ( $self->_create_reggrp_object( $_ ) ) {
            carp( 'RegGrp No ' . $no . ' in arrayref is malformed!' );
            return 0;
        }

    } @{ $self->{_reggrp} };

    return 1;
}

sub _create_reggrp_object {
    my ( $self, $args ) = @_;

    my $reggrp_data = Regexp::RegGrp::Data->new(
        {
            regexp      => $args->{regexp},
            replacement => $args->{replacement},
            placeholder => $args->{placeholder},
            modifier    => $args->{modifier}
        }
    );

    return 0 unless ( $reggrp_data );

    $self->reggrp_add( $reggrp_data );

    return 1;
}

sub _adjust_restore_pattern_attribute {
    my ( $self ) = @_;

    my $restore_pattern = $self->{_restore_pattern} || qr~\x01(\d+)\x01~;
    $self->{_restore_pattern} = qr/$restore_pattern/;
}

sub args_are_valid {
    my ( $self, $args ) = @_;

    if ( ref( $args ) ne 'HASH' ) {
        carp( 'First argument must be a hashref!' );
        return 0;
    }

    unless ( exists( $args->{reggrp} ) ) {
        carp( 'Key "reggrp" does not exist in input hashref!' );
        return 0;
    }

    if ( ref( $args->{reggrp} ) ne 'ARRAY' ) {
        carp( 'Value for key "reggrp" must be an arrayref!' );
        return 0;
    }

    if (    ref( $args->{restore_pattern} )
        and ref( $args->{restore_pattern} ) ne 'Regexp' )
    {
        carp( 'Value for key "restore_pattern" must be a scalar or regexp!' );
        return 0;
    }

    return 1;
}

# re_str methods

sub re_str {
    my $self = shift;

    return $self->{_re_str};
}

# /re_str methods

# restore_pattern methods

sub restore_pattern {
    my $self = shift;

    return $self->{_restore_pattern};
}

# /restore_pattern methods

# store_data methods

sub store_data_add {
    my ( $self, $data ) = @_;

    push( @{ $self->{_store_data} }, $data );
}

sub store_data_by_idx {
    my ( $self, $idx ) = @_;

    return $self->{_store_data}->[$idx];
}

sub store_data_count {
    my $self = shift;

    return scalar( @{ $self->{_store_data} || [] } );
}

sub flush_stored {
    my $self = shift;

    $self->{_store_data} = [];
}

# /store_data methods

# reggrp methods

sub reggrp_add {
    my ( $self, $reggrp ) = @_;

    push( @{ $self->{_reggrps} }, $reggrp );
}

sub reggrp_array {
    my $self = shift;

    return @{ $self->{_reggrps} };
}

sub reggrp_by_idx {
    my ( $self, $idx ) = @_;

    return $self->{_reggrps}->[$idx];
}

# /reggrp methods

sub exec {
    my ( $self, $input, $opts ) = @_;

    if ( ref( $input ) ne 'SCALAR' ) {
        carp( 'First argument in Regexp::RegGrp->exec must be a scalarref!' );
        return undef;
    }

    $opts ||= {};

    if ( ref( $opts ) ne 'HASH' ) {
        carp( 'Second argument in Regexp::RegGrp->exec must be a hashref!' );
        return undef;
    }

    my $to_process = \'';
    my $cont       = 'void';

    if ( defined( wantarray ) ) {
        my $tmp_input = ${$input};

        $to_process = \$tmp_input;
        $cont       = 'scalar';
    }
    else {
        $to_process = $input;
    }

    ${$to_process} =~ s/${\$self->re_str()}/$self->_process( { match_hash => \%+, opts => $opts } )/eg;

    # Return a scalar if requested by context
    return ${$to_process} if ( $cont eq 'scalar' );
}

sub _process {
    my ( $self, $args ) = @_;

    my %match_hash = %{ $args->{match_hash} };
    my $opts       = $args->{opts};

    my $match_key = ( keys( %match_hash ) )[0];
    my ( $midx ) = $match_key =~ /^_(\d+)$/;
    my $match = $match_hash{$match_key};

    my $reggrp = $self->reggrp_by_idx( $midx );

    my @submatches = $match =~ $reggrp->regexp();
    map { $_ .= ''; } @submatches;

    my $ret = $match;

    my $replacement = $reggrp->replacement();

    if ( defined( $replacement )
        and not ref( $replacement ) )
    {
        $ret = $replacement;
    }
    elsif ( ref( $replacement ) eq 'CODE' ) {
        $ret = $replacement->(
            {
                match      => $match,
                submatches => \@submatches,
                opts       => $opts,
            }
        );
    }

    my $placeholder = $reggrp->placeholder();

    if ( $placeholder ) {
        my $store = $ret;

        if ( not ref( $placeholder ) ) {
            $ret = $placeholder;
        }
        elsif ( ref( $placeholder ) eq 'CODE' ) {
            $ret = $placeholder->(
                {
                    match             => $match,
                    submatches        => \@submatches,
                    opts              => $opts,
                    placeholder_index => $self->store_data_count()
                }
            );
        }

        $self->store_data_add( $store );
    }

    return $ret;
}

sub restore_stored {
    my ( $self, $input ) = @_;

    if ( ref( $input ) ne 'SCALAR' ) {
        carp( 'First argument in Regexp::RegGrp->restore must be a scalarref!' );
        return undef;
    }

    my $to_process = \'';
    my $cont       = 'void';

    if ( defined( wantarray ) ) {
        my $tmp_input = ${$input};

        $to_process = \$tmp_input;
        $cont       = 'scalar';
    }
    else {
        $to_process = $input;
    }

    # Here is a while loop, because there could be recursive replacements
    while ( ${$to_process} =~ /${\$self->restore_pattern()}/ ) {
        ${$to_process} =~ s/${\$self->restore_pattern()}/$self->store_data_by_idx( $1 )/egsm;
    }

    $self->flush_stored();

    # Return a scalar if requested by context
    return ${$to_process} if ( $cont eq 'scalar' );
}

1;

__END__

=head1 NAME

Regexp::RegGrp - Groups a regular expressions collection

=head1 VERSION

Version 1.003_002

=head1 DESCRIPTION

Groups regular expressions to one regular expression

=head1 SYNOPSIS

    use Regexp::RegGrp;

    my $reggrp = Regexp::RegGrp->new(
        {
            reggrp          => [
                {
                    regexp => '%name%',
                    replacement => 'John Doe',
                    modifier    => $modifier
                },
                {
                    regexp => '%company%',
                    replacement => 'ACME',
                    modifier    => $modifier
                }
            ],
            restore_pattern => $restore_pattern
        }
    );

    $reggrp->exec( \$scalar );

To return a scalar without changing the input simply use (e.g. example 2):

    my $ret = $reggrp->exec( \$scalar );

The first argument must be a hashref. The keys are:

=over 4

=item reggrp (required)

Arrayref of hashrefs. The keys of each hashref are:

=over 8

=item regexp (required)

A regular expression

=item replacement (optional)

Scalar or sub.

A replacement for the regular expression match. If not set, nothing will be replaced except "store" is set.
In this case the match is replaced by something like sprintf("\x01%d\x01", $idx) where $idx is the index
of the stored element in the store_data arrayref. If "store" is set the default is:

    sub {
        return sprintf( "\x01%d\x01", $_[0]->{placeholder_index} );
    }

If a custom restore_pattern is passed to to constructor you MUST also define a replacement. Otherwise
it is undefined.

If you define a subroutine as replacement an hashref is passed to this subroutine. This hashref has
four keys:

=over 12

=item match

Scalar. The match of the regular expression.

=item submatches

Arrayref of submatches.

=item placeholder_index

The next index. You need this if you want to create a placeholder and store the replacement in the
$self->{store_data} arrayref.

=item opts

Hashref of custom options.

=back

=item modifier (optional)

Scalar. The default is 'sm'.

=item store (optional)

Scalar or sub. If you define a subroutine an hashref is passed to this subroutine. This hashref has
three keys:

=over 12

=item match

Scalar. The match of the regular expression.

=item submatches

Arrayref of submatches.

=item opts

Hashref of custom options.

=back

A replacement for the regular expression match. It will not replace the match directly. The replacement
will be stored in the $self->{store_data} arrayref. The placeholders in the text can easily be rereplaced
with the restore_stored method later.

=back

=item restore_pattern (optional)

Scalar or Regexp object. The default restore pattern is

    qr~\x01(\d+)\x01~

This means, if you use the restore_stored method it is looking for \x010\x01, \x011\x01, ... and
replaces the matches with $self->{store_data}->[0], $self->{store_data}->[1], ...

=back

=head1 EXAMPLES

=over 4

=item Example 1

Common usage.

    #!/usr/bin/perl

    use strict;
    use warnings;

    use Regexp::RegGrp;

    my $reggrp = Regexp::RegGrp->new(
        {
            reggrp          => [
                {
                    regexp => '%name%',
                    replacement => 'John Doe'
                },
                {
                    regexp => '%company%',
                    replacement => 'ACME'
                }
            ]
        }
    );

    open( INFILE, 'unprocessed.txt' );
    open( OUTFILE, '>processed.txt' );

    my $txt = join( '', <INFILE> );

    $reggrp->exec( \$txt );

    print OUTFILE $txt;
    close(INFILE);
    close(OUTFILE);

=item Example 2

A scalar is requested by the context. The input will remain unchanged.

    #!/usr/bin/perl

    use strict;
    use warnings;

    use Regexp::RegGrp;

    my $reggrp = Regexp::RegGrp->new(
        {
            reggrp          => [
                {
                    regexp => '%name%',
                    replacement => 'John Doe'
                },
                {
                    regexp => '%company%',
                    replacement => 'ACME'
                }
            ]
        }
    );

    open( INFILE, 'unprocessed.txt' );
    open( OUTFILE, '>processed.txt' );

    my $unprocessed = join( '', <INFILE> );

    my $processed = $reggrp->exec( \$unprocessed );

    print OUTFILE $processed;
    close(INFILE);
    close(OUTFILE);

=back

=head1 AUTHOR

Merten Falk, C<< <nevesenin at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests through the web interface at
L<http://github.com/nevesenin/regexp-reggrp-perl/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

perldoc Regexp::RegGrp

=head1 COPYRIGHT & LICENSE

Copyright 2010, 2011 Merten Falk, all rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
