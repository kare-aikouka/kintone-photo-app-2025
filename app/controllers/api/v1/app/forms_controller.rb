module Api::V1::App
  class FormsController < ::Api::V1::ApiController
    # GET /v1/app/form/fields
    def fields
      logger.info form_params

      app_id = form_params['app']
      guest_id = form_params['guest_id']
      @fields = ::KintoneSync::App::Form.new(app_id, guest_id)
      res = @fields.fields
      render json: res
    end

    # GET /v1/app/form/layout
    def layout
      logger.info form_params

      app_id = form_params['app']
      guest_id = form_params['guest_id']
      @fields = ::KintoneSync::App::Form.new(app_id, guest_id)
      res = @fields.layout
      render json: res
    end

    private

    # Only allow a trusted parameter "white list" through.
    def form_params
      params.permit(:app, :guest_id, :format)
    end
  end
end
