# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class AddIssuesPosition < ActiveRecord::Migration
  def self.up
    add_column :issues, :position, :integer
    add_index :issues, [:position], :name => "issues_position"
  end

  def self.down
    remove_column :issues, :position
  end
end
