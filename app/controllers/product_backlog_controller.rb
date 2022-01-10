# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ProductBacklogController < ApplicationController

  menu_item :product_backlog
  model_object Sprint

  before_action :find_model_object,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :release_plan, :stats, :sort, :check_dependencies]
  before_action :find_project_from_association,
                :only => [:show, :edit, :update, :destroy, :edit_effort, :update_effort, :burndown,
                          :release_plan, :stats, :sort, :check_dependencies]
  before_action :find_project_by_project_id,
                :only => [:index, :new, :create]
  before_action :find_subprojects,
                :only => [:show, :burndown, :release_plan]
  before_action :filter_by_project,
                :only => [:show, :burndown, :release_plan]
  before_action :check_issue_positions, :only => [:show]
  before_action :calculate_stats, :only => [:show, :burndown, :release_plan]
  before_action :authorize

  helper :scrum

  def index
    unless @project.product_backlogs.empty?
      redirect_to product_backlog_path(@project.product_backlogs.first)
    else
      render_error l(:error_no_sprints)
    end
  rescue
    render_404
  end

  def show
    unless @product_backlog.is_product_backlog?
      render_404
    end
  end

  def sort
    # First, detect dependent issues.
    error_messages = []
    the_pbis = @product_backlog.pbis
    the_pbis.each do |pbi|
      pbi.init_journal(User.current)
      pbi.position = params['pbi'].index(pbi.id.to_s) + 1
      message = pbi.check_bad_dependencies(false)
      error_messages << message unless message.nil?
    end

    if error_messages.empty?
      # No dependency issue, we can sort.
      the_pbis.each do |pbi|
        pbi.save!
      end
    end

    respond_to do |format|
      format.json {render :json => error_messages.to_json}
    end
  end

  def check_dependencies
    @pbis_dependencies = @product_backlog.get_dependencies
    respond_to do |format|
      format.js
    end
  end

  def new_pbi
    @pbi = Issue.new
    @pbi.project = @project
    @pbi.author = User.current
    @pbi.tracker = @project.trackers.find(params[:tracker_id])
    @pbi.sprint = @product_backlog
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create_pbi
    begin
      @continue = !(params[:create_and_continue].nil?)
      @pbi = Issue.new(params[:issue])
      @pbi.project = @project
      @pbi.author = User.current
      @pbi.sprint = @product_backlog
      @pbi.save!
      @pbi.story_points = params[:issue][:story_points]
    rescue Exception => @exception
    end
    respond_to do |format|
      format.js
    end
  end

  MAX_SERIES = 10

  def burndown
    if @pbi_filter and @pbi_filter[:filter_by_project] == 'without-total'
      @pbi_filter.delete(:filter_by_project)
      without_total = true
    end
    @only_one = @project.children.visible.empty?
    if @pbi_filter and @pbi_filter[:filter_by_project] == 'only-total'
      @pbi_filter.delete(:filter_by_project)
      @only_one = true
    end
    @x_axis_labels = []
    all_projects_serie = burndown_for_project(@product_backlog, @project, l(:label_all), @pbi_filter, nil, @x_axis_labels)
    @sprints_count = all_projects_serie[:sprints_count]
    @velocity = all_projects_serie[:velocity]
    @velocity_type = all_projects_serie[:velocity_type]
    @series = []
    @series << all_projects_serie unless without_total
    if Scrum::Setting.product_burndown_extra_sprints == 0
      extra_sprints = nil
    else
      extra_sprints = all_projects_serie[:data].length - @project.sprints.length
      extra_sprints += Scrum::Setting.product_burndown_extra_sprints
    end
    unless @only_one
      if @pbi_filter.empty? and @subprojects.count > 2
        sub_series = recursive_burndown(@product_backlog, @project, extra_sprints)
        @series += sub_series
      end
      @series.sort! { |serie_1, serie_2|
        closed = ((serie_1[:project].respond_to?('closed?') and serie_1[:project].closed?) ? 1 : 0) -
                 ((serie_2[:project].respond_to?('closed?') and serie_2[:project].closed?) ? 1 : 0)
        if 0 != closed
          closed
        else
          serie_2[:pending_story_points] <=> serie_1[:pending_story_points]
        end
      }
    end
    if @series.count > MAX_SERIES
      @warning = l(:label_limited_to_n_series, :n => MAX_SERIES)
      @series = @series.first(MAX_SERIES)
    end
  end

  def release_plan
    @sprints = []
    velocity_all_pbis, velocity_scheduled_pbis, @sprints_count = @project.story_points_per_sprint(@pbi_filter)
    @velocity_type = params[:velocity_type] || 'only_scheduled'
    case @velocity_type
      when 'all'
        @velocity = velocity_all_pbis
      when 'only_scheduled'
        @velocity = velocity_scheduled_pbis
      else
        @velocity = params[:custom_velocity].to_f unless params[:custom_velocity].blank?
    end
    @velocity = 1.0 if @velocity.blank? or @velocity < 1.0
    @total_story_points = 0.0
    @pbis_with_estimation = 0
    @pbis_without_estimation = 0
    versions = {}
    accumulated_story_points = @velocity
    current_sprint = {:pbis => [], :story_points => 0.0, :versions => []}
    @product_backlog.pbis(@pbi_filter).each do |pbi|
      if pbi.story_points
        @pbis_with_estimation += 1
        story_points = pbi.story_points.to_f
        @total_story_points += story_points
        while accumulated_story_points < story_points
          @sprints << current_sprint
          accumulated_story_points += @velocity
          current_sprint = {:pbis => [], :story_points => 0.0, :versions => []}
        end
        accumulated_story_points -= story_points
        current_sprint[:pbis] << pbi
        current_sprint[:story_points] += story_points
        if pbi.fixed_version
          versions[pbi.fixed_version.id] = {:version => pbi.fixed_version,
                                            :sprint => @sprints.count}
        end
      else
        @pbis_without_estimation += 1
      end
    end
    if current_sprint and (current_sprint[:pbis].count > 0)
      @sprints << current_sprint
    end
    versions.values.each do |info|
      @sprints[info[:sprint]][:versions] << info[:version]
    end
  end

private

  def check_issue_positions
    check_issue_position(Issue.where(:sprint_id => @product_backlog, :position => nil))
  end

  def check_issue_position(issue)
    if issue.is_a?(Issue)
      if issue.position.nil?
        issue.reset_positions_in_list
        issue.save!
        issue.reload
      end
    elsif issue.respond_to?(:each)
      issue.each do |i|
        check_issue_position(i)
      end
    else
      raise "Invalid type: #{issue.inspect}"
    end
  end

  def find_subprojects
    if @project and @product_backlog
      @subprojects = [[l(:label_all), calculate_path(@product_backlog)]]
      @subprojects << [l(:label_only_total), calculate_path(@product_backlog, 'only-total')] if action_name == 'burndown'
      @subprojects << [l(:label_all_but_total), calculate_path(@product_backlog, 'without-total')] if action_name == 'burndown'
      @subprojects += find_recursive_subprojects(@project, @product_backlog)
    end
  end

  def find_recursive_subprojects(project, product_backlog, tabs = '')
    options = [[tabs + project.name, calculate_path(product_backlog, project)]]
    project.children.visible.to_a.each do |child|
      options += find_recursive_subprojects(child, product_backlog, tabs + '» ')
    end
    return options
  end

  def filter_by_project
    @pbi_filter = {}
    unless params[:filter_by_project].blank?
      @pbi_filter = {:filter_by_project => params[:filter_by_project]}
    end
  end

  def calculate_path(product_backlog, project = nil)
    options = {}
    if 'burndown' == action_name
      path_method = :burndown_product_backlog_path
    elsif 'release_plan' == action_name
      path_method = :release_plan_product_backlog_path
    else
      path_method = :product_backlog_path
    end
    if ['burndown', 'release_plan'].include?(action_name)
      options[:velocity_type] = params[:velocity_type] unless params[:velocity_type].blank?
      options[:custom_velocity] = params[:custom_velocity] unless params[:custom_velocity].blank?
    end
    if project.nil?
      project_id = nil
    elsif project == 'without-total'
      options[:filter_by_project] = 'without-total'
      project_id = 'without-total'
    elsif project == 'only-total'
      options[:filter_by_project] = 'only-total'
      project_id = 'only-total'
    else
      options[:filter_by_project] = project.id
      project_id = project.id.to_s
    end
    result = send(path_method, product_backlog, options)
    if (project.nil? and params[:filter_by_project].blank?) or
       (project_id == params[:filter_by_project])
      @selected_subproject = result
    end
    return result
  end

  def burndown_for_project(product_backlog, project, label, pbi_filter = {}, extra_sprints = nil, x_axis_labels = nil)
    serie = {:data => [],
             :label => label,
             :project => pbi_filter.include?(:filter_by_project) ?
                         Project.find(pbi_filter[:filter_by_project]) :
                         project}
    project.sprints.each do |sprint|
      x_axis_labels << sprint.name unless x_axis_labels.nil?
      serie[:data] << {:story_points => sprint.story_points(pbi_filter).round(2),
                       :pending_story_points => 0}
    end
    velocity_all_pbis, velocity_scheduled_pbis, serie[:sprints_count] = project.story_points_per_sprint(pbi_filter)
    serie[:velocity_type] = params[:velocity_type] || 'only_scheduled'
    case serie[:velocity_type]
      when 'all'
        serie[:velocity] = velocity_all_pbis
      when 'only_scheduled'
        serie[:velocity] = velocity_scheduled_pbis
      else
        serie[:velocity] = params[:custom_velocity].to_f unless params[:custom_velocity].blank?
    end
    serie[:velocity] = 1.0 if serie[:velocity].blank? or serie[:velocity] < 1.0
    pending_story_points = product_backlog.story_points(pbi_filter)
    serie[:pending_story_points] = pending_story_points
    new_sprints = 1
    while pending_story_points > 0 and (!extra_sprints or new_sprints <= extra_sprints)
      x_axis_labels << "#{l(:field_sprint)} +#{new_sprints}" unless x_axis_labels.nil?
      serie[:data] << {:story_points => ((serie[:velocity] <= pending_story_points) ?
                                         serie[:velocity] : pending_story_points).round(2),
                       :pending_story_points => 0}
      pending_story_points -= serie[:velocity]
      new_sprints += 1
    end
    for i in 0..(serie[:data].length - 1)
      others = serie[:data][(i + 1)..(serie[:data].length - 1)]
      serie[:data][i][:pending_story_points] = serie[:data][i][:story_points] +
          (others.blank? ? 0.0 : others.collect{|other| other[:story_points]}.sum.round(2))
      serie[:data][i][:story_points_tooltip] = l(:label_pending_story_points,
                                                 :pending_story_points => serie[:data][i][:pending_story_points],
                                                 :sprint => serie[:data][i][:axis_label],
                                                 :story_points => serie[:data][i][:story_points])
    end
    return serie
  end

  def recursive_burndown(product_backlog, project, extra_sprints)
    series = [burndown_for_project(@product_backlog, @project, project.name,
                                   {:filter_by_project => project.id}, extra_sprints)]
    project.children.visible.to_a.each do |child|
      series += recursive_burndown(product_backlog, child, extra_sprints)
    end
    return series
  end

  def serie_sps(serie, index)
    (serie[:data].count <= index) ? 0.0 : serie[:data][index][:story_points]
  end

  def calculate_stats
    if Scrum::Setting.show_project_totals_on_backlog
      total_pbis_count = @project.pbis_count(@pbi_filter)
      closed_pbis_count = @project.closed_pbis_count(@pbi_filter)
      total_sps_count = @project.total_sps(@pbi_filter)
      closed_sps_count = @project.closed_sps(@pbi_filter)
      closed_total_percentage = (total_sps_count == 0.0) ? 0.0 : ((closed_sps_count * 100.0) / total_sps_count)
      @stats = {:total_pbis_count => total_pbis_count,
                :closed_pbis_count => closed_pbis_count,
                :total_sps_count => total_sps_count,
                :closed_sps_count => closed_sps_count,
                :closed_total_percentage => closed_total_percentage}
    end
  end

end
