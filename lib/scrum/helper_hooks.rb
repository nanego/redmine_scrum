# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

module Scrum
  class HelperHooks < Redmine::Hook::Listener

    def helper_issues_show_detail_after_setting(context)
      case context[:detail].property
      when "attr"
        case context[:detail].prop_key
        when "sprint_id"
          context[:detail][:value] = get_sprint_name(context[:detail].value)
          context[:detail][:old_value] = get_sprint_name(context[:detail].old_value)
        end
      end
    end

  private

    def get_sprint_name(id)
      sprint = Sprint.find(id.to_i)
      return sprint.name
    rescue
      return id
    end

  end
end
