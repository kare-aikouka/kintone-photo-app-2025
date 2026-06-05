# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  DEFAULT_OPERATOR_LABEL = '會澤高圧コンクリート株式会社'.freeze
  INTERNAL_GROUP_LABELS = ['會澤社員'].freeze
  APP_VERSION_CODE = ENV.fetch('APP_VERSION', '260605').freeze
  APP_RELEASE_DATE = ENV.fetch('APP_RELEASE_DATE', '2026-06-05').freeze

  protect_from_forgery with: :exception

  include Account::Helper
  helper_method :app_home_path, :app_shell_context_label,
                :app_shell_secondary_label, :body_css_classes, :show_app_shell?,
                :show_debug_panels?, :app_version_code, :app_version_label,
                :app_release_date

  def authentication
    redirect_to sign_in_path(backto: request.fullpath) unless signed_in?
  end

  private

  def app_home_path
    signed_in? ? router_path : root_path
  end

  def app_version_code
    APP_VERSION_CODE
  end

  def app_version_label
    "Ver.#{app_version_code}"
  end

  def app_release_date
    APP_RELEASE_DATE
  end

  def app_shell_primary_label
    return unless signed_in?

    current_account.record.company.presence || current_account.record.group.presence || 'Kintone Photo'
  end

  def app_shell_secondary_label
    return unless signed_in?

    allowed_companies = current_account.allowed_companies
    return allowed_companies.join(" / ") unless current_account.full_company_access?

    [
      current_account.record.company,
      current_account.record.team,
      current_account.record.eigyosyo,
      current_account.record.area
    ].find { |label| label.present? && INTERNAL_GROUP_LABELS.exclude?(label) } || DEFAULT_OPERATOR_LABEL
  end

  def app_shell_context_label
    return unless signed_in?

    current_account.record.eigyosyo.presence || current_account.record.area.presence
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
