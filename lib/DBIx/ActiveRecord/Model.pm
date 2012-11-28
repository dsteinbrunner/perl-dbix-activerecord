package DBIx::ActiveRecord::Model;
use strict;
use warnings;

use POSIX;

use DBIx::ActiveRecord::Arel;
use DBIx::ActiveRecord;
use DBIx::ActiveRecord::Relation;
use DBIx::ActiveRecord::Scope;

use constant INSERT_RECORD_TIMESTAMPS => [qw/created_at updated_at/];
use constant UPDATE_RECORD_TIMESTAMPS => [qw/updated_at/];

sub dbh {DBIx::ActiveRecord->dbh}

sub _global {
    my $self = shift;
    my $p = ref $self || $self;
    $DBIx::ActiveRecord::GLOBAL{$p} ||= {};
}

sub table {
    my ($self, $table_name) = @_;
    return $self->_global->{table} if !$table_name;
    $self->_global->{table} = $table_name;
    $self->_global->{arel} = DBIx::ActiveRecord::Arel->create($table_name);
}

sub belongs_to {
    my ($self, $name, $package, $rel_id, $dest_id) = @_;

    if (!$rel_id) {
        $package =~ /([^:]+)$/;
        $rel_id = lc($1)."_id";
    }
    $dest_id = 'id' if !$dest_id;

    $self->_global->{arel}->parent_relation($package->arel, $rel_id, $dest_id);
    $self->_global->{joins}->{$name} = $package;

    no strict 'refs';
    *{$self."::$name"} = sub {
        my $self = shift;
        $package->eq($dest_id => $self->$rel_id);
    };
}

sub has_one {
    my ($self, $name, $package, $rel_id, $dest_id) = @_;
    $self->_add_has_relation($name, $package, $rel_id, $dest_id, 1);
}

sub has_many {
    my ($self, $name, $package, $rel_id, $dest_id) = @_;
    $self->_add_has_relation($name, $package, $rel_id, $dest_id, 0);
}

sub _add_has_relation {
    my ($self, $name, $package, $rel_id, $dest_id, $has_one) = @_;

    $rel_id = 'id' if !$rel_id;
    if (!$dest_id) {
        $self =~ /([^:]+)$/;
        $dest_id = lc($1)."_id";
    }

    $self->_global->{arel}->child_relation($package->arel, $rel_id, $dest_id);
    $self->_global->{joins}->{$name} = $package;

    no strict 'refs';
    *{$self."::$name"} = sub {
        my $self = shift;
        my $s = $package->eq($dest_id, $self->$rel_id);
        $has_one ? $s->limit(1) : $s;
    };
}

sub default_scope {
    my ($self, $coderef) = @_;
    $self->_global->{default_scope} = $coderef;
}

sub scope {
    my ($self, $name, $coderef) = @_;
    $self->_global->{scopes}->{$name} = $coderef;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    $AUTOLOAD =~ /([^:]+)$/;
    my $m = $1;
    my $s = $self->_global->{scopes}->{$m};
    die "method missing $AUTOLOAD" if !$s;
    $s->($self->scoped, @_);
}
sub DESTROY{}

sub arel {shift->_global->{arel}->clone}

sub scoped {
    my ($self) = @_;
    my $r = DBIx::ActiveRecord::Relation->new($self);
    my $ds = $self->_global->{default_scope};
    $r = $ds->($r) if $ds;
    $r;
}

sub new {
    my ($self, $hash) = @_;
    bless {-org => {}, -set => $hash || {}, in_storage => 0}, $self;
}

sub _new_from_storage {
    my ($self, $hash) = @_;
    bless {-org => $hash, -set => {}, in_storage => 1}, $self;
}

sub get_column {
    my ($self, $name) = @_;
    exists $self->{-set}->{$name} ? $self->{-set}->{$name} : $self->{-org}->{$name};
}

sub set_column {
    my ($self, $name, $value) = @_;
    $self->{-set}->{$name} = $value;
}

sub to_hash {
    my $self = shift;
    my %h;
    foreach (keys %{$self->{-org}}, keys %{$self->{-set}}) {
        $h{$_} = $self->get_column($_);
    }
    \%h;
}

sub in_storage { shift->{in_storage} }

sub save {
    my $self = shift;
    my $res = $self->in_storage ? $self->update(@_) : $self->insert(@_);
    $self->{in_storage} = 1;
    %{$self->{-org}} = (%{$self->{-org}}, %{$self->{-set}});
    $self->{-set} = {};
    $res;
}

sub insert {
    my ($self) = @_;
    return if $self->in_storage;

    my $s = $self->scoped;
    $self->_record_timestamp(INSERT_RECORD_TIMESTAMPS);
    my $sql = $s->{arel}->insert($self->to_hash);
    my $sth = $self->dbh->prepare($sql);
    my $res = $sth->execute($s->_binds);

    my $insert_id = $sth->{'insertid'} || $self->dbh->{'mysql_insertid'};
    $self->{-set}->{$self->_global->{primary_keys}->[0]} = $insert_id if $insert_id;
    $res;
}

sub update {
    my ($self) = @_;
    return if !%{$self->{-set}};
    return if !$self->in_storage;

    my $s = $self->_pkey_scope;
    $self->_record_timestamp(UPDATE_RECORD_TIMESTAMPS);
    my $sql = $s->{arel}->update($self->{-set});
    my $sth = $self->dbh->prepare($sql);
    $sth->execute($s->_binds);
}

sub delete {
    my ($self) = @_;
    return if !$self->in_storage;

    my $s = $self->_pkey_scope;
    my $sql = $s->{arel}->delete;
    my $sth = $self->dbh->prepare($sql);
    $sth->execute($s->_binds);
}

sub _record_timestamp {
    my ($self, $columns) = @_;
    my %cs = map {$_ => 1} @{$self->_global->{columns}};
    my $now = POSIX::strftime("%Y-%m-%d %H:%M:%S", localtime);
    foreach (@$columns) {
        $self->{-set}->{$_} = $now if $cs{$_};
    }
}

sub _pkey_scope {
    my $self = shift;
    my $s = $self->scoped;
    $s = $s->eq($_ => $self->{-org}->{$_} || die 'primary key is empty') for @{$self->_global->{primary_keys}};
    $s;
}

sub instantiates_by_relation {
    my ($self, $relation) = @_;
    my $sth = $self->dbh->prepare($relation->to_sql);
    $sth->execute($relation->_binds);
    my @all;
    while (my $row = $sth->fetchrow_hashref) {
        push @all, $self->_new_from_storage($row);
    }
    \@all;
}

1;