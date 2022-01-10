# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class CreatePendingEfforts < ActiveRecord::Migration[4.2]
  class Issue < ActiveRecord::Base
  end
  class CustomValue < ActiveRecord::Base
  end
  class PendingEffort < ActiveRecord::Base
  end

  def self.up
    create_table :pending_efforts, :force => true do |t|
      t.column :issue_id,          :integer,                           :null => false
      t.column :date,              :date,                              :null => false
      t.column :effort,            :integer
    end

    add_index :pending_efforts, [:issue_id], :name => "pending_efforts_issue"
    add_index :pending_efforts, [:date], :name => "pending_efforts_date"

    if !((custom_field_id = Setting.plugin_scrum[:pending_effort_custom_field]).nil?)
      Issue.all.each do |issue|
        values = CustomValue.where(:customized_type => "Issue",
                                   :customized_id => issue.id,
                                   :custom_field_id => custom_field_id)
        if values.count == 1
          effort = PendingEffort.new(:issue_id => issue.id,
                                     :date => issue.updated_on,
                                     :effort => values.first.value.to_i)
          effort.save!
        end
      end
    end
  end

  def self.down
    drop_table :pending_efforts
  end
end
