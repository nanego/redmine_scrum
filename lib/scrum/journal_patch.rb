# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency "journal"

module Scrum
  module JournalPatch
    def self.included(base)
      base.class_eval do

      private

        def add_attribute_detail_with_scrum(attribute, old_value, value)
          if Scrum::Setting.create_journal_on_pbi_position_change or (attribute != 'position')
            add_attribute_detail_without_scrum(attribute, old_value, value)
          end
        end
        alias_method_chain :add_attribute_detail, :scrum

      end
    end
  end
end
