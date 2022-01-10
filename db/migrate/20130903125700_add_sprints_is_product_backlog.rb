# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class AddSprintsIsProductBacklog < ActiveRecord::Migration[4.2]
  class Sprint < ActiveRecord::Base
    belongs_to :project
  end
  class Project < ActiveRecord::Base
    belongs_to :product_backlog, :class_name => "Sprint"
    has_many :sprints
  end

  def self.up
    add_column :sprints, :is_product_backlog, :boolean, :default => false
    add_index :sprints, [:is_product_backlog], :name => "sprints_is_product_backlog"
    Sprint.all.each do |sprint|
      is_product_backlog = (!(sprint.project.nil?))
      is_product_backlog &&= (!(sprint.project.product_backlog.nil?))
      is_product_backlog &&= (sprint.project.product_backlog == sprint)
      sprint.is_product_backlog = is_product_backlog
      sprint.save!
    end
  end

  def self.down
    remove_column :sprints, :is_product_backlog
  end
end
