# encoding: UTF-8

# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

# This plugin should be reloaded in development mode.
if (Rails.env == 'development')
  ActiveSupport::Dependencies.autoload_once_paths.reject!{|x| x =~ /^#{Regexp.escape(File.dirname(__FILE__))}/}
end

ApplicationHelper.send(:include, Scrum::ApplicationHelperPatch)
CalendarsController.send(:include, Scrum::CalendarsControllerPatch)
Issue.send(:include, Scrum::IssuePatch)
IssueQuery.send(:include, Scrum::IssueQueryPatch)
IssuesController.send(:include, Scrum::IssuesControllerPatch)
IssueStatus.send(:include, Scrum::IssueStatusPatch)
Journal.send(:include, Scrum::JournalPatch)
Project.send(:include, Scrum::ProjectPatch)
ProjectsHelper.send(:include, Scrum::ProjectsHelperPatch)
Query.send(:include, Scrum::QueryPatch)
Tracker.send(:include, Scrum::TrackerPatch)
User.send(:include, Scrum::UserPatch)

require_dependency 'scrum/helper_hooks'
require_dependency 'scrum/view_hooks'

Redmine::Plugin.register :scrum do
  name              'Scrum Redmine plugin'
  author            'Emilio González Montaña'
  description       'This plugin for Redmine allows to follow Scrum methodology with Redmine projects'
  version           '0.21.0'
  url               'https://redmine.ociotec.com/projects/redmine-plugin-scrum'
  author_url        'http://ociotec.com'
  requires_redmine  :version_or_higher => '4.0.0'

  project_module    :scrum do
    permission      :manage_sprints,
                    {:sprints => [:new, :create, :edit, :update, :destroy, :edit_effort, :update_effort]},
                    :require => :member
    permission      :view_sprint_board,
                    {:sprints => [:index, :show]}
    permission      :edit_sprint_board,
                    {:sprints => [:change_issue_status, :sort],
                     :scrum => [:change_story_points, :change_remaining_story_points,
                                :change_pending_effort, :change_assigned_to,
                                :new_pbi, :create_pbi, :edit_pbi, :update_pbi,
                                :new_task, :create_task, :edit_task, :update_task]},
                    :require => :member
    permission      :sort_sprint_board,
                    {:sprints => [:sort]},
                    :require => :member
    permission      :view_sprint_burndown,
                    {:sprints => [:burndown_index, :burndown]}
    permission      :view_sprint_stats, {:sprints => [:stats_index, :stats]}
    permission      :view_sprint_stats_by_member, {}
    permission      :view_product_backlog,
                    {:product_backlog => [:index, :show, :check_dependencies]}
    permission      :edit_product_backlog,
                    {:product_backlog => [:new_pbi, :create_pbi],
                     :scrum => [:edit_pbi, :update_pbi]},
                    :require => :member
    permission      :sort_product_backlog,
                    {:product_backlog => [:sort],
                     :scrum => [:move_pbi]},
                    :require => :member
    permission      :view_product_backlog_burndown,
                    {:product_backlog => [:burndown]}
    permission      :view_release_plan,
                    {:product_backlog => [:release_plan]}
    permission      :view_scrum_stats,
                    {:scrum => [:stats]}
    permission      :view_pending_effort,
                    {}
    permission      :edit_pending_effort,
                    {:scrum => [:change_pending_effort, :change_pending_efforts,
                                :change_story_points, :change_remaining_story_points]},
                    :require => :member
    permission      :view_remaining_story_points,
                    {}
    permission      :edit_remaining_story_points,
                    {:scrum => [:change_remaining_story_points]},
                    :require => :member
  end

  menu              :project_menu, :product_backlog, {:controller => :product_backlog, :action => :index},
                    :caption => :label_menu_product_backlog, :after => :activity, :param => :project_id
  menu              :project_menu, :sprint, {:controller => :sprints, :action => :index},
                    :caption => :label_menu_sprint, :after => :activity, :param => :project_id

  settings          :default => {:create_journal_on_pbi_position_change => '0',
                                 :doer_color => 'post-it-color-5',
                                 :pbi_status_ids => [],
                                 :pbi_tracker_ids => [],
                                 :reviewer_color => 'post-it-color-3',
                                 :doer_reviewer_postit_user_field_id => nil,
                                 :story_points_custom_field_id => nil,
                                 :blocked_custom_field_id => nil,
                                 :simple_pbi_custom_field_id => nil,
                                 :task_status_ids => [],
                                 :task_tracker_ids => [],
                                 :auto_update_pbi_status => '1',
                                 :closed_pbi_status_id => nil,
                                 :clear_new_tasks_assignee => '1',
                                 :verification_activity_ids => [],
                                 :inherit_pbi_attributes => '1',
                                 :random_posit_rotation => '1',
                                 :render_position_on_pbi => '0',
                                 :render_category_on_pbi => '1',
                                 :render_version_on_pbi => '1',
                                 :render_author_on_pbi => '1',
                                 :render_assigned_to_on_pbi => '0',
                                 :render_updated_on_pbi => '0',
                                 :check_dependencies_on_pbi_sorting => '0',
                                 :product_burndown_sprints => '4',
                                 :render_pbis_speed => '1',
                                 :render_tasks_speed => '1',
                                 :lowest_speed => 70,
                                 :low_speed => 80,
                                 :high_speed => 140,
                                 :render_plugin_tips => '1',
                                 :sprint_burndown_day_zero => '1',
                                 :pbi_is_closed_if_tasks_are_closed => '0',
                                 :show_project_totals_on_sprint => '0',
                                 :show_project_totals_on_backlog => '0',
                                 :use_remaining_story_points => '0',
                                 :product_burndown_extra_sprints => 3,
                                 :default_sprint_name => 'Sprint 1',
                                 :default_sprint_days => 10,
                                 :default_sprint_shared => '1'},
                    :partial => 'settings/scrum_settings'
end
