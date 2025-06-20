module Api::V1
  class FilesController < ApiController
    # GET /v1/file
    def show
      app_id = file_params['app']
      guest_id = file_params['guest_id']
      file_key = file_params['fileKey']
      @file = ::KintoneSync::File.new(app_id, guest_id)
      res = @file.download(file_key)
      # logger.info MIME.check(res)
      send_data res, type: 'image/*', disposition: 'inline'
    end

    # POST /v1/file
    def create
      app_id = file_params['app']
      guest_id = file_params['guest_id']
      f = file_params['file']
      content = {
        data: f.tempfile.read,
        content_type: f.content_type,
        filename: f.original_filename
      }
      @file = ::KintoneSync::File.new(app_id, guest_id)
      file_key = @file.upload(content)
      render json: { "fileKey": file_key }
    end

    private

    # Only allow a trusted parameter "white list" through.
    def file_params
      params.permit(:app, :guest_id, :file, :fileKey, :format)
    end
  end
end
