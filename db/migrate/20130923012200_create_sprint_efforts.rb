# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class CreateSprintEfforts < ActiveRecord::Migration[4.2]
  def self.up
    create_table :sprint_efforts, :force => true do |t|
      t.column :sprint_id,        :integer,                           :null => false
      t.column :user_id,          :integer,                           :null => false
      t.column :date,             :date,                              :null => false
      t.column :effort,           :integer
    end

    add_index :sprint_efforts, [:sprint_id], :name => "sprint_efforts_sprint"
    add_index :sprint_efforts, [:user_id], :name => "sprint_efforts_user"
    add_index :sprint_efforts, [:date], :name => "sprint_efforts_date"
  end

  def self.down
    drop_table :sprint_efforts
  end
end
