# NAME

Data::Model - model interface which had more data sources unified, a.k.a data/object mapper

# SYNOPSIS

    package Your::Model;
    use base 'Data::Model';
    use Data::Model::Schema;
    use Data::Model::Driver::DBI;
    

    my $dbfile = '/foo/bar.db';
    my $driver = Data::Model::Driver::DBI->new(
        dsn => "dbi:SQLite:dbname=$dbfile",
    );
    base_driver( $driver );
    

    install_model user => schema {
        key 'id';
        columns qw/
            id
            name
        /;
    };
    

    # create database file
    unless (-f $dbfile) {
        my $dbh = DBI->connect($dsn, '', '', { RaiseError => 1, PrintError => 0 });
        for my $sql (__PACKAGE__->as_sqls) {
            $dbh->do( $sql );
        }
        $dbh->disconnect;
    }
    

    # in your script:
    use Your::Model;
    

    my $model = Your::Model->new;
    

    # insert
    my $row = $model->set(
        user => {
            id => 1,
        }
    );
    

    my $row = $model->lookup( user => 1 );
    $row->delete;

# DESCRIPTION

Data::Model is can use as ORM which can be defined briefly.

There are few documents. It is due to be increased in the near future.

# SCHEMA DEFINITION

One package can define two or more tables using DSL.

see [Data::Model::Schema](http://search.cpan.org/perldoc?Data::Model::Schema).

# METHODS

## new(\[ \\%options \]);

    my $model = Class->new;

## lookup($target => $key)

    my $row = $model->lookup( user => $id );
    print $row->name;

## lookup\_multi($target => \\@keylist)

    my @row = $model->lookup_multi( user => [ $id1, $id2 ] );
    print $row[0]->name;
    print $row[1]->name;

## get($target => $key \[, \\%options \])

    my $iterator = $model->get( user => { 
        id => {
            IN => [ $id1, $id2 ],
        }
    });
    while (my $row = $iterator->next) {
        print $row->name;
    }
    # or
    while (my $row = <$iterator>) {
        print $row->name;
    }
    # or
    while (<$iterator>) {
        print $_->name;
    }

## set($target => $key, => \\%values \[, \\%options \])

    $model->set( user => {
      id   => 3,
      name => 'insert record',
    });



if insert to table has auto increment then return $row object with fill in key column by last\_insert\_id.

    my $row = $model->set( user => {
      name => 'insert record',
    });
    say $row->id; # show last_insert_id()

## delete($target => $key \[, \\%options \])

    $model->delete( user => 3 ); # id = 3 is deleted

# ROW OBJECT METHODS

row object is provided by [Data::Model::Row](http://search.cpan.org/perldoc?Data::Model::Row).

## update

    my $row = $model->lookup( user => $id );
    $row->name('update record');
    $row->update;

## delete

    my $row = $model->lookup( user => $id );
    $row->delete;

# TRANSACTION

see [Data::Model::Transaction](http://search.cpan.org/perldoc?Data::Model::Transaction).

# DATA DRIVERS

## DBI

see [Data::Model::Driver::DBI](http://search.cpan.org/perldoc?Data::Model::Driver::DBI).

## DBI::MasterSlave

master-slave composition for mysql.

see [Data::Model::Driver::DBI::MasterSlave](http://search.cpan.org/perldoc?Data::Model::Driver::DBI::MasterSlave).

## Cache

Cash of the result of a query.

see [Data::Model::Driver::Cache::HASH](http://search.cpan.org/perldoc?Data::Model::Driver::Cache::HASH),
see [Data::Model::Driver::Cache::Memcached](http://search.cpan.org/perldoc?Data::Model::Driver::Cache::Memcached).

## Memcached

memcached is used for data storage.

see [Data::Model::Driver::Memcached](http://search.cpan.org/perldoc?Data::Model::Driver::Memcached).

## Queue::Q4M

queuing manager for Q4M.

see [Data::Model::Driver::Queue::Q4M](http://search.cpan.org/perldoc?Data::Model::Driver::Queue::Q4M).

## Memory

on memory storage.

see [Data::Model::Driver::Memory](http://search.cpan.org/perldoc?Data::Model::Driver::Memory).

# SEE ALSO

[Data::Model::Row](http://search.cpan.org/perldoc?Data::Model::Row),
[Data::Model::Iterator](http://search.cpan.org/perldoc?Data::Model::Iterator)

# ACKNOWLEDGEMENTS

Benjamin Trott more idea given by [Data::ObjectDriver](http://search.cpan.org/perldoc?Data::ObjectDriver)

# AUTHOR

Kazuhiro Osawa <yappo <at> shibuya <döt> pl>

# REPOSITORY

    git clone git://github.com/yappo/p5-Data-Model.git

Data::Model's Git repository is hosted at [http://github.com/yappo/p5-Data-Model](http://github.com/yappo/p5-Data-Model).
patches and collaborators are welcome.

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
