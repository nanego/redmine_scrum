# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class UpdateSprintsDateConstraints < ActiveRecord::Migration[4.2]
  def self.up
    change_column :sprints, :sprint_start_date, :date, :null => true
    change_column :sprints, :sprint_end_date, :date, :null => true
    Sprint.where(:is_product_backlog => true).update_all(:sprint_start_date => nil, :sprint_end_date => nil)
  end

  def self.down
    Sprint.where(:sprint_start_date => nil).update_all(:sprint_start_date => Time.now)
    Sprint.where(:sprint_end_date => nil).update_all(:sprint_end_date => Time.now)
    change_column :sprints, :sprint_start_date, :date, :null => false
    change_column :sprints, :sprint_end_date, :date, :null => false
  end
end
