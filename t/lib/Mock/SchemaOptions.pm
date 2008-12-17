package Mock::SchemaOptions;
use strict;
use warnings;
use base 'Data::Model';
use Data::Model::Schema;

install_model unq => schema {
    driver $main::DRIVER;
    key [qw/ id1 id2 /];
    unique unq_2 => [qw/ id2 id1 /];

    columns qw( id1 id2 );

    schema_options key_as_unique => 'unq_1';
    schema_options create_sql_attributes => {
        SQLite => 'TYPE=InnoDB',
    };
};

install_model unq2 => schema {
    driver $main::DRIVER;
    key [qw/ id2 id1 /];
    unique unq_1 => [qw/ id1 id2 /];

    columns qw( id1 id2 );

    schema_options key_as_unique => 'unq_2';
    schema_options create_sql_attributes => {
        SQLite => 'TYPE=InnoDB',
    };
};

1;
