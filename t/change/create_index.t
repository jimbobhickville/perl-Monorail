#!perl

use Test::Spec;
use Test::Deep;
use Monorail::Change::CreateIndex;
use Monorail::Change::CreateTable;
use DBI;
use DBD::SQLite;
use DBIx::Class::Schema;

describe 'An add field change' => sub {
    my $sut;
    my %sut_args;
    before each => sub {
        %sut_args = (
            table   => 'epcot',
            name    => 'ride_idx',
            fields  => ['ride'],
            type    => 'normal',
            options => [],
        );
        $sut = Monorail::Change::CreateIndex->new(%sut_args);
        $sut->db_type('PostgreSQL');
    };

    it 'produces valid sql' => sub {
        like($sut->as_sql, qr/CREATE INDEX ride_idx on epcot \(ride\)/i);
    };

    it 'produces valid perl' => sub {
        my $perl = $sut->as_perl;

        my $new = eval $perl;
        cmp_deeply($new, all(
            isa('Monorail::Change::CreateIndex'),
            methods(%sut_args),
        ));
    };

    it 'transforms a schema' => sub {
        my $schema = SQL::Translator::Schema->new;
        $schema->add_table(name => 'epcot')->add_field(
            name           => 'ride',
            data_type      => 'text',
            is_nullable    => 1,
            is_primary_key => 0,
            is_unique      => 0,
            default_value  => undef,
        );

        $sut->transform_schema($schema);

        my ($index) = $schema->get_table('epcot')->get_indices;
        cmp_deeply(
            $index,
            methods(
                type => 'NORMAL',
                name => 'ride_idx',
                fields => [qw/ride/],
            )
        );
    };

    it 'manipulates an in-memory dbix' => sub {
        my $dbix      = DBIx::Class::Schema->connect(sub { DBI->connect('dbi:SQLite:dbname=:memory:') });
        my $table_add = Monorail::Change::CreateTable->new(
            name => 'epcot',
            fields => [
                {
                    name           => 'ride',
                    type           => 'text',
                    is_nullable    => 1,
                    is_primary_key => 1,
                    is_unique      => 0,
                    default_value  => undef,
                },
            ],
            db_type => 'SQLite'
        );

        $table_add->transform_dbix($dbix);
        $sut->db_type('SQLite');
        $sut->transform_dbix($dbix);

        my $class = $dbix->source('epcot')->result_class;

        my $sqlt_table = mock();
        my $was_called = $sqlt_table->expects('add_index')->once->with_deep(all(
            isa('SQL::Translator::Schema::Index'),
            methods(
                name   => $sut->name,
                fields => scalar $sut->fields,
            ),
        ));

        $class->sqlt_deploy_hook($sqlt_table);

        ok($was_called->verify)
    }
};

runtests;
