package DBIx::ActiveRecord::Arel::Column;
use strict;
use warnings;

our $USE_FULL_NAME = 0;

sub new {
    my ($self, $table, $column) = @_;
    bless {table => $table, column => $column}, $self;
}

sub table {shift->{table}}

sub name {
  my $self = shift;
  if ($USE_FULL_NAME) {
      $self->table->table.'.'.$self->{column};
  } else {
      $self->{column};
  }
}

1;
