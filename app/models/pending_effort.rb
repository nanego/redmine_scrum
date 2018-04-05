# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class PendingEffort < ActiveRecord::Base

  belongs_to :issue

  include Redmine::SafeAttributes
  safe_attributes :issue_id, :date, :effort
  attr_protected :id

end
