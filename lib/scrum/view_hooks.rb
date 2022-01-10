# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

module Scrum
  class ViewHooks < Redmine::Hook::ViewListener

    render_on(:view_issues_bulk_edit_details_bottom, :partial => 'scrum_hooks/issues/bulk_edit')
    render_on(:view_issues_context_menu_start,       :partial => 'scrum_hooks/context_menus/issues')
    render_on(:view_issues_form_details_bottom,      :partial => 'scrum_hooks/issues/form')
    render_on(:view_issues_show_details_bottom,      :partial => 'scrum_hooks/issues/show')
    render_on(:view_layouts_base_html_head,          :partial => 'scrum_hooks/head')
    render_on(:view_layouts_base_sidebar,            :partial => 'scrum_hooks/scrum_tips')
    render_on(:view_projects_show_sidebar_bottom,    :partial => 'scrum_hooks/projects/show_sidebar')

  end
end
