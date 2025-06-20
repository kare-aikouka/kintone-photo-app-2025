module Api::V1
  class ApiController < ActionController::Base
    before_action :api_authenticate

    class HttpTokenInvalid < StandardError; end

    protected

    rescue_from StandardError, with: :render_500

    def render_500(e = nil)
      if e
        logger.error e
        logger.error e.backtrace.join("\n")
      end

      map = { status: 500, error: e.class.name, exception: e.to_s }
      render json: map.to_json, status: 500
    end

    def api_authenticate
      unless authenticate_token
        raise HttpTokenInvalid, 'HTTP Token: Access denied.'
      end
    end

    def authenticate_token
      authenticate_with_http_token do |token, _options|
        # logger.info "authenticate:#{token}, #{ENV['API_TOKEN']}"
        token == ENV['API_TOKEN']
      end
    end
  end
end
