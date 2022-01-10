# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency "project"

module Scrum
  module ProjectPatch
    def self.included(base)
      base.class_eval do

        has_many :product_backlogs, -> { where(:is_product_backlog => true).order('name ASC') },
                 :class_name => 'Sprint'
        has_many :sprints, -> { where(:is_product_backlog => false).order('sprint_start_date ASC, name ASC') },
                 :dependent => :destroy
        has_many :sprints_and_product_backlogs, -> { order('sprint_start_date ASC, name ASC') },
                 :class_name => 'Sprint', :dependent => :destroy
        has_many :open_sprints_and_product_backlogs, -> { where(:status => 'open').order('sprint_start_date ASC, name ASC') },
                 :class_name => 'Sprint', :dependent => :destroy

        def last_sprint
          sprints.last
        end

        def current_sprint
          today = Date.today
          current_sprint = sprints.where('sprint_start_date <= ?', today)
                                  .where('sprint_end_date >= ?', today).last
          current_sprint ? current_sprint : last_sprint
        end

        def story_points_per_sprint(options = {})
          max_sprints_count = self.sprints.length
          last_sprints_count = Scrum::Setting.product_burndown_sprints
          last_sprints_count = max_sprints_count if last_sprints_count == 0
          i = max_sprints_count - 1
          sprints_count = 0
          story_points_per_sprint = 0.0
          scheduled_story_points_per_sprint = 0.0
          today = Date.today
          while (sprints_count < last_sprints_count and i >= 0)
            story_points = self.sprints[i].story_points(options)
            scheduled_story_points = self.sprints[i].scheduled_story_points(options)
            sprint_end_date = self.sprints[i].sprint_end_date
            unless story_points.nil? or scheduled_story_points.nil? or (sprint_end_date >= today)
              story_points_per_sprint += story_points
              scheduled_story_points_per_sprint += scheduled_story_points
              sprints_count += 1
            end
            i -= 1
          end
          story_points_per_sprint = filter_story_points(story_points_per_sprint, sprints_count)
          scheduled_story_points_per_sprint = filter_story_points(scheduled_story_points_per_sprint, sprints_count)
          return [story_points_per_sprint, scheduled_story_points_per_sprint,
                  (Scrum::Setting.product_burndown_sprints == 0) ? 0 : sprints_count]
        end

        def closed_story_points_per_sprint
          return value_per_sprint(:closed_story_points,
                                  :label_closed_story_points)
        end

        def hours_per_story_point
          return value_per_sprint(:hours_per_story_point,
                                  :label_hours_per_story_point)
        end

        def sps_by_category
          sps_by_pbi_field(:category, :sps_by_pbi_category)
        end

        def sps_by_pbi_type
          sps_by_pbi_field(:tracker, :sps_by_pbi_type)
        end

        def effort_by_activity
          sps_by_pbi_field(:activity, :time_entries_by_activity)
        end

        def all_open_sprints_and_product_backlogs(only_shared = false)
          # Get this project Sprints.
          conditions = {}
          conditions[:shared] = true if only_shared
          all_sprints = scrum? ? open_sprints_and_product_backlogs.where(conditions).to_a : []
          # If parent try to recursively add shared Sprints from parents.
          unless parent.nil?
            all_sprints += parent.all_open_sprints_and_product_backlogs(true)
          end
          return all_sprints
        end

        def scrum?
          is_scrum = module_enabled?(:scrum)
          is_scrum = parent.scrum? unless is_scrum or parent.nil?
          return is_scrum
        end

        def pbis_count(filters)
          return pbis(filters).count
        end

        def closed_pbis_count(filters)
          return pbis(filters).select {|pbi| pbi.scrum_closed?}.count
        end

        def total_sps(filters)
          return pbis(filters).collect {|pbi| pbi.story_points.to_f || 0.0}.sum
        end

        def closed_sps(filters)
          return pbis(filters).collect {|pbi| pbi.closed_story_points}.sum
        end

      private

        def pbis(filters)
          the_filters = filters ? filters.clone : {}
          the_filters[:filter_by_project] = Integer(the_filters[:filter_by_project]) rescue nil
          filter_conditions = {}
          filter_conditions[:project_id] = the_filters[:filter_by_project] if the_filters[:filter_by_project]
          Issue.visible.includes(:custom_values).where(pbis_conditons(the_filters)).where(filter_conditions)
        end

        def pbis_conditons(filters)
          conditions = []
          conditions << self.project_condition(::Setting.display_subprojects_issues?) unless filters[:filter_by_project]
          conditions << "(tracker_id IN (#{Tracker.pbi_trackers(self).collect {|tracker| tracker.id}.join(', ')}))"
          return conditions.join(' AND ')
        end

        def filter_story_points(story_points, sprints_count)
          story_points /= sprints_count if story_points > 0 and sprints_count > 0
          story_points = 1 if story_points == 0
          story_points = story_points.round(2)
          return story_points
        end

        def sps_by_pbi_field(field, method)
          results = {}
          total = 0.0
          all_sprints = sprints_and_product_backlogs
          all_sprints.each do |sprint|
            sprint_results, sprint_total = sprint.send(method)
            sprint_results.each do |result|
              if !results.key?(result[field])
                results[result[field]] = 0.0
              end
              results[result[field]] += result[:total]
            end
            total += sprint_total
          end
          new_results = []
          results.each_pair{|key, value|
            new_results << {field => key,
                            :total => value,
                            :percentage => total ? ((value * 100.0) / total).round(2) : 0.0}
          }
          [new_results, total]
        end

        def value_per_sprint(sprint_method, label_value)
          results = {}
          media = 0.0
          sprints_to_use = sprints
          max_sprints_count = sprints_to_use.count
          last_sprints_count = Scrum::Setting.product_burndown_sprints
          last_sprints_count = max_sprints_count if last_sprints_count == 0
          last_sprints_count = sprints_to_use.count if last_sprints_count > sprints_to_use.count
          sprints_to_use.each_with_index { |sprint, i|
            value = sprint.send(sprint_method)
            results[sprint.name] = value
            if i >= max_sprints_count - last_sprints_count
              media += value
            end
          }
          media = (media / last_sprints_count).round(2) if last_sprints_count > 0
          results[l(:label_media_last_n_sprints, :n => last_sprints_count)] = media
          return {l(label_value) => results}
        end

      end
    end
  end
end
