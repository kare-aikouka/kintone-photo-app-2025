# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  include Account::Helper
  helper_method :body_css_classes

  def authentication
    redirect_to sign_in_path(backto: request.fullpath) unless signed_in?
  end

  private

  def body_css_classes
    [
      "controller-#{controller_name.dasherize}",
      "action-#{action_name.dasherize}",
      ("signed-in" if signed_in?)
    ].compact.join(' ')
  end
end
