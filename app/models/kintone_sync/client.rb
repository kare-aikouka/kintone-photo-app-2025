module KintoneSync
  class Client
    attr_accessor :app_id, :guest_space_id, :host
    delegate :logger, to: :Rails

    def initialize(app_id = nil, params = {})
      self.host = params[:host]
      user = params[:user]
      pass = params[:pass]
      basic_user = params[:basic_user]
      basic_pass = params[:basic_pass]

      @app_id = app_id.try! :to_i
      @guest_space_id = params[:guest].try! :to_i

      credentials = [host, user, pass]
      credentials += [basic_user, basic_pass] if basic_user.present?

      @api = ::Kintone::Api.new(*credentials)
      @host = host
    end

    def api
      !@guest_space_id ? @api : @api.guest(@guest_space_id)
    end

    def api_url(path)
      if !guest_space_id
        "/k/#{path}"
      else
        "/k/guest/#{guest_space_id}/#{path}"
      end
    end
  end
end
