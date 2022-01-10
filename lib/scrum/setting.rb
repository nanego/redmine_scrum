# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

module Scrum
  class Setting

    %w(auto_update_pbi_status
       check_dependencies_on_pbi_sorting
       clear_new_tasks_assignee
       create_journal_on_pbi_position_change
       inherit_pbi_attributes
       pbi_is_closed_if_tasks_are_closed
       random_posit_rotation
       render_author_on_pbi
       render_category_on_pbi
       render_pbis_speed
       render_plugin_tips
       render_position_on_pbi
       render_tasks_speed
       render_updated_on_pbi
       render_version_on_pbi
       render_assigned_to_on_pbi
       show_project_totals_on_sprint
       show_project_totals_on_backlog
       sprint_burndown_day_zero
       use_remaining_story_points
       default_sprint_shared).each do |setting|
      src = <<-END_SRC
      def self.#{setting}
        setting_or_default_boolean(:#{setting})
      end
      def self.#{setting}?
        setting_or_default_boolean(:#{setting})
      end
      END_SRC
      class_eval src, __FILE__, __LINE__
    end

    %w(doer_color
       reviewer_color
       default_sprint_name).each do |setting|
      src = <<-END_SRC
      def self.#{setting}
        setting_or_default(:#{setting})
      end
      END_SRC
      class_eval src, __FILE__, __LINE__
    end

    %w(pbi_status_ids
       pbi_tracker_ids
       task_status_ids
       task_tracker_ids
       verification_activity_ids).each do |setting|
      src = <<-END_SRC
      def self.#{setting}
        collect_ids(:#{setting})
      end
      END_SRC
      class_eval src, __FILE__, __LINE__
    end

    %w(blocked_custom_field_id
       closed_pbi_status_id
       simple_pbi_custom_field_id
       story_points_custom_field_id
       doer_reviewer_postit_user_field_id).each do |setting|
      src = <<-END_SRC
      def self.#{setting}
        ::Setting.plugin_scrum[:#{setting}.to_s]
      end
      END_SRC
      class_eval src, __FILE__, __LINE__
    end

    module TrackerFields
      FIELDS = 'fields'
      CUSTOM_FIELDS = 'custom_fields'
      SPRINT_BOARD_FIELDS = 'sprint_board_fields'
      SPRINT_BOARD_CUSTOM_FIELDS = 'sprint_board_custom_fields'
    end

    def self.tracker_fields(tracker, type = TrackerFields::FIELDS)
      collect("tracker_#{tracker}_#{type}")
    end

    def self.tracker_field?(tracker, field, type = TrackerFields::FIELDS)
      tracker_fields(tracker, type).include?(field.to_s)
    end

    def self.sprint_board_fields
      [:status_id, :category_id, :fixed_version_id]
    end

    def self.task_tracker
      Tracker.all(task_tracker_ids)
    end

    def self.tracker_id_color(id)
      setting_or_default("tracker_#{id.to_s}_color")
    end

    def self.product_burndown_sprints
      setting_or_default_integer(:product_burndown_sprints, :min => 0)
    end

    def self.product_burndown_extra_sprints
      setting_or_default_integer(:product_burndown_extra_sprints, :min => 0)
    end

    def self.lowest_speed
      setting_or_default_integer(:lowest_speed, :min => 0, :max => 99)
    end

    def self.low_speed
      setting_or_default_integer(:low_speed, :min => 0, :max => 99)
    end

    def self.high_speed
      setting_or_default_integer(:high_speed, :min => 101, :max => 10000)
    end

    def self.default_sprint_days
      setting_or_default_integer(:default_sprint_days, :min => 1, :max => 20)
    end

  private

    def self.setting_or_default(setting)
      ::Setting.plugin_scrum[setting.to_s] || Redmine::Plugin::registered_plugins[:scrum].settings[:default][setting]
    end

    def self.setting_or_default_boolean(setting)
      setting_or_default(setting) == '1'
    end

    def self.setting_or_default_integer(setting, options = {})
      value = setting_or_default(setting).to_i
      value = options[:min] if options[:min] and value < options[:min]
      value = options[:max] if options[:max] and value > options[:max]
      value
    end

    def self.collect_ids(setting)
      (::Setting.plugin_scrum[setting.to_s] || []).collect{|value| value.to_i}
    end

    def self.collect(setting)
      (::Setting.plugin_scrum[setting.to_s] || [])
    end

  end
end
