# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class SprintsController < ApplicationController

  menu_item :sprint
  model_object Sprint

  before_action :find_model_object,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :stats, :sort]
  before_action :find_project_from_association,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :stats, :sort]
  before_action :find_project_by_project_id,
                :only => [:index, :new, :create, :change_issue_status, :burndown_index,
                          :stats_index]
  before_action :find_pbis, :only => [:sort]
  before_action :find_subprojects,
                :only => [:burndown]
  before_action :filter_by_project,
                :only => [:burndown]
  before_action :calculate_stats, :only => [:show, :burndown, :stats]
  before_action :authorize

  accept_api_auth :index, :show

  helper :custom_fields
  helper :scrum
  helper :timelog

  include Redmine::Utils::DateCalculation

  def index
    respond_to do |format|
      format.html {
        if (current_sprint = @project.current_sprint)
          redirect_to sprint_path(current_sprint)
        else
          render_error l(:error_no_sprints)
        end
      }
      format.api
    end
  rescue
    render_404
  end

  def show
    redirect_to project_product_backlog_index_path(@project) if @sprint.is_product_backlog?
    respond_to do |format|
      format.html
      format.api
    end
  end

  def new
    @sprint = Sprint.new(:project => @project, :is_product_backlog => params[:create_product_backlog])
    if @sprint.is_product_backlog
      @sprint.name = l(:label_product_backlog)
      @sprint.sprint_start_date = @sprint.sprint_end_date = Date.today
    elsif @project.sprints.empty?
      @sprint.name = Scrum::Setting.default_sprint_name
      @sprint.sprint_start_date = Date.today
      @sprint.sprint_end_date = add_working_days(@sprint.sprint_start_date, Scrum::Setting.default_sprint_days - 1)
      @sprint.shared = Scrum::Setting.default_sprint_shared
    else
      last_sprint = @project.sprints.last
      result = last_sprint.name.match(/^(.*)(\d+)(.*)$/)
      @sprint.name = result.nil? ? Scrum::Setting.default_sprint_name : (result[1] + (result[2].to_i + 1).to_s + result[3])
      @sprint.description = last_sprint.description
      @sprint.sprint_start_date = next_working_date(last_sprint.sprint_end_date + 1)
      last_sprint_duration = last_sprint.sprint_end_date - last_sprint.sprint_start_date
      @sprint.sprint_end_date = next_working_date(@sprint.sprint_start_date + last_sprint_duration)
      @sprint.shared = last_sprint.shared
    end
  end

  def create
    is_product_backlog = !(params[:create_product_backlog].nil?)
    @sprint = Sprint.new(:user => User.current, :project => @project, :is_product_backlog => is_product_backlog)
    @sprint.safe_attributes = params[:sprint]
    if request.post? and @sprint.save
      if is_product_backlog
        @project.product_backlogs << @sprint
        raise 'Fail to update project with product backlog' unless @project.save!
      end
      flash[:notice] = l(:notice_successful_create)
      redirect_back_or_default settings_project_path(@project, :tab => is_product_backlog ? 'product_backlogs' : 'sprints')
    else
      render :action => :new
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def edit
    @product_backlog = @sprint if @sprint.is_product_backlog
  end

  def update
    @sprint.safe_attributes = params[:sprint]
    if @sprint.save
      flash[:notice] = l(:notice_successful_update)
      redirect_back_or_default settings_project_path(@project, :tab => 'sprints')
    else
      render :action => :edit
    end
  end

  def destroy
    if @sprint.issues.any?
      flash[:error] = l(:notice_sprint_has_issues)
    else
      @sprint.destroy
    end
  rescue
    flash[:error] = l(:notice_unable_delete_sprint)
  ensure
    redirect_to settings_project_path(@project, :tab => 'sprints')
  end

  def change_issue_status
    result = params[:task].match(/^(task|pbi)_(\d+)$/)
    issue_id = result[2].to_i
    @issue = Issue.find(issue_id)
    @old_status = @issue.status

    # Do not change issue status if not necessary
    new_status = IssueStatus.find(params[:status].to_i)

    # Manage case where new status is allowed
    if new_status && @issue.new_statuses_allowed_to.include?(new_status)
      @issue.init_journal(User.current)
      @issue.status = new_status
      @issue.save!
    else
      # Exception replaced by an instance variable
      # Create error message if new status not allowed
      @error_message = l(:error_new_status_no_allowed,
                         :status_from => @old_status,
                         :status_to => new_status)
    end

    respond_to do |format|
      format.js { render 'scrum/update_issue' }
    end
  end

  def edit_effort
  end

  def update_effort
    params[:user].each_pair do |user_id, days|
      user_id = user_id.to_i
      days.each_pair do |day, effort|
        day = day.to_i
        date = @sprint.sprint_start_date + day.to_i
        sprint_effort = SprintEffort.where(:sprint_id => @sprint.id,
                                           :user_id => user_id,
                                           :date => date).first
        if sprint_effort.nil?
          unless effort.blank?
            sprint_effort = SprintEffort.new(:sprint_id => @sprint.id,
                                             :user_id => user_id,
                                             :date => @sprint.sprint_start_date + day,
                                             :effort => effort)
          end
        elsif effort.blank?
          sprint_effort.destroy
          sprint_effort = nil
        else
          sprint_effort.effort = effort
        end
        sprint_effort.save! unless sprint_effort.nil?
      end
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_back_or_default settings_project_path(@project, :tab => 'sprints')
  end

  def burndown_index
    if @project.last_sprint
      redirect_to burndown_sprint_path(@project.last_sprint, :type => params[:type])
    else
      render_error l(:error_no_sprints)
    end
  rescue Exception => exception
    render_404
  end

  MAX_SERIES = 10

  def burndown
    if @sprint.is_product_backlog
      redirect_to(burndown_product_backlog_path(@sprint))
    else
      if @pbi_filter and @pbi_filter[:filter_by_project] == 'without-total'
        @pbi_filter.delete(:filter_by_project)
        without_total = true
      else
        without_total = false
      end
      @only_one = @project.children.visible.empty?
      @x_axis_labels = []
      serie_label = @only_one ? l(:field_pending_effort) : "#{l(:field_pending_effort)} (#{l(:label_all)})"
      all_projects_serie = burndown_for_project(@sprint, @project, serie_label, @pbi_filter, @x_axis_labels)
      @series = []
      @series << all_projects_serie unless without_total
      unless @only_one
        if @pbi_filter.empty? and @subprojects.count > 2
          sub_series = recursive_burndown(@sprint, @project)
          @series += sub_series
        end
        @series.sort! { |serie_1, serie_2|
          closed = ((serie_1[:project].respond_to?('closed?') and serie_1[:project].closed?) ? 1 : 0) -
                   ((serie_2[:project].respond_to?('closed?') and serie_2[:project].closed?) ? 1 : 0)
          if 0 != closed
            closed
          else
            serie_2[:max_value] <=> serie_1[:max_value]
          end
        }
      end
      if params[:type] == 'effort'
        @series = [estimated_effort_serie(@sprint)] + @series
      end
      if @series.count > MAX_SERIES
        @warning = l(:label_limited_to_n_series, :n => MAX_SERIES)
        @series = @series.first(MAX_SERIES)
      end
    end
  end

  def stats_index
    if @project.last_sprint
      redirect_to stats_sprint_path(@project.last_sprint)
    else
      render_error l(:error_no_sprints)
    end
  rescue
    render_404
  end

  def stats
    @days = []
    @members_efforts = {}
    @estimated_efforts_totals = {:days => {}, :total => 0.0}
    @done_efforts_totals = {:days => {}, :total => 0.0}
    ((@sprint.sprint_start_date)..(@sprint.sprint_end_date)).each do |date|
      if @sprint.efforts.where(['date = ?', date]).count > 0
        @days << {:date => date, :label => "#{I18n.l(date, :format => :scrum_day)} #{date.day}"}
        if User.current.allowed_to?(:view_sprint_stats_by_member, @project)
          estimated_effort_conditions = ['date = ?', date]
          done_effort_conditions = ['spent_on = ?', date]
        else
          estimated_effort_conditions = ['date = ? AND user_id = ?', date, User.current.id]
          done_effort_conditions = ['spent_on = ? AND user_id = ?', date, User.current.id]
        end
        @sprint.efforts.where(estimated_effort_conditions).each do |sprint_effort|
          if sprint_effort.effort
            init_members_efforts(@members_efforts, sprint_effort.user)
            member_estimated_efforts_days = init_member_efforts_days(@members_efforts,
                                                                     @sprint,
                                                                     sprint_effort.user,
                                                                     date,
                                                                     true)
            member_estimated_efforts_days[date] += sprint_effort.effort
            @members_efforts[sprint_effort.user.id][:estimated_efforts][:total] += sprint_effort.effort
            @estimated_efforts_totals[:days][date] = 0.0 unless @estimated_efforts_totals[:days].include?(date)
            @estimated_efforts_totals[:days][date] += sprint_effort.effort
            @estimated_efforts_totals[:total] += sprint_effort.effort
          end
        end
        project_efforts_for_stats(@project, @sprint, date, done_effort_conditions, @members_efforts, @done_efforts_totals)
      end
    end
    @members_efforts = @members_efforts.values.sort{|a, b| a[:member] <=> b[:member]}

    @sps_by_pbi_category, @sps_by_pbi_category_total = @sprint.sps_by_pbi_category

    @sps_by_pbi_type, @sps_by_pbi_type_total = @sprint.sps_by_pbi_type

    @sps_by_pbi_creation_date, @sps_by_pbi_creation_date_total = @sprint.sps_by_pbi_creation_date

    @effort_by_activity, @effort_by_activity_total = @sprint.time_entries_by_activity

    if User.current.allowed_to?(:view_sprint_stats_by_member, @project)
      @efforts_by_member_and_activity = @sprint.efforts_by_member_and_activity
      @efforts_by_member_and_activity_chart = {:id => 'stats_efforts_by_member_and_activity', :height => 400}
    end
  end

  def sort
    new_pbis_order = []
    params.keys.each do |param|
      id = param.scan(/pbi\_(\d+)/)
      new_pbis_order << id[0][0].to_i if id and id[0] and id[0][0]
    end
    @pbis.each do |pbi|
      if (index = new_pbis_order.index(pbi.id))
        pbi.position = index + 1
        pbi.save!
      end
    end
    render :body => nil
  end

private

  def init_members_efforts(members_efforts, member)
    unless members_efforts.include?(member.id)
      members_efforts[member.id] = {
        :member => member,
        :estimated_efforts => {
          :days => {},
          :total => 0.0
        },
        :done_efforts => {
          :days => {},
          :total => 0.0
        }
      }
    end
  end

  def init_member_efforts_days(members_efforts, sprint, member, date, estimated)
    member_efforts_days = members_efforts[member.id][estimated ? :estimated_efforts : :done_efforts][:days]
    unless member_efforts_days.include?(date)
      member_efforts_days[date] = 0.0
    end
    return member_efforts_days
  end

  def project_efforts_for_stats(project, sprint, date, done_effort_conditions, members_efforts, done_efforts_totals)
    project.time_entries.where(done_effort_conditions).each do |time_entry|
      if time_entry.hours
        init_members_efforts(members_efforts, time_entry.user)
        member_done_efforts_days = init_member_efforts_days(members_efforts,
                                                            sprint,
                                                            time_entry.user,
                                                            date,
                                                            false)
        member_done_efforts_days[date] += time_entry.hours
        members_efforts[time_entry.user.id][:done_efforts][:total] += time_entry.hours
        done_efforts_totals[:days][date] = 0.0 unless done_efforts_totals[:days].include?(date)
        done_efforts_totals[:days][date] += time_entry.hours
        done_efforts_totals[:total] += time_entry.hours
      end
    end
    if sprint.shared
      project.children.visible.each do |sub_project|
        project_efforts_for_stats(sub_project, sprint, date, done_effort_conditions, members_efforts, done_efforts_totals)
      end
    end
  end

  def find_pbis
    @pbis = @sprint.pbis
  rescue
    render_404
  end

  def calculate_stats
    if Scrum::Setting.show_project_totals_on_sprint
      total_pbis_count = @sprint.pbis().count
      closed_pbis_count = @sprint.closed_pbis().count
      total_sps_count = @sprint.story_points()
      closed_sps_count = @sprint.closed_story_points()
      closed_total_percentage = (total_sps_count == 0.0) ? 0.0 : ((closed_sps_count * 100.0) / total_sps_count)
      @stats = {:total_pbis_count => total_pbis_count,
                :closed_pbis_count => closed_pbis_count,
                :total_sps_count => total_sps_count,
                :closed_sps_count => closed_sps_count,
                :closed_total_percentage => closed_total_percentage}
    end
  end

  def find_subprojects
    if @project and @sprint
      @subprojects = [[l(:label_all), calculate_path(@sprint)]]
      @subprojects << [l(:label_all_but_total), calculate_path(@sprint, 'without-total')] if action_name == 'burndown'
      @subprojects += find_recursive_subprojects(@project, @sprint)
    end
  end

  def find_recursive_subprojects(project, sprint, tabs = '')
    options = [[tabs + project.name, calculate_path(sprint, project)]]
    project.children.visible.to_a.each do |child|
      options += find_recursive_subprojects(child, sprint, tabs + '» ')
    end
    return options
  end

  def filter_by_project
    @pbi_filter = {}
    unless params[:filter_by_project].blank?
      @pbi_filter = {:filter_by_project => params[:filter_by_project]}
    end
  end

  def calculate_path(sprint, project = nil)
    options = {}
    path_method = :burndown_sprint_path
    if ['burndown'].include?(action_name)
      options[:type] = params[:type] unless params[:type].blank?
    end
    if project.nil?
      project_id = nil
    elsif project == 'without-total'
      options[:filter_by_project] = 'without-total'
      project_id = 'without-total'
    else
      options[:filter_by_project] = project.id
      project_id = project.id.to_s
    end
    result = send(path_method, sprint, options)
    if (project.nil? and params[:filter_by_project].blank?) or
       (project_id == params[:filter_by_project])
      @selected_subproject = result
    end
    return result
  end

  def burndown_for_project(sprint, project, label, pbi_filter = {}, x_axis_labels = nil)
    serie = {:data => [],
             :label => label,
             :project => pbi_filter.include?(:filter_by_project) ?
                         Project.find(pbi_filter[:filter_by_project]) :
                         project,
             :max_value => 0.0}

    if params[:type] == 'sps'
      last_sps = sprint.completed_sps_at_day(sprint.sprint_start_date - 1, pbi_filter)
      last_day = nil
      last_label = l(:label_begin) if Scrum::Setting.sprint_burndown_day_zero?
      sprint.completed_sps_by_day(pbi_filter).each do |date, sps|
        date_label = "#{I18n.l(date, :format => :scrum_day)} #{date.day}"
        last_label = date_label unless Scrum::Setting.sprint_burndown_day_zero?
        x_axis_labels << last_label unless x_axis_labels.nil?
        serie[:max_value] = last_sps if last_sps and last_sps > serie[:max_value]
        serie[:data] << {:day => date,
                         :pending_sps => last_sps,
                         :pending_sps_tooltip => l(:label_pending_sps_tooltip,
                                                   :date => last_label,
                                                   :sps => last_sps)}
        last_sps = sps
        last_day = date.day
        last_label = date_label if Scrum::Setting.sprint_burndown_day_zero?
      end
      if serie[:data].any?
        unless x_axis_labels.nil?
          if Scrum::Setting.sprint_burndown_day_zero?
            x_axis_labels << last_label
          else
            x_axis_labels[x_axis_labels.length - 1] = l(:label_end)
          end
        end
        serie[:max_value] = last_sps if last_sps and last_sps > serie[:max_value]
        serie[:data].last[:pending_sps_tooltip] = l(:label_pending_sps_tooltip,
                                                    :date => last_label,
                                                    :sps => last_sps)
      end
      @type = :sps
    else
      sprint_tasks = sprint.tasks(pbi_filter)
      last_pending_effort = pending_effort_at_day(sprint_tasks, sprint.sprint_start_date - 1)
      last_day = nil
      last_label = l(:label_begin) if Scrum::Setting.sprint_burndown_day_zero?
      ((sprint.sprint_start_date)..(sprint.sprint_end_date)).each do |date|
        sprint_efforts = sprint.efforts.where(['date >= ?', date])
        if sprint_efforts.any?
          if date <= Date.today
            pending_effort = pending_effort_at_day(sprint_tasks, date)
          end
          date_label = "#{I18n.l(date, :format => :scrum_day)} #{date.day}"
          last_label = date_label unless Scrum::Setting.sprint_burndown_day_zero?
          x_axis_labels << last_label unless x_axis_labels.nil?
          serie[:max_value] = last_pending_effort if last_pending_effort and last_pending_effort > serie[:max_value]
          serie[:data] << {:day => date,
                           :effort => last_pending_effort,
                           :tooltip => l(:label_pending_effort_tooltip,
                                         :date => last_label,
                                         :hours => last_pending_effort)}
          last_pending_effort = pending_effort
          last_day = date.day
          last_label = date_label if Scrum::Setting.sprint_burndown_day_zero?
        end
      end
      last_label = l(:label_end) unless Scrum::Setting.sprint_burndown_day_zero?
      x_axis_labels << last_label unless x_axis_labels.nil?
      serie[:max_value] = last_pending_effort if last_pending_effort and last_pending_effort > serie[:max_value]
      serie[:data] << {:day => last_day,
                       :effort => last_pending_effort,
                       :tooltip => l(:label_pending_effort_tooltip,
                                     :date => last_label,
                                     :hours => last_pending_effort)}
      @type = :effort
    end
    return serie
  end

  def estimated_effort_serie(sprint)
    serie = {:data => [],
             :label => l(:label_estimated_effort)}
    last_day = nil
    last_label = l(:label_begin) if Scrum::Setting.sprint_burndown_day_zero
    ((sprint.sprint_start_date)..(sprint.sprint_end_date)).each do |date|
      sprint_efforts = sprint.efforts.where(['date >= ?', date])
      if sprint_efforts.any?
        estimated_effort = sprint_efforts.collect{|effort| effort.effort}.compact.sum
        date_label = "#{I18n.l(date, :format => :scrum_day)} #{date.day}"
        last_label = date_label unless Scrum::Setting.sprint_burndown_day_zero
        serie[:data] << {:day => date,
                         :effort => estimated_effort,
                         :tooltip => l(:label_estimated_effort_tooltip,
                                       :date => last_label,
                                       :hours => estimated_effort)}
        last_day = date.day
        last_label = date_label if Scrum::Setting.sprint_burndown_day_zero
      end
    end
    last_label = l(:label_end) unless Scrum::Setting.sprint_burndown_day_zero
    serie[:data] << {:day => last_day,
                     :effort => 0,
                     :tooltip => l(:label_estimated_effort_tooltip,
                                   :date => last_label,
                                   :hours => 0)}
    return serie
  end

  def recursive_burndown(sprint, project)
    serie_name = "#{l(:field_pending_effort)} (#{project.name})"
    series = [burndown_for_project(@sprint, @project, serie_name,
                                   {:filter_by_project => project.id})]
    project.children.visible.to_a.each do |child|
      series += recursive_burndown(sprint, child)
    end
    return series
  end

  def pending_effort_at_day(tasks, date)
    efforts = []
    tasks.each do |task|
      if task.use_in_burndown?
        task_efforts = task.pending_efforts.where(['date <= ?', date])
        efforts << (task_efforts.any? ? task_efforts.last.effort : task.estimated_hours)
      end
    end
    return efforts.compact.sum
  end

end
