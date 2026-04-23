require 'base64'

module KintoneSync
  class Client
    attr_accessor :app_id, :guest_space_id, :host
    delegate :logger, to: :Rails

    def initialize(app_id = nil, params = {})
      @host = params[:host] || ENV['KINTONE_HOST']
      @app_id = app_id.try! :to_i
      @guest_space_id = params[:guest].try! :to_i
    end

    def connection
      @connection ||= Faraday.new(url: "https://#{@host}") do |builder|
        builder.request :json
        builder.response :json, parser_options: { symbolize_names: false }
        
        if ENV["KINTONE_API_TOKEN_#{@app_id}"]
          builder.headers['X-Cybozu-API-Token'] = ENV["KINTONE_API_TOKEN_#{@app_id}"]
        elsif ENV['KINTONE_API_TOKEN']
          builder.headers['X-Cybozu-API-Token'] = ENV['KINTONE_API_TOKEN']
        else
          builder.headers['X-Cybozu-Authorization'] = Base64.strict_encode64("#{ENV['KINTONE_USER']}:#{ENV['KINTONE_PASS']}")
        end

        if ENV['KINTONE_BASIC_USER'] && ENV['KINTONE_BASIC_PASS']
          builder.request :authorization, :basic, ENV['KINTONE_BASIC_USER'], ENV['KINTONE_BASIC_PASS']
        end
        builder.adapter Faraday.default_adapter
      end
    end

    def api_url(path)
      base = @guest_space_id ? "/k/guest/#{@guest_space_id}/v1" : "/k/v1"
      "#{base}/#{path}"
    end
    
    def get(path, params = {})
      res = connection.get(api_url(path), params)
      raise "Kintone API Error: #{res.body}" unless res.success?
      res.body
    end

    def post(path, body = {})
      res = connection.post(api_url(path), body)
      raise "Kintone API Error: #{res.body}" unless res.success?
      res.body
    end

    def put(path, body = {})
      res = connection.put(api_url(path), body)
      raise "Kintone API Error: #{res.body}" unless res.success?
      res.body
    end
  end
end
