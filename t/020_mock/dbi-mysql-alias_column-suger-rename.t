use t::Utils config => +{
    type   => 'AliasColumnSugerRename',
    driver => 'DBI',
    dsn    => 'dbi:mysql:database=test',
};
run;
