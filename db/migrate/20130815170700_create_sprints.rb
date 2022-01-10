# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class CreateSprints < ActiveRecord::Migration[4.2]
  def self.up
    create_table :sprints, :force => true do |t|
      t.column :name,             :string,                            :null => false
      t.column :description,      :text
      t.column :start_date,       :date,                              :null => false
      t.column :end_date,         :date,                              :null => false
      t.column :user_id,          :integer,                           :null => false
      t.column :project_id,       :integer,                           :null => false
      t.column :created_on,       :datetime
      t.column :updated_on,       :datetime
    end

    add_index :sprints, [:name], :name => "sprints_name"
    add_index :sprints, [:user_id], :name => "sprints_user"
    add_index :sprints, [:project_id], :name => "sprints_project"
  end

  def self.down
    drop_table :sprints
  end
end
