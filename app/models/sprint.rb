# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class Sprint < ActiveRecord::Base

  belongs_to :user
  belongs_to :project
  has_many :issues, :dependent => :destroy
  has_many :efforts, :class_name => "SprintEffort", :dependent => :destroy
  scope :sorted, -> { order(fields_for_order_statement) }
  scope :open, -> { where(:status => 'open') }

  include Redmine::SafeAttributes
  safe_attributes :name, :description, :sprint_start_date, :sprint_end_date, :status, :shared

  SPRINT_STATUSES = %w(open closed)

  validates_presence_of :name
  validates_uniqueness_of :name, :scope => [:project_id]
  validates_length_of :name, :maximum => 60
  validates_presence_of :sprint_start_date, :unless => :is_product_backlog?
  validates_presence_of :sprint_end_date, :unless => :is_product_backlog?
  validates_inclusion_of :status, :in => SPRINT_STATUSES

  def to_s
    name
  end

  def is_product_backlog?
    self.is_product_backlog
  end

  def pbis(options = {})
    conditions = {:tracker_id => Scrum::Setting.pbi_tracker_ids,
                  :status_id => Scrum::Setting.pbi_status_ids}
    order = "position ASC"
    if options[:position_bellow]
      first_issue = issues.where(conditions).order(order).first
      first_position = first_issue ? first_issue.position : (options[:position_bellow] - 1)
      last_position = options[:position_bellow] - 1
    elsif options[:position_above]
      last_issue = issues.where(conditions).order(order).last
      first_position = options[:position_above] + 1
      last_position = last_issue ? last_issue.position : (options[:position_above] + 1)
    end
    if options[:position_bellow] or options[:position_above]
      if last_position < first_position
        temp = last_position
        last_position = first_position
        first_position = temp
      end
      conditions[:position] = first_position..last_position
    end
    conditions[:project_id] = options[:filter_by_project] if options[:filter_by_project]
    issues.where(conditions).order(order).select{|issue| issue.visible?}
  end

  def closed_pbis(options = {})
    pbis(options).select {|pbi| pbi.scrum_closed?}
  end

  def not_closed_pbis(options = {})
    pbis(options).select {|pbi| !pbi.scrum_closed?}
  end

  def story_points(options = {})
    pbis(options).collect{|pbi| pbi.story_points.to_f}.sum
  end

  def closed_story_points(options = {})
    pbis(options).collect{|pbi| pbi.closed_story_points}.sum
  end

  def scheduled_story_points(options = {})
    pbis(options).select{|pbi| pbi.scheduled?}.collect{|pbi| pbi.story_points.to_f}.sum
  end

  def tasks(options = {})
    modified_options = options.clone
    conditions = {:tracker_id => Scrum::Setting.task_tracker_ids}
    if modified_options[:filter_by_project]
      conditions[:project_id] = modified_options[:filter_by_project]
      modified_options.delete(:filter_by_project)
    end
    conditions.merge!(modified_options)
    issues.where(conditions).select{|issue| issue.visible?}
  end

  def orphan_tasks
    tasks(:parent_id => nil)
  end

  def estimated_hours(filter = {})
    sum = 0.0
    tasks(filter).each do |task|
      if task.use_in_burndown?
        pending_effort = task.pending_efforts.where(['date < ?', self.sprint_start_date]).order('date ASC').last
        pending_effort = pending_effort.effort unless pending_effort.nil?
        if (!(pending_effort.nil?))
          sum += pending_effort
        elsif (!((estimated_hours = task.estimated_hours).nil?))
          sum += estimated_hours
        end
      end
    end
    return sum
  end

  def time_entries
    tasks.collect{|task| task.time_entries}.flatten
  end

  def time_entries_by_activity
    results = {}
    total = 0.0
    if User.current.allowed_to?(:view_sprint_stats, project)
      time_entries.each do |time_entry|
        if time_entry.activity and time_entry.hours > 0.0 and
           time_entry.spent_on and sprint_start_date and sprint_end_date and
           time_entry.spent_on >= sprint_start_date and time_entry.spent_on <= sprint_end_date
          if !results.key?(time_entry.activity_id)
            results[time_entry.activity_id] = {:activity => time_entry.activity, :total => 0.0}
          end
          results[time_entry.activity_id][:total] += time_entry.hours
          total += time_entry.hours
        end
      end
      results.values.each do |result|
        result[:percentage] = ((result[:total] * 100.0) / total).round
      end
    end
    return results.values, total
  end

  def time_entries_by_member
    results = {}
    total = 0.0
    if User.current.allowed_to?(:view_sprint_stats_by_member, project)
      time_entries.each do |time_entry|
        if time_entry.activity and time_entry.hours > 0.0 and
           time_entry.spent_on >= sprint_start_date and time_entry.spent_on <= sprint_end_date
          if !results.key?(time_entry.user_id)
            results[time_entry.user_id] = {:member => time_entry.user, :total => 0.0}
          end
          results[time_entry.user_id][:total] += time_entry.hours
          total += time_entry.hours
        end
      end
      results.values.each do |result|
        result[:percentage] = ((result[:total] * 100.0) / total).round
      end
    end
    results = results.values.sort{|a, b| a[:member] <=> b[:member]}
    return results, total
  end

  def efforts_by_member
    results = {}
    total = 0.0
    if User.current.allowed_to?(:view_sprint_stats_by_member, project)
      efforts.each do |effort|
        if effort.user and effort.effort > 0.0
          if !results.key?(effort.user_id)
            results[effort.user_id] = {:member => effort.user, :total => 0.0}
          end
          results[effort.user_id][:total] += effort.effort
          total += effort.effort
        end
      end
      results.values.each do |result|
        result[:percentage] = ((result[:total] * 100.0) / total).round
      end
    end
    results = results.values.sort{|a, b| a[:member] <=> b[:member]}
    return results, total
  end

  def efforts_by_member_and_activity
    results = {}
    if User.current.allowed_to?(:view_sprint_stats_by_member, project)
      members = Set.new
      time_entries.each do |time_entry|
        if time_entry.activity and time_entry.hours > 0.0 and
            time_entry.spent_on >= sprint_start_date and time_entry.spent_on <= sprint_end_date
          activity = time_entry.activity.name
          member = time_entry.user.name
          if !results.key?(activity)
            results[activity] = {}
          end
          if !results[activity].key?(member)
            results[activity][member] = 0.0
          end
          results[activity][member] += time_entry.hours
          members << member
        end
      end
      results.values.each do |data|
        members.each do |member|
          data[member] = 0.0 unless data.key?(member)
        end
      end
    end
    return results
  end

  def sps_by_pbi_category
    return sps_by_pbi_field(:category_id, nil, :category, :name, nil, nil)
  end

  def sps_by_pbi_type
    return sps_by_pbi_field(:tracker_id, nil, :tracker, :name, nil, nil)
  end

  def sps_by_pbi_creation_date
    return sps_by_pbi_field(:created_on, :to_date, :created_on, :to_date, self.sprint_start_date,
                            l(:label_date_previous_to, :date => self.sprint_start_date))
  end

  def self.fields_for_order_statement(table = nil)
    table ||= table_name
    ["(CASE WHEN #{table}.sprint_end_date IS NULL THEN 1 ELSE 0 END)",
     "#{table}.sprint_end_date",
     "#{table}.name",
     "#{table}.id"]
  end

  def total_time
    pbis.collect{|pbi| pbi.total_time}.compact.sum
  end

  def hours_per_story_point
    sps = story_points
    sps > 0 ? (total_time / sps).round(2) : 0.0
  end

  def closed?
    status == 'closed'
  end

  def open?
    status == 'open'
  end

  def get_dependencies
    dependencies = []
    pbis.each do |pbi|
      pbi_dependencies = pbi.get_dependencies
      dependencies << {:pbi => pbi, :dependencies => pbi_dependencies} if pbi_dependencies.count > 0
    end
    return dependencies
  end

  def completed_sps_by_day(filter = {})
    days = {}
    non_working_days = Setting.non_working_week_days.collect{|day| (day == '7') ? 0 : day.to_i}
    end_date = self.sprint_end_date + 1
    (self.sprint_start_date..end_date).each do |day|
      if (day == end_date) or (!(non_working_days.include?(day.wday)))
        days[day] = self.completed_sps_at_day(day, filter)
      end
    end
    return days
  end

  def completed_sps_at_day(day, filter = {})
    sps = self.pbis(filter).collect { |pbi| pbi.story_points_for_burdown(day) }.compact.sum
    sps = 0.0 unless sps
    return sps
  end

private

  def sps_by_pbi_field(field_id, subfield_id, field, subfield, field_min, label_min)
    results = {}
    total = 0.0
    if User.current.allowed_to?(:view_sprint_stats, project)
      pbis.each do |pbi|
        pbi_story_points = pbi.story_points
        if pbi_story_points
          pbi_story_points = pbi_story_points.to_f
          if pbi_story_points > 0.0
            field_id_value = pbi.public_send(field_id)
            field_id_value = field_id_value.public_send(subfield_id) unless field_id_value.nil? or subfield_id.nil? or !(field_id_value.respond_to?(subfield_id))
            field_id_value = field_min unless field_min.nil? or (field_id_value > field_min)
            if !results.key?(field_id_value)
              field_value = pbi.public_send(field) unless !(pbi.respond_to?(field))
              field_value = field_value.public_send(subfield) unless field_value.nil? or subfield.nil? or !(field_value.respond_to?(subfield))
              field_value = label_min unless field_min.nil? or label_min.nil? or (field_value >= field_min)
              results[field_id_value] = {field => field_value, :total => 0.0}
            end
            results[field_id_value][:total] += pbi_story_points
            total += pbi_story_points
          end
        end
      end
      results.values.each do |result|
        result[:percentage] = ((result[:total] * 100.0) / total).round
      end
    end
    return results.values, total
  end

end
