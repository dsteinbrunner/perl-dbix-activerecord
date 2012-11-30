use strict;
use warnings;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../lib";

BEGIN {
    use_ok('DBIx::ActiveRecord::Arel');
    use_ok('DBIx::ActiveRecord::Arel::Native');
};

{
    my $post = DBIx::ActiveRecord::Arel->create('posts');
    my $user = DBIx::ActiveRecord::Arel->create('users');
    my $comment = DBIx::ActiveRecord::Arel->create('comments');

    $user->child_relation($post, {foreign_key => 'user_id', primary_key => 'id'});
    $post->parent_relation($user, {foreign_key => 'user_id', primary_key => 'id'});

    $post->child_relation($comment, {foreign_key => 'post_id', primary_key => 'id'});
    $comment->parent_relation($post, {foreign_key => 'post_id', primary_key => 'id'});
    $comment->parent_relation($user, {foreign_key => 'user_id', primary_key => 'id'});

    # where
    my $scope = $user->eq(id => 1);
    is $scope->to_sql, 'SELECT * FROM users WHERE id = ?';
    is_deeply [$scope->binds], [1];

    # multi where
    $scope = $user->eq(id => 1)->eq(name => 'test');
    is $scope->to_sql, 'SELECT * FROM users WHERE id = ? AND name = ?';
    is_deeply [$scope->binds], [1, 'test'];

    $scope = $user->eq(id => 1)->eq(id => 2);
    is $scope->to_sql, 'SELECT * FROM users WHERE id = ? AND id = ?';
    is_deeply [$scope->binds], [1,2];

    # join
    $scope = $user->joins($post);
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id';
    is_deeply [$scope->binds], [];

    # join 2
    $scope = $post->joins($user);
    is $scope->to_sql, 'SELECT posts.* FROM posts INNER JOIN users ON users.id = posts.user_id';
    is_deeply [$scope->binds], [];

    # join and where
    $scope = $user->joins($post)->eq(name => 'test');
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE users.name = ?';
    is_deeply [$scope->binds], ['test'];

    # join and multi where
    $scope = $user->joins($post)->eq(name => 'test')->eq(type => 0);
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE users.name = ? AND users.type = ?';
    is_deeply [$scope->binds], ['test', 0];

    # merge
    my $post_scope = $post->eq(title => 'hogehoge');
    $scope = $user->joins($post)->merge($post_scope);
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE posts.title = ?';
    is_deeply [$scope->binds], ['hogehoge'];

    # double merge
    $scope = $user->joins($post)->merge($user->eq(type => 1))->merge($post->eq(published => 1)->eq(deleted => 0));
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE users.type = ? AND posts.published = ? AND posts.deleted = ?';
    is_deeply [$scope->binds], [1, 1, 0];


    # operators eq, ne, in, not_in
    $scope = $user->eq(id => 1)->ne(hoge => 'hoge')->in(fuga => [1,2,3,4])->not_in(bura => [1,2,3,4,5,6,7,8,9]);
    is $scope->to_sql, 'SELECT * FROM users WHERE id = ? AND hoge != ? AND fuga IN (?, ?, ?, ?) AND bura NOT IN (?, ?, ?, ?, ?, ?, ?, ?, ?)';
    is_deeply [$scope->binds], [1, 'hoge', 1, 2, 3, 4, 1,2,3,4,5,6,7,8,9];

    # operators null, not_null
    $scope = $post->null('title')->not_null('description');
    is $scope->to_sql, 'SELECT * FROM posts WHERE title IS NULL AND description IS NOT NULL';
    is_deeply [$scope->binds], [];

    # operators gt, lt, ge, le
    $scope = $post->gt(created_at => '2010-10-10')->lt(updated_at => '2010-10-11')->ge(uid => 1)->le(uid => 10);
    is $scope->to_sql, 'SELECT * FROM posts WHERE created_at > ? AND updated_at < ? AND uid >= ? AND uid <= ?';
    is_deeply [$scope->binds], ['2010-10-10', '2010-10-11', 1, 10];

    # operators like, contains, starts_with, ends_with
    $scope = $user->like(profile => '_HOGE')->contains(name => 'AA')->starts_with(uid => '10')->ends_with(uid => '99');
    is $scope->to_sql, 'SELECT * FROM users WHERE profile LIKE ? AND name LIKE ? AND uid LIKE ? AND uid LIKE ?';
    is_deeply [$scope->binds], ['_HOGE', '%AA%', '10%', '%99'];

    # operator between
    $scope = $user->between('uid', 1, 100);
    is $scope->to_sql, 'SELECT * FROM users WHERE uid >= ? AND uid <= ?';
    is_deeply [$scope->binds], [1, 100];

    # select
    $scope = $user->select('id', 'name');
    is $scope->to_sql, 'SELECT id, name FROM users';
    is_deeply [$scope->binds], [];

    # join and select
    $scope = $user->joins($post)->select('id', 'name');
    is $scope->to_sql, 'SELECT users.id, users.name FROM users LEFT JOIN posts ON posts.user_id = users.id';
    is_deeply [$scope->binds], [];

    # multi table select
    $scope = $user->joins($post)->select('id', 'name')->merge($post->select('id', 'title'));
    is $scope->to_sql, 'SELECT users.id, users.name, posts.id, posts.title FROM users LEFT JOIN posts ON posts.user_id = users.id';
    is_deeply [$scope->binds], [];

    # limit offset
    $scope = $user->limit(10)->offset(20);
    is $scope->to_sql, 'SELECT * FROM users LIMIT 10 OFFSET 20';
    is_deeply [$scope->binds], [];

    # lock
    $scope = $user->lock;
    is $scope->to_sql, 'SELECT * FROM users FOR UPDATE';
    is_deeply [$scope->binds], [];

    # group
    $scope = $user->group('id');
    is $scope->to_sql, 'SELECT * FROM users GROUP BY id';
    is_deeply [$scope->binds], [];

    # order
    $scope = $user->desc('created_at')->asc('id');
    is $scope->to_sql, 'SELECT * FROM users ORDER BY created_at DESC, id';
    is_deeply [$scope->binds], [];

    # reorder
    $scope = $user->desc('created_at')->asc('id')->reorder->desc('id');
    is $scope->to_sql, 'SELECT * FROM users ORDER BY id DESC';
    is_deeply [$scope->binds], [];

    # join group
    $scope = $user->joins($post)->merge($post->group('type'))->group('id');
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id GROUP BY posts.type, users.id';
    is_deeply [$scope->binds], [];

    # join order
    $scope = $user->joins($post)->desc('created_at')->merge($post->asc('id'));
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id ORDER BY users.created_at DESC, posts.id';
    is_deeply [$scope->binds], [];

    # having
    # NOW, etc.. sql function
    $scope = $user->select(DBIx::ActiveRecord::Arel::Native->new('MAX(*)'))->group('type');
    is $scope->to_sql, 'SELECT MAX(*) FROM users GROUP BY type';
    is_deeply [$scope->binds], [];

    $scope = $user->select(DBIx::ActiveRecord::Arel::Native->new('MAX(*)'))->joins($post)->group('type');
    is $scope->to_sql, 'SELECT MAX(*) FROM users LEFT JOIN posts ON posts.user_id = users.id GROUP BY users.type';
    is_deeply [$scope->binds], [];

    # update
    $scope = $user->eq(id => 3);
    is $scope->update({hoge => 1}), 'UPDATE users SET hoge = ? WHERE id = ?';
    is_deeply [$scope->binds], [1,3];

    # insert
    is $user->insert({name => 'hoge', profile => 'hogehoge'}), 'INSERT INTO users (profile, name) VALUES (?, ?)';
    is_deeply [$user->binds], ['hogehoge', 'hoge'];

    # delete
    $scope = $user->in(id => [1,2,3]);
    is $scope->delete, 'DELETE FROM users WHERE id IN (?, ?, ?)';
    is_deeply [$scope->binds], [1,2,3];

    # where
    $scope = $user->where("id = ? and name = ?", 5, 'hoge');
    is $scope->to_sql, 'SELECT * FROM users WHERE id = ? and name = ?';
    is_deeply [$scope->binds], [5, 'hoge'];

    # join where
    $scope = $user->joins($post)->where("name = ?", 'fuga')->merge($post->where('name2 = ?', 'hoge')->eq(id => 45));
    is $scope->to_sql, 'SELECT users.* FROM users LEFT JOIN posts ON posts.user_id = users.id WHERE name = ? AND name2 = ? AND posts.id = ?';
    is_deeply [$scope->binds], ['fuga', 'hoge', 45];

    # count
    $scope = $user->eq(type => 'AA');
    is $scope->count, 'SELECT COUNT(*) FROM users WHERE type = ?';
    is_deeply [$scope->binds], ['AA'];

}

done_testing;