# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class AddSprintsShared < ActiveRecord::Migration
  def self.up
    add_column :sprints, :shared, :boolean, :default => false
    add_index :sprints, [:shared], :name => "sprints_shared"
  end

  def self.down
    remove_column :sprints, :shared
  end
end
