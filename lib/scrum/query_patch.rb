# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency 'query'

module Scrum
  module QueryPatch
    def self.included(base)
      base.class_eval do

        def sprints(options = {})
          Sprint
              .joins(:project)
              .includes(:project)
              .where(Query.scrum_merge_conditions(project_statement, options[:conditions]))
        rescue ::ActiveRecord::StatementInvalid => e
          raise StatementInvalid.new(e.message)
        end

        # Deprecated method from Rails 2.3.X.
        def self.scrum_merge_conditions(*conditions)
          segments = []

          conditions.each do |condition|
            unless condition.blank?
              sql = sanitize_sql(condition)
              segments << sql unless sql.blank?
            end
          end

          "(#{segments.join(') AND (')})" unless segments.empty?
        end

      end
    end
  end
end
