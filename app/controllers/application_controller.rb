# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  include Account::Helper
  helper_method :app_home_path, :app_shell_context_label, :app_shell_primary_label,
                :app_shell_secondary_label, :body_css_classes, :show_app_shell?,
                :show_debug_panels?

  def authentication
    redirect_to sign_in_path(backto: request.fullpath) unless signed_in?
  end

  private

  def app_home_path
    signed_in? ? router_path : root_path
  end

  def app_shell_primary_label
    return unless signed_in?

    current_account.record.company.presence || current_account.record.group.presence || 'Kintone Photo'
  end

  def app_shell_secondary_label
    return unless signed_in?

    current_account.record.team.presence || current_account.record.user.presence || current_account.record.email
  end

  def app_shell_context_label
    return unless signed_in?

    current_account.record.eigyosyo.presence || current_account.record.area.presence || current_account.record.group
  end

  def body_css_classes
    [
      "controller-#{controller_name.dasherize}",
      "action-#{action_name.dasherize}",
      ("signed-in" if signed_in?)
    ].compact.join(' ')
  end

  def show_app_shell?
    signed_in? && !(controller_name == 'accounts' && action_name == 'sign_in')
  end

  def show_debug_panels?
    params[:debug].to_s == '1'
  end
end
