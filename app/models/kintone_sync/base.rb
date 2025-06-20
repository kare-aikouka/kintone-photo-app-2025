module KintoneSync
  class Base
    class ApplicationNotPermit < StandardError; end

    delegate :logger, to: :Rails
    attr_accessor :client, :name, :app_id, :guest_space_id
    attr_accessor :fields

    def initialize(app_id, guest_space_id = nil)
      authenticate(app_id)

      self.app_id = app_id
      self.guest_space_id = guest_space_id

      self.client = Client.new(
        app_id,
        host: ENV['KINTONE_HOST'],
        user: ENV['KINTONE_USER'],
        pass: ENV['KINTONE_PASS'],
        basic_user: ENV['KINTONE_BASIC_USER'],
        basic_pass: ENV['KINTONE_BASIC_PASS'],
        guest: guest_space_id
      )
    end

    def api
      client.api
    end

    def api_url(path)
      client.api_url(path)
    end

    def properties
      fields['properties']
    end

    def fields
      @__fields_cache ||= {}
      @__fields_cache[app_id] ||= begin
        url = api_url('/v1/app/form/fields.json')
        api.get(url, { app: app_id })
      end
    end

    private

    def authenticate(app_id)
      return unless app_id

      @permit_apps ||= ENV['PERMIT_APPS'].split(',').map(&:to_i)

      unless @permit_apps.include?(app_id.try!(:to_i))
        raise ApplicationNotPermit, "アプリID #{app_id}のアプリへのアクセスが許可されていません。"
      end
    end
  end
end
