# Copyright © Emilio González Montaña
# Licence: Attribution & no derivatives
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivatives of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class RenameDeviationToSpeedSettings < ActiveRecord::Migration[4.2]
  def self.up
    change_speed_settings render_pbis_deviations: :render_pbis_speed,
                          render_tasks_deviations: :render_tasks_speed,
                          major_deviation_ratio: :lowest_speed,
                          minor_deviation_ratio: :low_speed,
                          below_deviation_ratio: :high_speed
  end

  def self.down
    change_speed_settings render_pbis_speed: :render_pbis_deviations,
                          render_tasks_speed: :render_tasks_deviations,
                          lowest_speed: :major_deviation_ratio,
                          low_speed: :minor_deviation_ratio,
                          high_speed: :below_deviation_ratio
  end

private

  def self.change_speed_settings(settings)
    if (plugin_settings = Setting.where(name: 'plugin_scrum').first)
      if (values = plugin_settings.value)
        settings.each_pair { |key, value|
          change_speed_setting(values, key, value)
        }
        plugin_settings.value = values
        plugin_settings.save!
      end
    end
  end

  def self.change_speed_setting(settings, old_setting, new_setting)
    if settings[old_setting]
      old_setting_value = settings[old_setting].to_i
      if old_setting_value > 0
        settings[new_setting] = (10000 / old_setting_value).to_s
        settings.delete(old_setting)
      end
    end
  end
end