# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

resources :projects do
  resources :sprints, :shallow => true do
    member do
      get :edit_effort
      post :update_effort
      get :burndown
      get :burndown_graph
      get :stats
      post :sort
    end
    collection do
      get :burndown_index
      get :stats_index
    end
  end
  post "sprints/change_issue_status",
       :controller => :sprints, :action => :change_issue_status,
       :as => :sprints_change_issue_status

  resources :product_backlog, :shallow => true do
    member do
      post :sort
      post :create_pbi
      get :burndown
      get :burndown_graph
      get :check_dependencies
      get :release_plan
    end
  end
  get "product_backlog/new_pbi/:tracker_id",
      :controller => :product_backlog, :action => :new_pbi,
      :as => :product_backlog_new_pbi

  get "scrum/stats",
      :controller => :scrum, :action => :stats,
      :as => :scrum_stats

end

post "issues/:id/story_points",
     :controller => :scrum, :action => :change_story_points,
     :as => :change_story_points
post "issues/:id/remaining_story_points",
     :controller => :scrum, :action => :change_remaining_story_points,
     :as => :change_remaining_story_points
post "issues/:id/pending_effort",
     :controller => :scrum, :action => :change_pending_effort,
     :as => :change_pending_effort
post "issues/:id/pending_efforts",
     :controller => :scrum, :action => :change_pending_efforts,
     :as => :change_pending_efforts
post "issues/:id/assigned_to",
     :controller => :scrum, :action => :change_assigned_to,
     :as => :change_assigned_to
get "issues/:id/time_entry",
     :controller => :scrum, :action => :new_time_entry,
     :as => :new_scrum_time_entry
post "issues/:id/time_entry",
     :controller => :scrum, :action => :create_time_entry,
     :as => :create_scrum_time_entry
get "scrum/:sprint_id/new_pbi/:tracker_id",
     :controller => :scrum, :action => :new_pbi,
     :as => :new_pbi
post "scrum/:sprint_id/create_pbi",
     :controller => :scrum, :action => :create_pbi,
     :as => :create_pbi
get "scrum/:pbi_id/new/:tracker_id",
    :controller => :scrum, :action => :new_task,
    :as => :new_task
post "scrum/:pbi_id/create_task",
     :controller => :scrum, :action => :create_task,
     :as => :create_task
get "scrum/:pbi_id/edit_pbi",
    :controller => :scrum, :action => :edit_pbi,
    :as => :edit_pbi
post "scrum/:pbi_id/update_pbi",
     :controller => :scrum, :action => :update_pbi,
     :as => :update_pbi
get "scrum/:pbi_id/move/:position",
    :controller => :scrum, :action => :move_pbi,
    :as => :move_pbi
get "scrum/:id/edit_task",
    :controller => :scrum, :action => :edit_task,
    :as => :edit_task
post "scrum/:id/update_task",
     :controller => :scrum, :action => :update_task,
     :as => :update_task
post "scrum/:pbi_id/move_to_last_sprint",
     :controller => :scrum, :action => :move_to_last_sprint,
     :as => :move_to_last_sprint
post "scrum/:sprint_id/move_not_closed_pbis_to_last_sprint",
     :controller => :scrum, :action => :move_not_closed_pbis_to_last_sprint,
     :as => :move_not_closed_pbis_to_last_sprint
post "scrum/:pbi_id/move_to_product_backlog",
     :controller => :scrum, :action => :move_to_product_backlog,
     :as => :move_to_product_backlog
