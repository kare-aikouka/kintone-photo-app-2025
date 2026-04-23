require 'base64'

module KintoneSync
  class File < Base
    def download(file_key)
      response = raw_connection.get(api_url('file.json'), fileKey: file_key)
      raise "Kintone file download failed: #{response.status} #{response.body}" unless response.success?

      response.body
    end

    def upload(params)
      filename = params[:filename]

      res = nil
      Tempfile.create filename, encoding: 'ascii-8bit' do |f|
        f.write(params[:data])
        f.flush
        f.path
        res = api.file.register(f.path, params[:content_type], params[:filename])
      end
      # logger.info "upload: #{res}"
      res
    end

    private

    def raw_connection
      @raw_connection ||= Faraday.new(url: "https://#{host}") do |builder|
        builder.options.open_timeout = 5
        builder.options.timeout = 30
        configure_auth_headers(builder)
        builder.adapter Faraday.default_adapter
      end
    end

    def host
      ENV['KINTONE_HOST'].to_s.strip.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')
    end

    def api_url(path)
      base = guest_space_id.present? ? "/k/guest/#{guest_space_id}/v1" : "/k/v1"
      "#{base}/#{path}"
    end

    def configure_auth_headers(builder)
      token = ENV["KINTONE_API_TOKEN_#{app_id}"].presence || ENV['KINTONE_API_TOKEN'].presence
      if token.present?
        builder.headers['X-Cybozu-API-Token'] = token
      elsif ENV['KINTONE_USER'].present? && ENV['KINTONE_PASS'].present?
        builder.headers['X-Cybozu-Authorization'] = Base64.strict_encode64("#{ENV['KINTONE_USER']}:#{ENV['KINTONE_PASS']}")
      end

      if ENV['KINTONE_BASIC_USER'].present? && ENV['KINTONE_BASIC_PASS'].present?
        builder.request :authorization, :basic, ENV['KINTONE_BASIC_USER'], ENV['KINTONE_BASIC_PASS']
      end
    end
  end
end
