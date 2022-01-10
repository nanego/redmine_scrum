# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ChangeSprintsDates < ActiveRecord::Migration[4.2]
  def self.up
    rename_column :sprints, :start_date, :sprint_start_date
    rename_column :sprints, :end_date, :sprint_end_date
  end

  def self.down
    rename_column :sprints, :sprint_start_date, :start_date
    rename_column :sprints, :sprint_end_date, :end_date
  end
end