# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

module ScrumHelper

  include ProjectsHelper

  def render_pbi_left_header(pbi)
    parts = []
    if Scrum::Setting.render_position_on_pbi
      parts << "#{l(:field_position)}: #{pbi.position}"
    end
    if Scrum::Setting.render_category_on_pbi and pbi.category
      parts << "#{l(:field_category)}: #{h(pbi.category.name)}"
    end
    if Scrum::Setting.render_version_on_pbi and pbi.fixed_version
      parts << "#{l(:field_fixed_version)}: #{link_to_version(pbi.fixed_version)}"
    end
    render :inline => parts.join(", ")
  end

  def render_pbi_right_header(pbi)
    parts = []
    if Scrum::Setting.render_author_on_pbi
      parts << authoring(pbi.created_on, pbi.author)
    end
    if Scrum::Setting.render_assigned_to_on_pbi and pbi.assigned_to
      parts << "#{l(:field_assigned_to)}: #{link_to_user(pbi.assigned_to)}"
    end
    if Scrum::Setting.render_updated_on_pbi and pbi.created_on != pbi.updated_on
      parts << "#{l(:label_updated_time, time_tag(pbi.updated_on))}"
    end
    render :inline => parts.join(", ")
  end

  def render_issue_icons(issue)
    icons = []
    if (User.current.allowed_to?(:view_time_entries, issue.project) and
        ((issue.is_pbi? and Scrum::Setting.render_pbis_speed) or
         (issue.is_task? and Scrum::Setting.render_tasks_speed)) and
        (speed = issue.speed))
      if speed <= Scrum::Setting.lowest_speed
        icons << render_issue_speed_icon(LOWEST_SPEED_ICON, speed)
      elsif speed <= Scrum::Setting.low_speed
        icons << render_issue_speed_icon(LOW_SPEED_ICON, speed)
      elsif speed >= Scrum::Setting.high_speed
        icons << render_issue_speed_icon(HIGH_SPEED_ICON, speed)
      end
    end
    icons << render_issue_icon(BLOCKED_ICON, l(:label_blocked)) if issue.scrum_blocked?
    render :inline => icons.compact.join(' ')
  end

  def project_selector_tree(project, indent = '')
    options = [["#{indent}#{project.name}", project.id]]
    project.children.visible.each do |child_project|
      options += project_selector_tree(child_project, indent + '» ')
    end
    return options
  end

  DEVIATION_ICONS = [LOWEST_SPEED_ICON = "icon-major-deviation",
                     LOW_SPEED_ICON = "icon-minor-deviation",
                     HIGH_SPEED_ICON = "icon-below-deviation"]
  BLOCKED_ICON = "icon-blocked"

private

def render_issue_icon(icon, title = nil)
  link_to("", "#", :class => "icon float-icon #{icon}", :title => title)
end

def render_issue_speed_icon(icon, speed)
  render_issue_icon(icon, l(:label_issue_speed, :speed => speed))
end

end
