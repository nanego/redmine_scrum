# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency 'application_helper'

module Scrum
  module ApplicationHelperPatch
    def self.included(base)
      base.class_eval do

        def link_to_sprint(sprint, include_project_prefix = false)
          if sprint.is_product_backlog?
            path = product_backlog_path(sprint)
          else
            path = sprint
          end
          label = h(sprint.name)
          label = "#{sprint.project.name}:#{label}" if include_project_prefix
          return link_to(label, path)
        end

        def link_to_sprint_stats(sprint, include_project_prefix = false)
          if sprint.is_product_backlog?
            return nil
          else
            path = stats_sprint_path(sprint)
            label = l(:label_sprint_stats_name, :name => sprint.name)
            label = "#{sprint.project.name}:#{label}" if include_project_prefix
            return link_to(label, path)
          end
        end

        def link_to_sprint_burndown(sprint, include_project_prefix = false)
          if sprint.is_product_backlog?
            label = l(:label_burndown, :name => sprint.name)
            path = burndown_product_backlog_path(sprint)
          else
            label = l(:label_sprint_burndown_chart_name, :name => sprint.name)
            path = burndown_sprint_path(sprint)
          end
          label = "#{sprint.project.name}:#{label}" if include_project_prefix
          return link_to(label, path)
        end

        def link_to_release_plan(sprint, include_project_prefix = false)
          unless sprint.is_product_backlog?
            return nil
          end
          label = l(:label_release_plan_name, :name => sprint.name)
          label = "#{project.name}:#{label}" if include_project_prefix
          return link_to(label, release_plan_product_backlog_path(sprint))
        end

        alias_method :parse_redmine_links_without_scrum, :parse_redmine_links
        def parse_redmine_links(text, default_project, obj, attr, only_path, options)
          result = parse_redmine_links_without_scrum(text, default_project, obj, attr, only_path, options)
          text.gsub!(%r{([\s\(,\-\[\>]|^)(!)?(([a-z0-9\-_]+):)?(sprint|burndown|stats|product\-backlog|release\-plan)?((#)((\d*)|(current|latest)))(?=(?=[[:punct:]][^A-Za-z0-9_/])|,|\s|\]|<|$)}) do |m|
            leading, project_identifier, element_type, separator, element_id_text = $1, $4, $5, $7, $8
            link = nil
            project = default_project
            if project_identifier
              project = Project.visible.find_by_identifier(project_identifier)
            end
            if project and element_type and element_id_text
              element_id = element_id_text.to_i
              include_project_prefix = (project != default_project)
              case element_type
                when 'sprint', 'burndown', 'stats', 'product-backlog', 'release-plan'
                  if ((element_id_text == 'latest') or (element_id_text == 'current'))
                    sprint = project.last_sprint
                  else
                    sprint = project.sprints_and_product_backlogs.find_by_id(element_id)
                  end
              end
              unless sprint.nil?
                case element_type
                  when 'sprint', 'product-backlog'
                    link = link_to_sprint(sprint, include_project_prefix)
                  when 'burndown'
                    link = link_to_sprint_burndown(sprint, include_project_prefix)
                  when 'stats'
                    link = link_to_sprint_stats(sprint, include_project_prefix)
                  when 'release-plan'
                    link = link_to_release_plan(sprint, include_project_prefix)
                end
              end
            end
            (leading + (link || "#{project_identifier}#{element_type}#{separator}#{element_id_text}"))
          end
          return result
        end

        def scrum_tips
          tips = []
          if Scrum::Setting.render_plugin_tips
            back_url = url_for(params.permit!)
            # Plugin permissions check.
            unless @project and !(@project.module_enabled?(:scrum))
              scrum_permissions = Redmine::AccessControl.modules_permissions(['scrum']).select{|p| p.project_module}.collect{|p| p.name}
              active_scrum_permissions = Role.all.collect{|r| r.permissions & scrum_permissions}.flatten
              if active_scrum_permissions.empty?
                tips << l(:label_tip_no_permissions,
                          :link => link_to(l(:label_tip_permissions_link), permissions_roles_path))
              end
            end
            # Minimal plugin settings check.
            plugin_settings_link = link_to(l(:label_tip_plugin_settings_link),
                                           plugin_settings_path(:id => :scrum))
            if Scrum::Setting.story_points_custom_field_id.blank?
              tips << l(:label_tip_no_plugin_setting, :link => plugin_settings_link,
                        :setting => l(:label_setting_story_points_custom_field))
            end
            if Scrum::Setting.pbi_tracker_ids.empty?
              tips << l(:label_tip_no_plugin_setting, :link => plugin_settings_link,
                        :setting => l(:label_pbi_plural))
            end
            if Scrum::Setting.task_tracker_ids.empty?
              tips << l(:label_tip_no_plugin_setting, :link => plugin_settings_link,
                        :setting => l(:label_task_plural))
            end
            if Scrum::Setting.task_status_ids.empty?
              tips << l(:label_tip_no_plugin_setting, :link => plugin_settings_link,
                        :setting => l(:label_setting_task_statuses))
            end
            if Scrum::Setting.pbi_status_ids.empty?
              tips << l(:label_tip_no_plugin_setting, :link => plugin_settings_link,
                        :setting => l(:label_setting_pbi_statuses))
            end
            # Project configuration checks.
            if @project and @project.persisted? and @project.module_enabled?(:scrum)
              product_backlog_link = link_to(l(:label_tip_product_backlog_link),
                                             project_product_backlog_index_path(@project))
              # At least one PB check.
              if @project.product_backlogs.empty?
                tips << l(:label_tip_no_product_backlogs,
                          :link => link_to(l(:label_tip_new_product_backlog_link),
                                           new_project_sprint_path(@project, :create_product_backlog => true,
                                                                   :back_url => back_url)))
              end
              # At least one Sprint check.
              if @project.sprints.empty?
                tips << l(:label_tip_no_sprints,
                          :link => link_to(l(:label_tip_new_sprint_link),
                                           new_project_sprint_path(@project, :back_url => back_url)))
              end
              # Product backlog (+release plan) checks.
              if @product_backlog and @product_backlog.persisted?
                # No PBIs check.
                if @product_backlog.pbis.empty?
                  tips << l(:label_tip_product_backlog_without_pbis, :link => product_backlog_link)
                end
                # Release plan checks.
                if params[:controller] == 'scrum' and params[:action] == 'release_plan'
                  # No versions check.
                  if @project.versions.empty?
                    tips << l(:label_tip_project_without_versions,
                              :link => link_to(l(:label_tip_new_version_link),
                                               new_project_version_path(@project, :back_url => back_url)))
                  end
                end
              end
              # Sprint checks.
              if @sprint and @sprint.persisted? and !(@sprint.is_product_backlog?)
                sprint_board_link = link_to(l(:label_tip_sprint_board_link),
                                            sprint_path(@sprint))
                there_are_simple_pbis = false
                there_are_only_simple_pbis = true
                @sprint.pbis.each do |pbi|
                  if pbi.is_simple_pbi?
                    there_are_simple_pbis = true
                  else
                    there_are_only_simple_pbis = false
                  end
                end
                # No PBIs check.
                if @sprint.pbis.empty?
                  tips << l(:label_tip_sprint_without_pbis, :sprint_board_link => sprint_board_link,
                            :product_backlog_link => product_backlog_link)
                end
                # No tasks check.
                if @sprint.tasks.empty? and not there_are_simple_pbis
                  tips << l(:label_tip_sprint_without_tasks, :link => sprint_board_link)
                end
                # Orphan tasks check.
                if (orphan_tasks = @sprint.orphan_tasks).any?
                  issues_link = orphan_tasks.collect{ |task|
                    link_to_issue(task, :subject => false, :tracker => false)
                  }.join(', ')
                  tips << l(:label_tip_sprint_with_orphan_tasks, :link => issues_link)
                end
                # No estimated effort check.
                if @sprint.efforts.empty? and not there_are_only_simple_pbis
                  tips << l(:label_tip_sprint_without_efforts,
                            :link => link_to(l(:label_tip_sprint_effort_link),
                                             edit_effort_sprint_path(@sprint, :back_url => back_url)))
                end
                # No project members on edit Sprint effort view.
                if @project.members.empty? and params[:action].to_s == 'edit_effort'
                  tips << l(:label_tip_project_without_members,
                            :link => link_to(l(:label_tip_project_members_link),
                                             settings_project_path(@project, :tab => :members)))
                end
              end
            end
          end
          return tips
        end

        def render_time(time, unit, options = {})
          if time.nil?
            ''
          else
            if time.is_a?(Integer)
              text = ("%d" % time) unless options[:ignore_zero] and time == 0
            elsif time.is_a?(Float)
              text = ("%g" % time) unless options[:ignore_zero] and time == 0.0
            else
              text = time unless options[:ignore_zero] and (time.blank? or (time == '0'))
            end
            unless text.blank?
              text = "#{text}#{options[:space_unit] ? ' ' : ''}#{unit}"
              unless options[:link].nil?
                text = link_to(text, options[:link])
              end
              render :inline => "<span title=\"#{options[:title]}\">#{text}</span>"
            end
          end
        end

        def render_hours(hours, options = {})
          render_time(hours, 'h', options)
        end

        def render_sps(sps, options = {})
          render_time(sps, l(:label_story_point_unit), options)
        end

        def render_scrum_help(unique_id = nil)
          template = nil
          case params[:controller].to_sym
          when :sprints
            case params[:action].to_sym
            when :show
              template = 'sprint/board'
            when :burndown
              template = (params[:type] and (params[:type] == 'sps')) ?
                         'sprint/burndown_sps' : 'sprint/burndown_effort'
            when :stats
              template = 'sprint/stats'
            when :new, :edit
              template = params[:create_product_backlog] ? 'product_backlog/form' : 'sprint/form'
            when :edit_effort
              template = 'sprint/edit_effort'
            end
          when :product_backlog
            case params[:action].to_sym
            when :show
              template = 'product_backlog/board'
            when :burndown
              template = 'product_backlog/burndown'
            when :release_plan
              template = 'product_backlog/release_plan'
            end
          when :scrum
            case params[:action].to_sym
            when :stats
              template = 'scrum/stats'
            end
          when :projects
            case params[:action].to_sym
            when :settings
              if unique_id == 'sprints'
                template = 'project_settings/sprints'
              elsif unique_id == 'product_backlogs'
                template = 'project_settings/product_backlogs'
              end
            end
          when :settings
            case params[:action].to_sym
            when :plugin
              case params[:id].to_sym
              when :scrum
                template = 'scrum/settings'
              end
            end
          end
          unless template.nil?
            links = {}
            links[:plugin_settings] = link_to(l(:label_tip_plugin_settings_link),
                                              plugin_settings_path(:id => :scrum))
            links[:permissions] = link_to(l(:label_tip_permissions_link),
                                          permissions_roles_path)
            links[:sprint_effort] = link_to(l(:label_tip_sprint_effort_link),
                                            edit_effort_sprint_path(@sprint,
                                                                    :back_url => url_for(params.permit!))) if @sprint and not @sprint.new_record?
          end
          return template.nil? ? '' : render(:partial => 'help/help',
                                             :formats => [:html],
                                             :locals => {:template => template,
                                                         :unique_id => unique_id,
                                                         :links => links})
        end

      end
    end
  end
end
