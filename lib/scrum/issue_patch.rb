# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency 'issue'

module Scrum
  module IssuePatch
    def self.included(base)
      base.class_eval do

        belongs_to :sprint
        has_many :pending_efforts, -> { order('date ASC') }

        safe_attributes :sprint_id, :if => lambda { |issue, user|
          issue.project and issue.project.scrum? and user.allowed_to?(:edit_issues, issue.project)
        }

        before_save :update_position, :if => lambda { |issue|
          issue.project and issue.project.scrum? and issue.sprint_id_changed? and issue.is_pbi?
        }
        before_save :update_pending_effort, :if => lambda { |issue|
          issue.project and issue.project.scrum? and issue.status_id_changed? and issue.is_task?
        }
        before_save :update_assigned_to, :if => lambda { |issue|
          issue.project and issue.project.scrum? and issue.status_id_changed? and issue.is_task?
        }
        before_save :update_parent_pbi, :if => lambda { |issue|
          issue.project and issue.project.scrum? and Scrum::Setting.auto_update_pbi_status and
          (issue.status_id_changed? or issue.new_record?) and
          issue.is_task? and !issue.parent_id.nil?
        }
        before_save :update_parent_pbi_on_closed_tasks, :if => lambda { |issue|
          issue.project and issue.project.scrum? and Scrum::Setting.closed_pbi_status_id and
          (issue.status_id_changed? or issue.new_record?) and
          issue.is_task? and !issue.parent_id.nil? and !issue.parent.closed?
        }

        def scrum_closed?
          closed = self.closed?
          if !closed and is_pbi? and self.children.any? and
             Scrum::Setting.pbi_is_closed_if_tasks_are_closed?
            closed = true
            self.children.each do |task|
              if !task.closed?
                closed = false
                break # at least a task opened, no need to go further
              end
            end
          end
          return closed
        end

        def closed_on_for_burndown
          completed_date = nil
          closed_statuses = IssueStatus::closed_status_ids
          if self.closed?
            self.journals.order('created_on DESC').each do |journal|
              journal.details.where(:prop_key => 'status_id',
                                    :value => closed_statuses).each do |detail|
                completed_date = journal.created_on
              end
              break unless completed_date.nil?
            end
          end
          if self.is_pbi? and self.children.any? and
             Scrum::Setting.pbi_is_closed_if_tasks_are_closed
            all_tasks_closed = true
            last_closed_task_date = completed_date
            self.children.each do |task|
              if all_tasks_closed and task.closed?
                task_closed_on = task.closed_on_for_burndown
                if task_closed_on
                  if last_closed_task_date.nil? or
                     last_closed_task_date > task_closed_on
                    last_closed_task_date = task_closed_on
                  end
                end
              else
                all_tasks_closed = false
              end
            end
            if all_tasks_closed and last_closed_task_date
              completed_date = last_closed_task_date
            end
          end
          return completed_date
        end

        def has_story_points?
          ((!((custom_field_id = Scrum::Setting.story_points_custom_field_id).nil?)) and
           visible_custom_field_values.collect{|value| value.custom_field.id.to_s}.include?(custom_field_id) and
           self.is_pbi?)
        end

        def story_points
          if has_story_points? and
             !((custom_field_id = Scrum::Setting.story_points_custom_field_id).nil?) and
             !((custom_value = self.custom_value_for(custom_field_id)).nil?) and
             !((value = custom_value.value).blank?)
            # Replace invalid float number separator (i.e. 0,5) with valid separator (i.e. 0.5)
            value.gsub(',', '.').to_f
          end
        end

        def story_points=(value)
          if has_story_points? and
             !((custom_field_id = Scrum::Setting.story_points_custom_field_id).nil?) and
             !((custom_value = self.custom_value_for(custom_field_id)).nil?) and
             custom_value.custom_field.valid_field_value?(value)
            custom_value.value = value
            custom_value.save!
          else
            raise
          end
        end

        def closed_story_points
          value = 0.0
          if self.scrum_closed? and self.has_story_points?
            value = self.story_points.to_f
          elsif self.has_story_points? and
                self.has_remaining_story_points? and
            sps = self.story_points
            remaining_sps = self.remaining_story_points
            unless sps.nil? or remaining_sps.nil?
              value = (sps - remaining_sps).to_f
              value = 0.0 if value < 0
            end
          end
          return value
        end

        def scheduled?
          is_scheduled = false
          if created_on and sprint and sprint.sprint_start_date
            if is_pbi?
              is_scheduled = created_on < sprint.sprint_start_date
            elsif is_task?
              is_scheduled = created_on <= sprint.sprint_start_date
            end
          end
          return is_scheduled
        end

        def use_in_burndown?
          is_task? and IssueStatus.task_statuses.include?(status) and
          parent and parent.is_pbi? and IssueStatus.pbi_statuses.include?(parent.status)
        end

        def is_pbi?
          self.tracker.is_pbi?
        end

        def is_complex_pbi?
          self.is_pbi? and not self.is_simple_pbi?
        end

        def is_simple_pbi?
          self.is_pbi? and
          !((custom_field_id = Scrum::Setting.simple_pbi_custom_field_id).nil?) and
          !((custom_value = self.custom_value_for(custom_field_id)).nil?) and
          (custom_value.value == '1')
        end

        def is_task?
          tracker.is_task?
        end

        def tasks_by_status_id
          raise 'Issue is not an user story' unless is_pbi?
          statuses = {}
          IssueStatus.task_statuses.each do |status|
            statuses[status.id] = children.select{|issue| (issue.status == status) and issue.visible?}
          end
          statuses
        end

        def doers
          users = []
          users << assigned_to unless assigned_to.nil?
          time_entries = TimeEntry.where(:issue_id => id,
                                         :activity_id => Issue.doing_activities_ids)
          users.concat(time_entries.collect{|t| t.user}).uniq.sort
        end

        def reviewers
          users = []
          time_entries = TimeEntry.where(:issue_id => id,
                                         :activity_id => Issue.reviewing_activities_ids)
          users.concat(time_entries.collect{|t| t.user}).uniq.sort
        end

        def sortable?()
          is_sortable = false
          if is_pbi? and editable? and sprint and
             ((User.current.allowed_to?(:edit_product_backlog, project) and (sprint.is_product_backlog?)) or
              (User.current.allowed_to?(:edit_sprint_board, project) and (!(sprint.is_product_backlog?))))
            is_sortable = true
          elsif is_task? and editable? and sprint and
                User.current.allowed_to?(:edit_sprint_board, project) and !sprint.is_product_backlog?
            is_sortable = true
          end
          return is_sortable
        end

        def post_it_css_class(options = {})
          classes = ['post-it', 'big-post-it', tracker.post_it_css_class]
          if is_pbi?
            classes << 'sprint-pbi'
            if options[:draggable] and editable? and sprint
              if User.current.allowed_to?(:edit_product_backlog, project) and sprint.is_product_backlog?
                classes << 'post-it-vertical-move-cursor'
              elsif User.current.allowed_to?(:edit_sprint_board, project) and !(sprint.is_product_backlog?) and
                    is_simple_pbi?
                classes << 'post-it-horizontal-move-cursor'
              end
            end
          elsif is_task?
            classes << 'sprint-task'
            if options[:draggable] and editable? and sprint and
               User.current.allowed_to?(:edit_sprint_board, project) and !sprint.is_product_backlog?
              classes << 'post-it-horizontal-move-cursor'
            end
          end
          if Scrum::Setting.random_posit_rotation
            classes << "post-it-rotation-#{rand(5)}" if options[:rotate]
            classes << "post-it-small-rotation-#{rand(5)}" if options[:small_rotate]
          end
          classes << 'post-it-scale' if options[:scale]
          classes << 'post-it-small-scale' if options[:small_scale]
          classes.join(' ')
        end

        def self.doer_post_it_css_class
          doer_or_reviewer_post_it_css_class(:doer)
        end

        def self.reviewer_post_it_css_class
          doer_or_reviewer_post_it_css_class(:reviewer)
        end

        def has_pending_effort?
          self.is_task? and self.pending_efforts.any?
        end

        def pending_effort
          value = nil
          if self.has_pending_effort?
            value = self.pending_efforts.last.effort
          elsif self.is_pbi?
            if Scrum::Setting.use_remaining_story_points?
              if self.has_remaining_story_points?
                value = self.pending_efforts.last.effort
              end
            else
              value = self.pending_effort_children
            end
          end
          return value
        end

        def pending_effort_children
          value = nil
          if self.is_complex_pbi? and self.children.any?
            value = self.children.collect{|task| task.pending_effort}.compact.sum
          end
          return value
        end

        def pending_effort=(new_effort)
          if is_task?
            self.any_pending_effort = new_effort
          elsif self.is_pbi? and Scrum::Setting.use_remaining_story_points?
            self.any_pending_effort = new_effort
          end
        end

        def has_remaining_story_points?
          Scrum::Setting.use_remaining_story_points? and is_pbi? and pending_efforts.any?
        end

        def remaining_story_points
          if has_remaining_story_points?
            return pending_efforts.last.effort
          end
        end

        def remaining_story_points=(new_sps_value)
          if is_pbi?
            self.any_pending_effort = new_sps_value
          end
        end

        def story_points_for_burdown(day)
          value = nil
          if self.has_remaining_story_points?
            values = self.pending_efforts.where(['date <= ?', day])
            value = values.last.effort if values.any?
          end
          if value.nil?
            closed_on = self.closed_on_for_burndown
            value = (closed_on.nil? or closed_on.beginning_of_day > day) ? self.story_points : 0.0
          end
          return value
        end

        def init_from_params(params)
        end

        def inherit_from_issue(source_issue)
          [:priority_id, :category_id, :fixed_version_id, :start_date, :due_date].each do |attribute|
            self.copy_attribute(source_issue, attribute)
          end
          self.custom_field_values = source_issue.custom_field_values.inject({}){|h, v| h[v.custom_field_id] = v.value; h}
        end

        def field?(field)
          included = self.tracker.field?(field)
          if (Redmine::VERSION::STRING < '3.4.0') and (field.to_sym == :description)
            included = true
          end
          self.safe_attribute?(field) and (included or self.required_attribute?(field))
        end

        def custom_field?(custom_field)
          self.tracker.custom_field?(custom_field)
        end

        def set_on_top
          @set_on_top = true
        end

        def total_time
          # Cache added
          unless defined?(@total_time)
            if self.is_simple_pbi?
              the_pending_effort = self.pending_effort
              the_spent_hours = self.spent_hours
            elsif self.is_pbi?
              the_pending_effort = self.pending_effort_children
              the_spent_hours = self.children.collect{|task| task.spent_hours}.compact.sum
            elsif self.is_task?
              the_pending_effort = self.pending_effort
              the_spent_hours = self.spent_hours
            end
            the_pending_effort = the_pending_effort.nil? ? 0.0 : the_pending_effort
            the_spent_hours = the_spent_hours.nil? ? 0.0 : the_spent_hours
            @total_time = (the_pending_effort + the_spent_hours)
          end
          return @total_time
        end

        def speed
          if (self.is_pbi? or self.is_task?) and (self.total_time > 0.0)
            the_estimated_hours = (!defined?(self.total_estimated_hours) or self.total_estimated_hours.nil?) ?
                0.0 : self.total_estimated_hours
            return ((the_estimated_hours * 100.0) / self.total_time).round
          else
            return nil
          end
        end

        def has_blocked_field?
          return ((!((custom_field_id = Scrum::Setting.blocked_custom_field_id).nil?)) and
                  visible_custom_field_values.collect{|value| value.custom_field.id.to_s}.include?(custom_field_id))
        end

        def scrum_blocked?
          if has_blocked_field? and
              !((custom_field_id = Scrum::Setting.blocked_custom_field_id).nil?) and
              !((custom_value = self.custom_value_for(custom_field_id)).nil?) and
              !((value = custom_value.value).blank?)
            return (value == '1')
          end
        end

        def move_pbi_to(position, other_pbi_id = nil)
          if !(sprint.nil?) and is_pbi?
            case position
              when 'top'
                move_issue_to_the_begin_of_the_sprint
                check_bad_dependencies
                save!
              when 'bottom'
                move_issue_to_the_end_of_the_sprint
                check_bad_dependencies
                save!
              when 'before', 'after'
                if other_pbi_id.nil? or (other_pbi = Issue.find(other_pbi_id)).nil?
                  raise "Other PBI ID ##{other_pbi_id} is invalid"
                elsif !(other_pbi.is_pbi?)
                  raise "Issue ##{other_pbi_id} is not a PBI"
                elsif (other_pbi.sprint_id != sprint_id)
                  raise "Other PBI ID ##{other_pbi_id} is not in this product backlog"
                else
                  move_issue_respecting_to_pbi(other_pbi, position == 'after')
                end
            end
          end
        end

        def is_first_pbi?
          min = min_position
          return ((!(position.nil?)) and (!(min.nil?)) and (position <= min))
        end

        def is_last_pbi?
          max = max_position
          return ((!(position.nil?)) and (!(max.nil?)) and (position >= max))
        end

        def assignable_sprints
          unless @assignable_sprints
            sprints = project.all_open_sprints_and_product_backlogs.to_a
            sprints << sprint unless sprint.nil? or sprint_id_changed?
            @assignable_sprints = sprints.uniq.sort
          end
          return @assignable_sprints if @assignable_sprints
        end

        def scrum?
          enabled = false
          if project
            enabled = true if project.scrum?
          end
          if sprint and sprint.project
            enabled = true if sprint.project.scrum?
          end
          return enabled
        end

        def get_dependencies
          dependencies = []
          unless sprint.nil?
            sprint.pbis(:position_bellow => position).each do |other_pbi|
              if self != other_pbi
                if self.respond_to?(:all_dependent_issues)
                  # Old Redmine API (<3.3.0).
                  is_dependent = all_dependent_issues.include?(other_pbi)
                elsif self.respond_to?(:would_reschedule?) and self.respond_to?(:blocks?)
                  # New Redmine API (>=3.3.0).
                  is_dependent = (would_reschedule?(other_pbi) or blocks?(other_pbi))
                else
                  is_dependent = false
                end
                dependencies << other_pbi if is_dependent
              end
            end
          end
          return dependencies
        end

        def check_bad_dependencies(raise_exception = true)
          message = nil
          if Scrum::Setting.check_dependencies_on_pbi_sorting
            dependencies = get_dependencies
            if dependencies.count > 0
              others = dependencies.collect{ |issue| "##{issue.id}" }.join(', ')
              message = l(:error_sorting_other_issues_depends_on_issue, :id => id, :others => others)
            end
          end
          raise message if !(message.nil?) and raise_exception
          return message
        end

      protected

        def copy_attribute(source_issue, attribute)
          if self.safe_attribute?(attribute) and source_issue.safe_attribute?(attribute)
            self.send("#{attribute}=", source_issue.send("#{attribute}"))
          end
        end

      private

        def update_position
          if sprint_id_was.blank?
            # New PBI into PB or Sprint
            if @set_on_top
              move_issue_to_the_begin_of_the_sprint
            else
              move_issue_to_the_end_of_the_sprint
            end
          elsif sprint and (old_sprint = Sprint.find_by_id(sprint_id_was))
            if old_sprint.is_product_backlog
              # From PB to Sprint
              move_issue_to_the_end_of_the_sprint
            elsif sprint.is_product_backlog
              # From Sprint to PB
              move_issue_to_the_begin_of_the_sprint
            else
              # From Sprint to Sprint
              move_issue_to_the_end_of_the_sprint
            end
          end
        end

        def update_pending_effort
          self.pending_effort = 0 if self.closed?
        end

        def update_assigned_to
          new_status = IssueStatus.task_statuses.first
          if new_status
            if self.status == new_status
              if Scrum::Setting.clear_new_tasks_assignee and !(new_record?)
                self.assigned_to = nil
              end
            elsif self.assigned_to.nil?
              self.assigned_to = User.current
            end
          end
        end

        def update_parent_pbi
          new_status = IssueStatus.task_statuses.first
          in_progress_status = IssueStatus.task_statuses.second
          if new_status && in_progress_status
            pbi = self.parent
            if pbi and pbi.is_pbi?
              all_tasks_new = (self.status == new_status)
              pbi.children.each do |task|
                if task.is_task?
                  task = self if task.id == self.id
                  if task.status != new_status
                    all_tasks_new = false
                    break # at least a task not new, no need to go further
                  end
                end
              end
              if pbi.status == new_status and !all_tasks_new
                pbi.init_journal(User.current,
                                 l(:label_pbi_status_auto_updated_one_task_no_new,
                                   :pbi_status => in_progress_status.name,
                                   :task_status => new_status.name))
                pbi.status = in_progress_status
                pbi.save!
              elsif pbi.status != new_status and all_tasks_new
                pbi.init_journal(User.current,
                                 l(:label_pbi_status_auto_updated_all_tasks_new,
                                   :pbi_status => new_status.name,
                                   :task_status => new_status.name))
                pbi.status = new_status
                pbi.save!
              end
            end
          end
        end

        def update_parent_pbi_on_closed_tasks
          statuses = IssueStatus.where(:id => Scrum::Setting.closed_pbi_status_id).order("position ASC")
          pbi = self.parent
          if statuses.length == 1 and pbi and pbi.is_pbi?
            pbi_status_to_set = statuses.first
            all_tasks_closed = self.closed?
            pbi.children.each do |task|
              if task.is_task?
                task = self if task.id == self.id
                unless task.closed?
                  all_tasks_closed = false
                  break # at least a task opened, no need to go further
                end
              end
            end
            if all_tasks_closed and pbi.status != pbi_status_to_set
              pbi.init_journal(User.current,
                               l(:label_pbi_status_auto_updated_all_tasks_closed,
                                 :pbi_status => pbi_status_to_set.name))
              pbi.status = pbi_status_to_set
              pbi.save!
            end
          end
        end

        def min_position
          min = nil
          unless sprint.nil?
            sprint.pbis.each do |pbi|
              min = pbi.position if min.nil? or ((!pbi.position.nil?) and (pbi.position < min))
            end
          end
          return min
        end

        def max_position
          max = nil
          unless sprint.nil?
            sprint.pbis.each do |pbi|
              max = pbi.position if max.nil? or ((!pbi.position.nil?) and (pbi.position > max))
            end
          end
          return max
        end

        def move_issue_to_the_begin_of_the_sprint
          min = min_position
          self.position = min.nil? ? 1 : (min - 1)
        end

        def move_issue_to_the_end_of_the_sprint
          max = max_position
          self.position = max.nil? ? 1 : (max + 1)
        end

        def move_issue_respecting_to_pbi(other_pbi, after)
          self.position = other_pbi.position
          self.position += 1 if after
          sprint.pbis(:position_above => after ? self.position : self.position - 1).each do |next_pbi|
            if next_pbi.id != self.id
              next_pbi.position += 1
            end
          end

          self.check_bad_dependencies
          sprint.pbis(:position_above => after ? self.position : self.position - 1).each do |next_pbi|
            if next_pbi.id != self.id
              next_pbi.check_bad_dependencies
            end
          end

          self.save!
          sprint.pbis(:position_above => after ? self.position : self.position - 1).each do |next_pbi|
            if next_pbi.id != self.id
              next_pbi.save!
            end
          end
        end

        def self.doer_or_reviewer_post_it_css_class(type)
          classes = ['post-it']
          case type
            when :doer
              classes << 'doer-post-it'
              classes << Scrum::Setting.doer_color
            when :reviewer
              classes << 'reviewer-post-it'
              classes << Scrum::Setting.reviewer_color
          end
          if Scrum::Setting.random_posit_rotation
            classes << "post-it-rotation-#{rand(5)}"
          end
          classes.join(' ')
        end

        @@activities = nil
        def self.activities
          unless @@activities
            @@activities = Enumeration.where(:type => 'TimeEntryActivity')
          end
          @@activities
        end

        @@reviewing_activities_ids = nil
        def self.reviewing_activities_ids
          unless @@reviewing_activities_ids
            @@reviewing_activities_ids = Scrum::Setting.verification_activity_ids
          end
          @@reviewing_activities_ids
        end

        @@doing_activities_ids = nil
        def self.doing_activities_ids
          unless @@doing_activities_ids
            reviewing_activities = Enumeration.where(:id => reviewing_activities_ids)
            doing_activities = activities - reviewing_activities
            @@doing_activities_ids = doing_activities.collect{|a| a.id}
          end
          @@doing_activities_ids
        end

        def any_pending_effort=(new_effort)
          if id and new_effort
            effort = PendingEffort.where(:issue_id => id, :date => Date.today).first
            # Replace invalid float number separator (i.e. 0,5) with valid separator (i.e. 0.5)
            new_effort.gsub!(',', '.') if new_effort.is_a?(String)
            if effort.nil?
              date = (pending_efforts.empty? and sprint and sprint.sprint_start_date and sprint.sprint_start_date < Date.today) ? sprint.sprint_start_date : Date.today
              effort = PendingEffort.new(:issue_id => id, :date => date, :effort => new_effort)
            else
              effort.effort = new_effort
            end
            effort.save!
          end
        end

      end
    end
  end
end
