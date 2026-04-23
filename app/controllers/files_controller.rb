# frozen_string_literal: true

class FilesController < ApplicationController
  def index
    expires_in 24.hour
    key = params[:key]
    type = params[:type].presence || 'image/jpeg'
    send_data download(key), type: type, disposition: :inline
  end

  private

  def download(file_key)
    @@__kintone ||= KintoneSync::File.new(
      ENV["APP_PHOTOS"].presence || ENV["APP_PHOTO"].presence || 779,
      ENV["GUEST_SPACE"].presence || 57
    )
    @@__kintone.download(file_key)
  end
end
