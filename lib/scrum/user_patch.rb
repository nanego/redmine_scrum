# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency "user"

module Scrum
  module UserPatch
    def self.included(base)
      base.class_eval do

        has_many :sprint_efforts, :dependent => :destroy

        def has_alias?
          return ((!((custom_field_id = Scrum::Setting.doer_reviewer_postit_user_field_id).nil?)) and
                  visible_custom_field_values.collect{|value| value.custom_field.id.to_s}.include?(custom_field_id))
        end

        def alias
          if has_alias? and
              !((custom_field_id = Scrum::Setting.doer_reviewer_postit_user_field_id).nil?) and
              !((custom_value = self.custom_value_for(custom_field_id)).nil?) and
              !((value = custom_value.value).blank?)
            return value
          end
        end

      end
    end
  end
end
