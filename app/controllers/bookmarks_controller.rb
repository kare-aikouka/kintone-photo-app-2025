class BookmarksController < ApplicationController
  before_action :authentication

  def show
    redirect_to router_path
  end

  def create
    redirect_to router_path
  end
end
