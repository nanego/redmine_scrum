# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ScrumController < ApplicationController

  menu_item :product_backlog, :except => [:stats]
  menu_item :overview, :only => [:stats]

  before_action :find_issue,
                :only => [:change_story_points, :change_remaining_story_points,
                          :change_pending_effort,
                          :change_assigned_to, :new_time_entry,
                          :create_time_entry, :edit_task, :update_task,
                          :change_pending_efforts]
  before_action :find_sprint,
                :only => [:new_pbi, :create_pbi,
                          :move_not_closed_pbis_to_last_sprint]
  before_action :find_pbi,
                :only => [:new_task, :create_task, :edit_pbi, :update_pbi,
                          :move_pbi, :move_to_last_sprint,
                          :move_to_product_backlog]
  before_action :find_project_by_project_id,
                :only => [:stats]

  before_action :authorize,
                :except => [:new_pbi, :create_pbi, :new_task, :create_task,
                            :move_to_last_sprint,
                            :move_not_closed_pbis_to_last_sprint,
                            :move_to_product_backlog,
                            :new_time_entry, :create_time_entry]
  before_action :authorize_add_issues,
                :only => [:new_pbi, :create_pbi, :new_task, :create_task]
  before_action :authorize_edit_issues,
                :only => [:move_to_last_sprint,
                          :move_not_closed_pbis_to_last_sprint,
                          :move_to_product_backlog]
  before_action :authorize_log_time,
                :only => [:new_time_entry, :create_time_entry]

  helper :custom_fields
  helper :projects
  helper :scrum
  helper :timelog

  def change_story_points
    begin
      @issue.story_points = params[:value]
      status = 200
    rescue
      status = 503
    end
    render :body => nil, :status => status
  end

  def change_remaining_story_points
    @issue.remaining_story_points = params[:value]
    render :body => nil, :status => status
  end

  def change_pending_effort
    @issue.pending_effort = params[:value]
    render :body => nil, :status => 200
  end

  def change_pending_efforts
    params['pending_efforts'].each_pair do |id, value|
      pending_effort = PendingEffort.find(id)
      raise "Invalid pending effort ID #{id}" if pending_effort.nil?
      raise "Pending effort ID #{id} is not owned by this issue" if pending_effort.issue_id != @issue.id
      if value.blank?
        pending_effort.delete
      else
        pending_effort.effort = value.to_f
        pending_effort.save!
      end
    end
    redirect_to issue_path(@issue)
  end

  def change_assigned_to
    @issue.init_journal(User.current)
    @issue.assigned_to = params[:value].blank? ? nil : User.find(params[:value].to_i)
    @issue.save!
    render_task(@project, @issue, params)
  end

  def new_time_entry
    @pbi_status_id = params[:pbi_status_id]
    @other_pbi_status_ids = params[:other_pbi_status_ids]
    @issue_id = params[:issue_id]
    respond_to do |format|
      format.js
    end
  end

  def create_time_entry
    begin
      time_entry = TimeEntry.new(params.require(:time_entry).permit(:hours, :spent_on, :comments, :activity_id, :user_id))
      time_entry.project_id = @project.id
      time_entry.issue_id = @issue.id
      time_entry.user_id = params[:time_entry][:user_id]
      call_hook(:controller_timelog_edit_before_save, {:params => params, :time_entry => time_entry})
      time_entry.save!
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def new_pbi
    @pbi = Issue.new
    @pbi.project = @project
    @pbi.tracker = @project.trackers.find(params[:tracker_id])
    @pbi.status = @pbi.default_status
    @pbi.author = User.current
    @pbi.sprint = @sprint
    @top = true unless params[:top].nil? or (params[:top] == 'false')
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create_pbi
    begin
      @continue = !(params[:create_and_continue].nil?)
      @top = !(params[:top].nil?)
      @pbi = Issue.new
      if params[:issue][:project_id]
        @pbi.project_id = params[:issue][:project_id]
      else
        @pbi.project = @project
      end
      @pbi.author = User.current
      @pbi.tracker_id = params[:issue][:tracker_id]
      @pbi.set_on_top if @top
      @pbi.sprint = @sprint
      update_attributes(@pbi, params)
      @pbi.save!
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def edit_pbi
    respond_to do |format|
      format.js
    end
  end

  def update_pbi
    begin
      @pbi.init_journal(User.current, params[:issue][:notes])
      update_attributes(@pbi, params)
      @pbi.save!
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def move_pbi
    begin
      @position = params[:position]
      case params[:position]
        when 'top', 'bottom'
          @pbi.move_pbi_to(@position)
        when 'before'
          @other_pbi = params[:before_other_pbi]
          @pbi.move_pbi_to(@position, @other_pbi)
        when 'after'
          @other_pbi = params[:after_other_pbi]
          @pbi.move_pbi_to(@position, @other_pbi)
        else
          raise "Invalid position: #{@position.inspect}"
      end
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
  end

  def move_to_last_sprint
    begin
      raise "The project hasn't defined any Sprint yet" unless @project.last_sprint
      @previous_sprint = @pbi.sprint
      move_issue_to_sprint(@pbi, @project.last_sprint)
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def move_not_closed_pbis_to_last_sprint
    begin
      last_sprint = @project.last_sprint
      raise "The project hasn't defined any Sprint yet" unless last_sprint
      not_closed_pbis = @sprint.not_closed_pbis
      if not_closed_pbis.empty?
        flash[:notice] = l(:label_nothing_to_move)
      else
        not_closed_pbis_links = []
        not_closed_pbis.each do |pbi|
          link = view_context.link_to_issue(pbi,
                                            :project => pbi.project != @project,
                                            :tracker => true)
          not_closed_pbis_links << link
          move_issue_to_sprint(pbi, last_sprint)
        end
        flash[:notice] = l(:label_pbis_moved,
                           :pbis => not_closed_pbis_links.join(', '))
      end
    rescue Exception => exception
      logger.error("Exception: #{exception.inspect}")
      flash[:error] = exception
    end
    redirect_to sprint_path(@sprint)
  end

  def move_to_product_backlog
    begin
      product_backlog = @project.product_backlogs.find(params[:id])
      move_issue_to_sprint(@pbi, product_backlog)
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def new_task
    @task = Issue.new
    @task.project = @pbi.project
    @task.tracker = Tracker.find(params[:tracker_id])
    @task.status = @task.default_status
    @task.parent = @pbi
    @task.author = User.current
    @task.sprint = @sprint
    if Scrum::Setting.inherit_pbi_attributes
      @task.inherit_from_issue(@pbi)
    end
    respond_to do |format|
      format.html
      format.js
    end
  rescue Exception => e
    logger.error("Exception: #{e.inspect}")
    render_404
  end

  def create_task
    begin
      @continue = !(params[:create_and_continue].nil?)
      @task = Issue.new
      if params[:issue][:project_id]
        @task.project_id = params[:issue][:project_id]
      else
        @task.project = @pbi.project
      end
      @task.parent_issue_id = @pbi.id
      @task.author = User.current
      @task.sprint = @sprint
      @task.tracker_id = params[:issue][:tracker_id]
      update_attributes(@task, params)
      @task.save!
      @task.pending_effort = params[:issue][:pending_effort]
    rescue Exception => @exception
    end
    respond_to do |format|
      format.js
    end
  end

  def edit_task
    respond_to do |format|
      format.js
    end
  end

  def update_task
    begin
      @issue.init_journal(User.current, params[:issue][:notes])
      @old_status = @issue.status
      update_attributes(@issue, params)
      @issue.save!
      @issue.pending_effort = params[:issue][:pending_effort]
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js do
        render "scrum/update_issue"
      end
    end
  end

  def stats
    if User.current.allowed_to?(:view_time_entries, @project)
      cond = @project.project_condition(Setting.display_subprojects_issues?)
      @total_hours = TimeEntry.visible.where(cond).sum(:hours).to_f
    end

    @closed_story_points_per_sprint = @project.closed_story_points_per_sprint
    @closed_story_points_per_sprint_chart = {:id => 'closed_story_points_per_sprint', :height => 400}

    @hours_per_story_point = @project.hours_per_story_point
    @hours_per_story_point_chart = {:id => 'hours_per_story_point', :height => 400}

    @sps_by_pbi_category, @sps_by_pbi_category_total = @project.sps_by_category
    @sps_by_pbi_type, @sps_by_pbi_type_total = @project.sps_by_pbi_type
    @effort_by_activity, @effort_by_activity_total = @project.effort_by_activity
  end

private

  def render_task(project, task, params)
    render :partial => "post_its/sprint_board/task",
           :status => 200,
           :locals => {:project => project,
                       :task => task,
                       :pbi_status_id => params[:pbi_status_id],
                       :other_pbi_status_ids => params[:other_pbi_status_ids].split(","),
                       :task_id => params[:task_id],
                       :read_only => false}
  end

  def find_sprint
    @sprint = Sprint.find(params[:sprint_id])
    @project = @sprint.project
  rescue
    logger.error("Sprint #{params[:sprint_id]} not found")
    render_404
  end

  def find_pbi
    @pbi = Issue.find(params[:pbi_id])
    @sprint = @pbi.sprint
    @project = @sprint.project
  rescue
    logger.error("PBI #{params[:pbi_id]} not found")
    render_404
  end

  def authorize_action_on_current_project(action)
    if User.current.allowed_to?(action, @project)
      return true
    else
      render_403
      return false
    end
  end

  def authorize_add_issues
    authorize_action_on_current_project(:add_issues)
  end

  def authorize_log_time
    authorize_action_on_current_project(:log_time)
  end

  def authorize_edit_issues
    authorize_action_on_current_project(:edit_issues)
  end

  def update_attributes(issue, params)
    issue.status_id = params[:issue][:status_id] unless params[:issue][:status_id].nil?
    raise 'New status is not allowed' unless issue.new_statuses_allowed_to.include?(issue.status)
    issue.project_id = params[:issue][:project_id] unless params[:issue][:project_id].nil?
    issue.assigned_to_id = params[:issue][:assigned_to_id] unless params[:issue][:assigned_to_id].nil?
    issue.subject = params[:issue][:subject] unless params[:issue][:subject].nil?
    issue.priority_id = params[:issue][:priority_id] unless params[:issue][:priority_id].nil?
    issue.estimated_hours = params[:issue][:estimated_hours].gsub(',', '.') if issue.safe_attribute?(:estimated_hours) and (!(params[:issue][:estimated_hours].nil?))
    issue.done_ratio = params[:issue][:done_ratio] unless params[:issue][:done_ratio].nil?
    issue.description = params[:issue][:description] unless params[:issue][:description].nil?
    issue.category_id = params[:issue][:category_id] if issue.safe_attribute?(:category_id) and (!(params[:issue][:category_id].nil?))
    issue.fixed_version_id = params[:issue][:fixed_version_id] if issue.safe_attribute?(:fixed_version_id) and (!(params[:issue][:fixed_version_id].nil?))
    issue.start_date = params[:issue][:start_date] if issue.safe_attribute?(:start_date) and (!(params[:issue][:start_date].nil?))
    issue.due_date = params[:issue][:due_date] if issue.safe_attribute?(:due_date) and (!(params[:issue][:due_date].nil?))
    issue.custom_field_values = params[:issue][:custom_field_values] unless params[:issue][:custom_field_values].nil?
  end

  def move_issue_to_sprint(issue, sprint)
    issue.init_journal(User.current)
    issue.sprint = sprint
    issue.save!
    issue.children.each do |child|
      unless child.closed?
        move_issue_to_sprint(child, sprint)
      end
    end
  end

end
