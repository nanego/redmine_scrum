# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

require_dependency 'calendars_controller'

module Scrum
  module CalendarsControllerPatch
    def self.included(base)
      base.class_eval do

        around_filter :add_sprints, :only => [:show]

        def add_sprints
          yield
          view = ActionView::Base.new(File.join(File.dirname(__FILE__), '..', '..', 'app', 'views'))
          view.class_eval do
            include ApplicationHelper
          end
          sprints = []
          query_sprints(sprints, @query, @calendar, true)
          query_sprints(sprints, @query, @calendar, false)
          response.body += view.render(:partial => 'scrum_hooks/calendars/sprints',
                                       :locals => {:sprints => sprints})
        end

      private

        def query_sprints(sprints, query, calendar, start)
          date_field = start ? 'sprint_start_date' : 'sprint_end_date'
          query.sprints.where(date_field => calendar.startdt..calendar.enddt,
                              is_product_backlog: false).each do |sprint|
            sprints << {:name => sprint.name,
                        :url => url_for(:controller => :sprints,
                                        :action => :show,
                                        :id => sprint.id,
                                        :only_path => true),
                        :day => sprint.send(date_field).day,
                        :week => sprint.send(date_field).cweek,
                        :start => start}
          end
        end

      end
    end
  end
end
