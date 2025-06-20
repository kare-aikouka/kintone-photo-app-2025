class PhotosController < ApplicationController
  before_action :authentication

  def index
  end

  def show
    @page_title = '施工写真詳細'
  end
end
