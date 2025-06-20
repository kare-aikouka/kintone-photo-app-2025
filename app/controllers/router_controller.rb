# frozen_string_literal: true

class RouterController < ApplicationController
  before_action :authentication

  def index
    if current_account.group_employee?
      ActionLogger.info('router.success.employee', request, current_account)
      redirect_to machines_path
    else
      ActionLogger.info('router.success.team', request, current_account)
      machine = current_account.record.team
      redirect_to replace_uri photos_path(anchor: "machine-#{machine}")
    end
  end

  private

  def replace_uri(value)
    value = value.gsub(/\(/, '%28')
    value = value.gsub(/\)/, '%29')
    value
  end
end
