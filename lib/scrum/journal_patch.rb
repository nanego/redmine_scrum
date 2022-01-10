# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency "journal"

module Scrum
  module JournalPatch
    def self.included(base)
      base.class_eval do

      private

      alias_method :add_attribute_detail_without_scrum, :add_attribute_detail
        def add_attribute_detail(attribute, old_value, value)
          if Scrum::Setting.create_journal_on_pbi_position_change or (attribute != 'position')
            add_attribute_detail_without_scrum(attribute, old_value, value)
          end
        end

      end
    end
  end
end
