# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ChangeSprintEffortsEffort < ActiveRecord::Migration[4.2]
  def self.up
    change_column :sprint_efforts, :effort, :float
  end

  def self.down
    change_column :sprint_efforts, :effort, :integer
  end
end