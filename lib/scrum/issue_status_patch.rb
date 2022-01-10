# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency "issue_status"

module Scrum
  module IssueStatusPatch
    def self.included(base)
      base.class_eval do

        def self.task_statuses
          IssueStatus.where(:id => Scrum::Setting.task_status_ids).order("position ASC")
        end

        def self.pbi_statuses
          IssueStatus.where(:id => Scrum::Setting.pbi_status_ids).order("position ASC")
        end

        def self.closed_status_ids
          IssueStatus.where(:is_closed => true).collect{|status| status.id}
        end

      end
    end
  end
end
