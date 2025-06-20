module KintoneSync::App
  class Form < ::KintoneSync::Base
    def fields
      url = api_url('/v1/app/form/fields.json')
      logger.info "fields: #{url}, #{app_id}"
      api.get(url, app: app_id)
    end

    def layout
      url = api_url('/v1/app/form/layout.json')
      logger.info "fields: #{url}, #{app_id}"
      api.get(url, app: app_id)
    end
  end
end
