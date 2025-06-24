# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  include Account::Helper

  def authentication
    redirect_to sign_in_path(backto: request.fullpath) unless signed_in?
  end
end