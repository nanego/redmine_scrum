# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class AddSprintsStatus < ActiveRecord::Migration[4.2]
  def self.up
    add_column :sprints, :status, :string, :limit => 10, :default => "open"
    add_index :sprints, [:status], :name => "sprints_status"
  end

  def self.down
    remove_column :sprints, :status
  end
end
