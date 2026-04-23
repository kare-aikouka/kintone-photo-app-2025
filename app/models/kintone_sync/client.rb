require 'base64'

module KintoneSync
  class Client
    attr_accessor :app_id, :guest_space_id, :host
    delegate :logger, to: :Rails

    def initialize(app_id = nil, params = {})
      @host = normalize_host(params[:host] || ENV['KINTONE_HOST'])
      @app_id = app_id.try! :to_i
      @guest_space_id = params[:guest].presence&.to_i
    end

    def connection
      raise "KINTONE_HOST is not configured." if @host.blank?

      @connection ||= Faraday.new(url: "https://#{@host}") do |builder|
        builder.options.open_timeout = 5
        builder.options.timeout = 20
        builder.request :json
        builder.response :json, parser_options: { symbolize_names: false }

        if ENV["KINTONE_API_TOKEN_#{@app_id}"].present?
          builder.headers['X-Cybozu-API-Token'] = ENV["KINTONE_API_TOKEN_#{@app_id}"]
        elsif ENV['KINTONE_API_TOKEN'].present?
          builder.headers['X-Cybozu-API-Token'] = ENV['KINTONE_API_TOKEN']
        else
          raise "KINTONE_API_TOKEN or KINTONE_USER/KINTONE_PASS is not configured." if ENV['KINTONE_USER'].blank? || ENV['KINTONE_PASS'].blank?

          builder.headers['X-Cybozu-Authorization'] = Base64.strict_encode64("#{ENV['KINTONE_USER']}:#{ENV['KINTONE_PASS']}")
        end

        if ENV['KINTONE_BASIC_USER'].present? && ENV['KINTONE_BASIC_PASS'].present?
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

    private

    def normalize_host(host)
      host.to_s.strip.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')
    end
  end
end
