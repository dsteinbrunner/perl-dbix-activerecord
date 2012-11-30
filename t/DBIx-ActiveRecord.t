use strict;
use warnings;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

BEGIN {
    use_ok('DBIx::ActiveRecord');
    use_ok('DBIx::ActiveRecord::Model');
};

=pod
create database ar_test;
use ar_test;
CREATE TABLE users (
  id serial NOT NULL,
  name varchar(50) NOT NULL,
  profile text,
  blood_type varchar(2),
  deleted bool,
  created_at datetime NOT NULL,
  updated_at datetime NOT NULL
) ENGINE=InnoDB;
CREATE TABLE posts (
  id serial NOT NULL,
  user_id bigint NOT NULL,
  title varchar(255) NOT NULL,
  content text,
  created_at datetime NOT NULL,
  updated_at datetime NOT NULL
) ENGINE=InnoDB;
=cut

package User;
use base 'DBIx::ActiveRecord::Model';
__PACKAGE__->table('users');
# end User Model

package Post;
use base 'DBIx::ActiveRecord::Model';
__PACKAGE__->table('posts');
# end Post Model

package main;


DBIx::ActiveRecord->connect("dbi:mysql:ar_test", 'root', '', {});
{
    # set up
    User->unscoped->delete_all;
    ok 1;
}

{
    # basic CRUD
    my $u = User->new({name => 'hoge', profile => 'hogehoge'});
    is $u->name, 'hoge';
    is $u->profile, 'hogehoge';

    $u->name('hoge2');
    is $u->name, 'hoge2';
    $u->name();
    is $u->name, 'hoge2';
    $u->name(undef);
    is $u->name, undef;

    $u->name('hoge');
    ok !$u->id;
    $u->save; # insert!
    ok $u->id;
    $u->save; # update!
    ok $u->id;

    my $us = User->all;

    is @$us, 1;
    is $us->[0]->name, 'hoge';
    is $us->[0]->profile, 'hogehoge';

    $u = $us->[0];

    $u->name('hoge2');
    $u->save; # update!

    $us = User->all;
    is @$us, 1;
    is $us->[0]->name, 'hoge2';
    is $us->[0]->profile, 'hogehoge';

    $us->[0]->delete;

    $us = User->all;
    is @$us, 0;
}

{
    # created_at, updated_at
    my $u = User->new({name => 'test'});
    ok !$u->created_at;
    ok !$u->updated_at;
    $u->save;

    ok $u->created_at;
    ok $u->updated_at;
    is $u->created_at, $u->updated_at;

    sleep(1);

    $u->name("test2");
    $u->save;
    ok $u->created_at;
    ok $u->updated_at;
    ok $u->created_at ne $u->updated_at;
}

{
    # scoped searches
    User->create({name => 'hoge'});
    User->create({name => 'fuga'});
    User->create({name => 'hoge2', profile => 'a'});

    my $s = User->eq(name => 'hoge');
    my $us = $s->all;
    is @$us, 1;
    is $us->[0]->name, 'hoge';
    is $s->to_sql, "SELECT * FROM users WHERE name = ?";

    $s = User->eq(name => 'hoge2')->eq(profile => 'a');
    $us = $s->all;
    is @$us, 1;
    is $us->[0]->name, 'hoge2';
    is $s->to_sql, "SELECT * FROM users WHERE name = ? AND profile = ?";

    $s = User->in(id => [1,2,3])->not_null('profile')->contains(profile => 'a');
    $s->all;
    is $s->to_sql, "SELECT * FROM users WHERE id IN (?, ?, ?) AND profile IS NOT NULL AND profile LIKE ?";
}

{
     # scope
     User->default_scope(sub{ shift->ne(deleted => 1) });
     User->scope(type_a => sub{ shift->eq(blood_type => 'A') });
     User->scope(type_a_or_b => sub{ shift->in(blood_type => ['A', 'B']) });

     is(User->scoped->to_sql, "SELECT * FROM users WHERE deleted != ?");

     User->delete_all;
     User->new({deleted => 1, name => 'deleted user'})->save;

     my $us = User->all;
     is @$us, 0;
     ok 1;

     User->type_a->type_a_or_b->all;

     is(User->type_a->to_sql, "SELECT * FROM users WHERE deleted != ? AND blood_type = ?");
     is(User->type_a_or_b->to_sql, "SELECT * FROM users WHERE deleted != ? AND blood_type IN (?, ?)");
     is(User->type_a_or_b->type_a->to_sql, "SELECT * FROM users WHERE deleted != ? AND blood_type IN (?, ?) AND blood_type = ?");
}

{
    # association - belongs_to
    Post->belongs_to(user => 'User');

    my $u = User->new({name => 'aaa'});
    $u->save;

    my $p = Post->new({user_id => $u->id, title => 'aaa title'});
    $p->save;
    my $s = $p->user;
    is $s->to_sql, "SELECT * FROM users WHERE deleted != ? AND id = ?";
    is_deeply [$s->_binds], [1, $p->user_id];

    ok 1;
}

{
    # association - has_many
    User->has_many(posts => 'Post');

    my $u = User->new({name => 'aaa'});
    $u->save;
    my $s = $u->posts;

    is $s->to_sql, "SELECT * FROM posts WHERE user_id = ?";
    is_deeply [$s->_binds], [$u->id];
    ok 1;
}

{
    # association - has_one
    User->has_one(post => 'Post');

    my $u = User->new({name => 'aaa'});
    $u->save;
    my $post = $u->post;

    ok 1;
}

{
    # joins
    my $s = User->joins('posts')->merge(Post->eq(title => 'aaa'));
    $s->all;
    is $s->to_sql, "SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE users.deleted != ? AND posts.title = ?";
}

{
    # select
    my $s = User->select("id", "name")->in(id => [1,2,3]);
    $s->all;
    is $s->to_sql, "SELECT id, name FROM users WHERE deleted != ? AND id IN (?, ?, ?)";

    # join and select
    $s = User->joins('posts')->merge(Post->eq(title => 'aaa'))->select("id", "name")->in(id => [1,2,3]);
    $s->all;
    is $s->to_sql, "SELECT users.id, users.name FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE users.deleted != ? AND posts.title = ? AND users.id IN (?, ?, ?)";
}

{
    # order, group, limit, offset
    my $s = User->desc("created_at")->asc("id");
    is $s->to_sql, "SELECT * FROM users WHERE deleted != ? ORDER BY created_at DESC, id";
    $s->all;

    $s = User->group("blood_type");
    is $s->to_sql, "SELECT * FROM users WHERE deleted != ? GROUP BY blood_type";
    $s->all;

    $s = User->limit(5)->offset(2);
    is $s->to_sql, "SELECT * FROM users WHERE deleted != ? LIMIT 5 OFFSET 2";
    $s->all;

    $s = User->eq(id => 1)->lock;
    is $s->to_sql, "SELECT * FROM users WHERE deleted != ? AND id = ? FOR UPDATE";
    $s->all;
}

{
    User->first;
    User->last;
    ok 1;
}

{
    # transaction
    User->transaction(sub {
    });
    User->transaction(sub {
      die;
    });
}

{
    # scope cache
#    print STDERR "*** cache test ***\n";
    User->all;
    User->all;

#    print STDERR "*** all only ***\n";
    my $s = User->scoped;
    $s->all;
    $s->first;
    $s->last;

#    print STDERR "*** first, last, all ***\n";
    $s = User->scoped;
    $s->first;
    $s->last;
    $s->first;
    $s->last;
    $s->all;
    $s->all;

#    print STDERR "*** new scope! ***\n";
    $s->eq(id => 1)->all;

    ok 1;
}
# includes
{

#    print STDERR "*** includes user => posts ***\n";
    User->unscoped->delete_all;
    Post->unscoped->delete_all;
    my $u1 = User->new({name => 'hoge', deleted => 0});
    my $u2 = User->new({name => 'fuga', deleted => 0});
    $u1->save;
    $u2->save;

    Post->new({title => 'hoge 01', user_id => $u1->id})->save;
    Post->new({title => 'hoge 02', user_id => $u1->id})->save;
    Post->new({title => 'hoge 03', user_id => $u1->id})->save;
    Post->new({title => 'hoge 04', user_id => $u1->id})->save;
    Post->new({title => 'fuga 01', user_id => $u2->id})->save;
    Post->new({title => 'fuga 02', user_id => $u2->id})->save;

    my $us = User->includes('posts')->all;
    is @{$us->[0]->posts->all}, 4;
    is @{$us->[1]->posts->all}, 2;

    ok 1;
}

{
    # array operator
    ok @{User->scoped};

    my $users = User->includes('posts');
    foreach my $u (@$users) {
        foreach my $p (@{$u->posts}) {
            ok $u;
            ok $p;
        }
    }
    ok 1;
}
# multi join

done_testing;