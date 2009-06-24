# storaged to memcache protocol (not for cache)
package Data::Model::Driver::Memcached;
use strict;
use warnings;
use base 'Data::Model::Driver';

use Carp ();
$Carp::Internal{(__PACKAGE__)}++;

sub memcached { shift->{memcached} }

sub update_direct { Carp::croak("update_direct is NOT IMPLEMENTED") }

sub init {
    my $self = shift;
    if (my $serializer = $self->{serializer}) {
        $serializer = 'Data::Model::Driver::Memcached::Serializer::' . $serializer
            unless $serializer =~ s/^\+//;
        unless ($serializer eq 'Data::Model::Driver::Memcached::Serializer::Default') {
            eval "use $serializer"; ## no critic
            Carp::croak $@;
        }
        $self->{serializer} = $serializer;
    }
}

sub lookup {
    my($self, $schema, $key) = @_;
    my $cache_key = $self->cache_key($schema, $key);
    my $ret = $self->{memcached}->get( $cache_key );
    return unless $ret;
    if ($self->{serializer}) {
        $ret = $self->{serializer}->deserialize($self, $ret);
    }
    return $ret;
}

sub lookup_multi {
    my($self, $schema, $keys) = @_;
    my @cache_keys = map { $self->cache_key($schema, $_) } @{ $keys };
    my $ret = $self->{memcached}->get_multi( @cache_keys );
    return unless $ret;

    my %resultlist;
    while (my($id, $data) = each %{ $ret }) {
        if ($self->{serializer}) {
            $data = $self->{serializer}->deserialize($self, $data);
        }
        my $key = $schema->get_key_array_by_hash($data);
        $resultlist{join "\0", @{ $key }} = +{ %{ $data } };
    }
    return \%resultlist;
}

sub get {
    my($self, $schema, $key, $columns, %args) = @_;

    my $cache_key = $self->cache_key($schema, $key);
    my $ret = $self->{memcached}->get( $cache_key );
    return unless $ret;
    if ($self->{serializer}) {
        $ret = $self->{serializer}->deserialize($self, $ret);
    }
    return $self->_generate_result_iterator([ $ret ]), +{};
}

sub set {
    my($self, $schema, $key, $columns, %args) = @_;

    my $cache_key = $self->cache_key($schema, $key);
    my $data = $columns;
    if ($self->{serializer}) {
        $data = $self->{serializer}->serialize($self, $columns);
    }
    my $ret = $self->{memcached}->add( $cache_key, $data );
    return unless $ret;

    $columns;
}

sub replace {
    my($self, $schema, $key, $columns, %args) = @_;

    my $cache_key = $self->cache_key($schema, $key);
    my $data = $columns;
    if ($self->{serializer}) {
        $data = $self->{serializer}->serialize($self, $columns);
    }
    my $ret = $self->{memcached}->set( $cache_key, $data );
    return unless $ret;

    $columns;
}

sub update {
    my($self, $schema, $old_key, $key, $old_columns, $columns, $changed_columns, %args) = @_;

    my $old_cache_key = $self->cache_key($schema, $old_key);
    my $new_cache_key = $self->cache_key($schema, $key);
    unless ($old_cache_key eq $new_cache_key) {
        my $ret = $self->delete($schema, $old_key);
        return unless $ret;
    }

    my $data = $columns;
    if ($self->{serializer}) {
        $data = $self->{serializer}->serialize($self, $columns);
    }
    my $ret = $self->{memcached}->set( $new_cache_key, $data );
    return unless $ret;

    $columns;
}

sub delete {
    my($self, $schema, $key, $columns, %args) = @_;
    my $cache_key = $self->cache_key($schema, $key);
    my $data = $self->{memcached}->get( $cache_key );
    return unless $data;
    my $ret = $self->{memcached}->delete( $cache_key );
    return unless $ret;
    $data;
}

package
    Data::Model::Driver::Memcached::Serializer::Default;
# serializer use messagepack format
# implement format is map16, map32, fixmap and nil, raw16, rwa32, fixraw and Positive FixNum, uint
# see http://msgpack.sourceforge.jp/spec
use strict;
use warnings;
use Carp ();
$Carp::Internal{(__PACKAGE__)}++;

my $MAGIC = 'd'^'e'^'f'^'a'^'u'^'l'^'t';
my $MAP16 = pack 'C', 0xde;
my $MAP32 = pack 'C', 0xdf;
my $RAW16 = pack 'C', 0xda;
my $RAW32 = pack 'C', 0xdb;
my $NIL   = pack 'C', 0xc0;

my $UINT8  = pack 'C', 0xcc;
my $UINT16 = pack 'C', 0xcd;
my $UINT32 = pack 'C', 0xce;
my $UINT64 = pack 'C', 0xcf;


sub serialize {
    my($class, $c, $hash) = @_;
    Carp::croak "usage: $class->serialize(\$self, \$hashref)" unless ref($hash) eq 'HASH';
    my $num = scalar(keys(%{ $hash }));
    Carp::croak "this serializer work is under 2^32 columns" if $num >= (2**32);

    my $pack = $MAGIC;
    if ($num < 16) {
        # FixMap
        $pack .= pack 'C', (0x80 + $num);
    } elsif ($num < 256*256) {
        # map16
        $pack .= $MAP16 . pack('n', $num);
   } else {
        # map32
        $pack .= $MAP32 . pack('N', $num);
    }

    while (my($k, $v) = each %{ $hash }) {
        if (defined $k) {
            if ($k =~ /\A[0-9]+\z/ && $k <= 0xffffffff) {
                # Positive FixNum, uint
                if ($k <= 0x7f) {
                    # Positive FixNum
                    $pack .= pack('C', $k);
                } elsif ($k <= 0xff) {
                    # uint 8
                    $pack .= $UINT8 . pack('C', $k);
                } elsif ($k <= 0xffff) {
                    # uint 16
                    $pack .= $UINT16 . pack('n', $k);
                } elsif ($k <= 0xffffffff) {
                    # uint 32
                    $pack .= $UINT32 . pack('N', $k);
                } else {
                    Carp::croak "oops? ($k => $v)";
                }
            } else {
                my $l = length($k);
                if ($l < 32) {
                    $pack .= pack 'C', 0xa0 + $l;
                } elsif ($l < 256*256) {
                    $pack .= $RAW16 . pack('n', $l);
                } elsif ($l < 2**32) {
                    $pack .= $RAW32 . pack('N', $l);
                } else {
                    Carp::croak "this serializer work is under 2^32 length ($k => $v)";
                }
                $pack .= $k;
            }
        } else {
            # undef
            $pack .= $NIL;
        }

        if (defined $v) {
            if ($v =~ /\A[0-9]+\z/ && $v <= 0xffffffff) {
                # Positive FixNum, uint
                if ($v <= 0x7f) {
                    # Positive FixNum
                    $pack .= pack('C', $v);
                } elsif ($v <= 0xff) {
                    # uint 8
                    $pack .= $UINT8 . pack('C', $v);
                } elsif ($v <= 0xffff) {
                    # uint 16
                    $pack .= $UINT16 . pack('n', $v);
                } elsif ($v <= 0xffffffff) {
                    # uint 32
                    $pack .= $UINT32 . pack('N', $v);
                } else {
                    Carp::croak "oops? ($k => $v)";
                }
            } else {
                my $l = length($v);
                if ($l < 32) {
                    $pack .= pack 'C', 0xa0 + $l;
                } elsif ($l < 256*256) {
                    $pack .= $RAW16 . pack('n', $l);
                } elsif ($l < 2**32) {
                    $pack .= $RAW32 . pack('N', $l);
                } else {
                    Carp::croak "this serializer work is under 2^32 length ($k => $v)";
                }
                $pack .= $v;
            }
        } else {
            # undef
            $pack .= $NIL;
        }
    }

    $pack;
}

sub deserialize {
    my($class, $c, $pack) = @_;
    $pack =~ s/^(.)//;
    my $fmt = $1;
    Carp::croak "this pack data is not Default format" unless $fmt eq $MAGIC;

    my $pos = 0;
    my $len = length($pack);

    # unpack hash header
    my $map_type = substr($pack, $pos++, 1);
    my $elements = 0;
    if ($map_type eq $MAP16) {
        $elements = unpack 'n', substr($pack, $pos);
        $pos += 2;
    } elsif ($map_type eq $MAP32) {
        $elements = unpack 'N', substr($pack, $pos);
        $pos += 4;
    } else {
        # under 16 elements
        $elements = unpack 'C', $map_type;
        $elements -= 0x80;
        Carp::croak "extra bytes" if $elements >= 16;
    }

    # unpack for map elements
    my $hash = +{};
    for (1..$elements) {
        my $k;
        for (0..1) {
            my $v;
            my $len;

            my $data_type = substr($pack, $pos++, 1);
            if ($data_type eq $NIL) {
                $v = undef;
            } elsif ($data_type eq $UINT8 || $data_type eq $UINT16 || $data_type eq $UINT32) {
                if ($data_type eq $UINT8) {
                    $v = unpack('C', substr($pack, $pos++));
                } elsif ($data_type eq $UINT16) {
                    $v = unpack('n', substr($pack, $pos));
                    $pos += 2;
                } elsif ($data_type eq $UINT32) {
                    $v = unpack('N', substr($pack, $pos));
                    $pos += 4;
                }
            } else {
                my $is_num;
                if ($data_type eq $RAW16) {
                    $len = unpack 'n', substr($pack, $pos);
                    $pos += 2;
                } elsif ($data_type eq $RAW32) {
                    $len = unpack 'N', substr($pack, $pos);
                    $pos += 4;
                } else {
                    $len = unpack 'C', $data_type;
                    if ($len <= 0x7f) {
                        # Positive FixNum
                        $v = $len;
                        $is_num = 1;
                    } else {
                        $len -= 0xa0;
                        Carp::croak "extra bytes" if $len >= 32;
                    }
                }
                unless ($is_num) {
                    $v = substr($pack, $pos, $len);
                    $pos += $len;
                }
            }

            if ($_) {
                $hash->{$k} = $v;
            } else {
                $k = $v;
            }
        }
    }

    $hash;
}

1;

=head1 NAME

Data::Model::Driver::Memcached - storage driver for memcached protocol

=head1 SYNOPSIS

  package MyDB;
  use base 'Data::Model';
  use Data::Model::Schema;
  use Data::Model::Driver::Memcached;
  
  my $dbi_connect_options = {};
  my $driver = Data::Model::Driver::Memcached->new(
      memcached => Cache::Memcached::Fast->new({ servers => [ { address => "localhost:11211" }, ], }),
  );
  
  base_driver $driver;
  install_model model_name => schema {
    ....
  };


use customizable serializer

  my $driver = Data::Model::Driver::Memcached->new(
      memcached  => Cache::Memcached::Fast->new({ servers => [ { address => "localhost:11211" }, ], }),
      serializer => 'Default', # default is messagepack minimum set for Data::Model
  );

  {
      package MySerializer;
      sub serialize {
          my($class, $c, $hash) = @_;
          # you serialize of $hash
          return $serialize_string;
      }
      sub deserialize {
          my($class, $c, $serialize_string) = @_;
          ...
          return $hash;
      }
  }
  my $driver = Data::Model::Driver::Memcached->new(
      memcached  => Cache::Memcached::Fast->new({ servers => [ { address => "localhost:11211" }, ], }),
      serializer => '+MySerializer',
  );


=head1 DESCRIPTION

Storage is used via a memcached protocol.

It can save at memcached, Tokyo Tyrant, kai, groonga, etc.

=head1 SEE ALSO

L<Cache::Memcache::Fast>,
L<Data::Model>

=head1 AUTHOR

Kazuhiro Osawa E<lt>yappo <at> shibuya <döt> plE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
