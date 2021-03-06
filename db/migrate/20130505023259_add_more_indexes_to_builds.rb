class AddMoreIndexesToBuilds < ActiveRecord::Migration
  def up
     execute <<-SQL
      CREATE INDEX CONCURRENTLY index_builds_on_repository_id_and_event_type_and_state_and_branch
        ON builds(repository_id, event_type, state, branch);
    SQL
  end

  def down
    execute "DROP INDEX CONCURRENTLY index_builds_on_repository_id_and_event_type_and_state_and_branch"
  end
end
